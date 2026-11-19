"use strict";

const $ = (selector, parent = document) => parent.querySelector(selector);
const $$ = (selector, parent = document) => [...parent.querySelectorAll(selector)];

const SESSION_KEY = "pdb-store.admin.session";
const STATUS_LABELS = { ACTIVE: "Activa", DRAFT: "Borrador", DISABLED: "Desactivada", ARCHIVED: "Archivada" };
const ROLE_LABELS = { SUPER_ADMIN: "Super administrador", ADMIN: "Administrador", APP_ADMIN: "Administrador de apps", EMPLOYEE: "Empleado" };
const ROLE_ORDER = ["EMPLOYEE", "APP_ADMIN", "ADMIN", "SUPER_ADMIN"];
const ACTION_LABELS = { DOWNLOAD: "Descarga", INSTALL: "Instalación", UPDATE: "Actualización", OPEN: "Apertura", REMOVE: "Desinstalación" };
const RESULT_LABELS = { PENDING: "Pendiente", SUCCESS: "Correcto", FAILED: "Fallido" };
const VIEWS = { aplicaciones: "apps", usuarios: "users", instalaciones: "logs" };

const state = {
  session: readSession(),
  apps: [],
  users: null,
  selectedId: null,
  iconUrls: new Map(),
  view: "apps",
};

const loginView = $("#login-view");
const adminView = $("#admin-view");
const loginForm = $("#login-form");
const passwordForm = $("#password-form");
const authError = $("#auth-error");
const appList = $("#app-list");
const editor = $("#editor");
const toast = $("#toast");

// ---------------------------------------------------------------- utilidades

function readSession() {
  try {
    return JSON.parse(sessionStorage.getItem(SESSION_KEY) || "null");
  } catch {
    return null;
  }
}

function saveSession() {
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(state.session));
  } catch {
    /* almacenamiento no disponible: la sesión vive solo en memoria */
  }
}

function clearSession() {
  state.session = null;
  state.apps = [];
  state.users = null;
  state.selectedId = null;
  state.iconUrls.forEach((url) => URL.revokeObjectURL(url));
  state.iconUrls.clear();
  try {
    sessionStorage.removeItem(SESSION_KEY);
  } catch {
    /* ignorado */
  }
  loginView.classList.remove("hidden");
  adminView.classList.add("hidden");
  passwordForm.classList.add("hidden");
  loginForm.classList.remove("hidden");
  loginForm.reset();
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
}

const dateFormatter = new Intl.DateTimeFormat("es", { dateStyle: "medium", timeStyle: "short" });

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : dateFormatter.format(date);
}

function formatBytes(value) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes <= 0) return "";
  const units = ["B", "KB", "MB", "GB"];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function labelForStatus(status) {
  return STATUS_LABELS[status] || status;
}

function normalize(value) {
  return String(value ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

function showToast(message, isError = false) {
  toast.textContent = message;
  toast.classList.toggle("error", isError);
  toast.classList.add("visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => toast.classList.remove("visible"), 3800);
}

function can(permissionList) {
  const permissions = state.session?.user?.permissions;
  // Backends anteriores no envían permisos: el servidor sigue validando cada llamada.
  if (!Array.isArray(permissions)) return true;
  return permissionList.split(/\s+/).some((permission) => permissions.includes(permission));
}

function applyPermissions(root = document) {
  $$("[data-permission]", root).forEach((node) => {
    node.classList.toggle("hidden", !can(node.dataset.permission));
  });
}

// ---------------------------------------------------------------- errores

const FIELD_LABELS = {
  displayName: "nombre", packageName: "paquete", slug: "slug", email: "correo", username: "usuario",
  password: "contraseña", newPassword: "nueva contraseña", roleCodes: "roles", category: "categoría",
  shortDescription: "descripción corta", description: "descripción", changelog: "novedades",
};

const errorTranslations = [
  [/^The APK belongs to package (\S+), but this app is (\S+)\./, (m) => `Este APK es del paquete ${m[1]}, pero esta aplicación es ${m[2]}. Súbelo en la aplicación correcta.`],
  [/^Version code (\d+) already exists/, (m) => `La versión con código ${m[1]} ya está cargada. Para actualizar, genera el APK con un versionCode mayor.`],
  [/^The APK has versionCode (\d+)/, (m) => `El APK tiene el código ${m[1]}, distinto al indicado.`],
  [/^The file is not a readable Android APK/, () => "El archivo no es un APK de Android válido."],
  [/^An application with package (\S+) already exists/, (m) => `Ya existe una aplicación con el paquete ${m[1]}. Sube el APK como nueva versión de esa aplicación.`],
  [/^An application with the same slug already exists/, () => "Ya existe una aplicación con ese slug."],
  [/^A user with the same email or username already exists/, () => "Ya existe un usuario con ese correo o nombre de usuario."],
  [/^You cannot (change your own status|revoke your own access)/, () => "No puedes desactivar tu propia cuenta."],
  [/^Insufficient permissions/, () => "No tienes permiso para esta acción."],
  [/^Invalid credentials/i, () => "Usuario o contraseña incorrectos."],
  [/^User account is not active/i, () => "Tu cuenta está desactivada."],
  [/^Too many/i, () => "Demasiados intentos. Espera un momento e inténtalo de nuevo."],
];

function apiError(payload, fallback) {
  const message = payload?.error?.message || payload?.message || fallback;
  if (message === "Validation failed") {
    const fields = Object.keys(payload?.details?.fieldErrors || payload?.error?.details?.fieldErrors || {});
    const names = fields.map((field) => FIELD_LABELS[field] || field);
    return names.length ? `Revisa estos campos: ${names.join(", ")}.` : "Revisa los datos del formulario.";
  }
  for (const [pattern, translate] of errorTranslations) {
    const match = String(message).match(pattern);
    if (match) return translate(match);
  }
  return message;
}

// ---------------------------------------------------------------- red

async function refreshSession() {
  if (!state.session?.refreshToken) return false;
  if (!refreshSession.pending) {
    refreshSession.pending = (async () => {
      const response = await fetch("/api/auth/refresh", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refreshToken: state.session.refreshToken }),
      });
      if (!response.ok) return false;
      const payload = await response.json();
      state.session.accessToken = payload.accessToken;
      state.session.refreshToken = payload.refreshToken;
      saveSession();
      return true;
    })().finally(() => { refreshSession.pending = null; });
  }
  return refreshSession.pending;
}

async function api(path, options = {}, retried = false) {
  const headers = new Headers(options.headers || {});
  if (state.session?.accessToken) headers.set("Authorization", `Bearer ${state.session.accessToken}`);
  if (options.body && !(options.body instanceof FormData) && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...options, headers });
  if (response.status === 401 && !retried && await refreshSession()) return api(path, options, true);
  if (response.status === 401) {
    clearSession();
    throw new Error("Tu sesión expiró. Inicia sesión nuevamente.");
  }
  const isJson = response.headers.get("content-type")?.includes("application/json");
  const payload = isJson ? await response.json() : null;
  if (!response.ok) throw new Error(apiError(payload, "No se pudo completar la operación."));
  return payload;
}

function json(data) {
  return JSON.stringify(data);
}

function sendUpload(path, formData, onProgress) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open("POST", path);
    request.setRequestHeader("Authorization", `Bearer ${state.session?.accessToken || ""}`);
    request.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) onProgress(Math.round((event.loaded / event.total) * 100));
    });
    request.addEventListener("load", () => {
      let payload = null;
      try { payload = JSON.parse(request.responseText); } catch { /* no es JSON */ }
      resolve({ status: request.status, payload });
    });
    request.addEventListener("error", () => reject(new Error("Se perdió la conexión mientras se subía el archivo.")));
    request.send(formData);
  });
}

// Los APK grandes tardan: XHR permite mostrar el progreso real de la subida.
async function uploadWithProgress(path, formData, onProgress) {
  let result = await sendUpload(path, formData, onProgress);
  if (result.status === 401 && await refreshSession()) result = await sendUpload(path, formData, onProgress);
  if (result.status === 401) {
    clearSession();
    throw new Error("Tu sesión expiró. Inicia sesión nuevamente.");
  }
  if (result.status < 200 || result.status >= 300) throw new Error(apiError(result.payload, "No se pudo subir el archivo."));
  return result.payload;
}

// ---------------------------------------------------------------- componentes

function setupPasswordToggles(root = document) {
  $$("[data-toggle-password]", root).forEach((button) => {
    button.addEventListener("click", () => {
      const input = $("input", button.parentElement);
      const reveal = input.type === "password";
      input.type = reveal ? "text" : "password";
      button.textContent = reveal ? "Ocultar" : "Mostrar";
      button.setAttribute("aria-label", reveal ? "Ocultar contraseña" : "Mostrar contraseña");
    });
  });
}

function setupDropzone(zone) {
  const input = $("input[type=file]", zone);
  const hint = $("[data-dropzone-hint]", zone);
  const defaultHint = hint.textContent;
  const refresh = () => {
    const file = input.files?.[0];
    zone.classList.toggle("has-file", Boolean(file));
    hint.textContent = file ? `${file.name} · ${formatBytes(file.size)}` : defaultHint;
  };
  ["dragenter", "dragover"].forEach((type) => zone.addEventListener(type, (event) => {
    event.preventDefault();
    zone.classList.add("dragging");
  }));
  ["dragleave", "drop"].forEach((type) => zone.addEventListener(type, () => zone.classList.remove("dragging")));
  zone.addEventListener("drop", (event) => {
    event.preventDefault();
    const file = event.dataTransfer?.files?.[0];
    if (!file) return;
    if (!file.name.toLowerCase().endsWith(".apk")) {
      showToast("Solo se aceptan archivos .apk.", true);
      return;
    }
    const transfer = new DataTransfer();
    transfer.items.add(file);
    input.files = transfer.files;
    refresh();
  });
  input.addEventListener("change", refresh);
  input.form?.addEventListener("reset", () => window.setTimeout(refresh));
}

function requireFile(form, name, message) {
  if (form[name]?.files?.length) return true;
  throw new Error(message);
}

function closeOnBackdrop(dialog) {
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });
  $$("[data-close-dialog]", dialog).forEach((button) => button.addEventListener("click", () => dialog.close()));
}

closeOnBackdrop($("#confirm-dialog"));

/** Pide escribir un texto exacto antes de una acción destructiva. */
function confirmTyped({ title, message, expected, actionLabel = "Eliminar" }) {
  const dialog = $("#confirm-dialog");
  const form = $("#confirm-form");
  const submit = $("button[type=submit]", form);
  $("[data-confirm-title]", dialog).textContent = title;
  $("[data-confirm-message]", dialog).textContent = message;
  $("[data-confirm-expected]", dialog).textContent = expected;
  submit.textContent = actionLabel;
  form.reset();
  submit.disabled = true;
  return new Promise((resolve) => {
    const onInput = () => { submit.disabled = form.confirmation.value.trim() !== expected; };
    const onSubmit = (event) => {
      event.preventDefault();
      if (form.confirmation.value.trim() !== expected) return;
      dialog.returnValue = "confirm";
      dialog.close();
    };
    const onClose = () => {
      form.confirmation.removeEventListener("input", onInput);
      form.removeEventListener("submit", onSubmit);
      resolve(dialog.returnValue === "confirm");
    };
    dialog.returnValue = "";
    form.confirmation.addEventListener("input", onInput);
    form.addEventListener("submit", onSubmit);
    dialog.addEventListener("close", onClose, { once: true });
    dialog.showModal();
    form.confirmation.focus();
  });
}

async function withBusy(button, busyLabel, task) {
  const label = button.textContent;
  button.disabled = true;
  button.textContent = busyLabel;
  try {
    return await task();
  } finally {
    if (button.isConnected) {
      button.disabled = false;
      button.textContent = label;
    }
  }
}

// ---------------------------------------------------------------- sesión y navegación

async function setUser() {
  const payload = await api("/api/auth/me");
  state.session.user = payload.user;
  saveSession();
  const { user } = payload;
  const fullName = [user.firstName, user.lastName].filter(Boolean).join(" ");
  $("#user-name").textContent = fullName || user.username || user.email;
  $("#user-roles").textContent = (user.roles || []).map((role) => ROLE_LABELS[role] || role).join(" · ");
  applyPermissions();
}

async function enterAdmin() {
  authError.textContent = "";
  loginView.classList.add("hidden");
  adminView.classList.remove("hidden");
  await setUser();
  await showView(VIEWS[location.hash.slice(1)] || "apps", { force: true });
}

async function showView(view, { force = false } = {}) {
  const link = $(`[data-nav="${view}"]`);
  if (!link || link.classList.contains("hidden")) view = "apps";
  if (state.view === view && !force) return;
  state.view = view;
  $$("[data-view]").forEach((section) => section.classList.toggle("hidden", section.dataset.view !== view));
  $$("[data-nav]").forEach((item) => item.classList.toggle("active", item.dataset.nav === view));
  try {
    if (view === "apps") await loadApps();
    if (view === "users") await loadUsers();
    if (view === "logs") await loadLogs();
  } catch (error) {
    showToast(error.message, true);
  }
}

window.addEventListener("hashchange", () => {
  if (state.session?.user) showView(VIEWS[location.hash.slice(1)] || "apps");
});

// ---------------------------------------------------------------- aplicaciones

function appMatchesFilter(app, filter) {
  const hasApk = Boolean(app.versions?.length);
  if (filter === "ACTIVE" || filter === "DRAFT") return app.status === filter;
  if (filter === "INACTIVE") return app.status === "DISABLED" || app.status === "ARCHIVED";
  if (filter === "NO_APK") return !hasApk;
  return true;
}

function updateMetrics() {
  const count = (filter) => state.apps.filter((app) => appMatchesFilter(app, filter)).length;
  $('[data-metric="total"]').textContent = state.apps.length;
  $('[data-metric="active"]').textContent = count("ACTIVE");
  $('[data-metric="draft"]').textContent = count("DRAFT");
  $('[data-metric="inactive"]').textContent = count("INACTIVE");
  const noApk = count("NO_APK");
  $('[data-metric="noApk"]').textContent = noApk;
  $('[data-filter="NO_APK"]').classList.toggle("is-zero", noApk === 0);
  const filter = $("#app-filter").value;
  $$("#metrics .metric").forEach((metric) => metric.classList.toggle("selected", metric.dataset.filter === filter));
}

function visibleApps() {
  const query = normalize($("#app-search").value.trim());
  const filter = $("#app-filter").value;
  return state.apps.filter((app) => appMatchesFilter(app, filter)
    && (!query || normalize(`${app.displayName} ${app.packageName} ${app.category || ""}`).includes(query)));
}

async function getIconUrl(app) {
  if (!app.iconPath) return null;
  const cacheKey = `${app.id}:${app.iconPath}`;
  if (state.iconUrls.has(cacheKey)) return state.iconUrls.get(cacheKey);
  try {
    // Endpoint de admin: el público oculta iconos de apps que no están activas.
    const response = await fetch(`/api/admin/apps/${app.id}/icon`, { headers: { Authorization: `Bearer ${state.session.accessToken}` } });
    if (!response.ok) return null;
    const url = URL.createObjectURL(await response.blob());
    state.iconUrls.set(cacheKey, url);
    return url;
  } catch {
    return null;
  }
}

async function fillIcon(node, app) {
  const url = await getIconUrl(app);
  if (!url || !node.isConnected) return;
  const image = document.createElement("img");
  image.src = url;
  image.alt = "";
  node.replaceChildren(image);
}

function renderApps() {
  updateMetrics();
  const apps = visibleApps();
  const total = state.apps.length;
  $("#catalog-summary").textContent = apps.length === total
    ? `${total} ${total === 1 ? "aplicación" : "aplicaciones"}`
    : `${apps.length} de ${total} aplicaciones`;
  appList.replaceChildren();
  if (total === 0) {
    appList.innerHTML = '<div class="empty-state"><span>+</span><h2>Sin aplicaciones</h2><p>Crea la primera aplicación a partir de su APK.</p></div>';
    return;
  }
  if (apps.length === 0) {
    appList.innerHTML = '<div class="empty-state"><span>?</span><h2>Sin resultados</h2><p>Ninguna aplicación coincide con la búsqueda o el filtro.</p></div>';
    return;
  }
  apps.forEach((app) => {
    const latest = app.versions?.[0];
    const card = document.createElement("button");
    card.type = "button";
    card.className = `app-card ${state.selectedId === app.id ? "selected" : ""}`;
    const meta = [
      latest ? `v${escapeHtml(latest.versionName)}` : '<span class="warn-text">Sin APK</span>',
      app.category ? escapeHtml(app.category) : "",
      app.requiresExplicitAccess ? "Acceso restringido" : "",
    ].filter(Boolean).join(" · ");
    card.innerHTML = `
      <span class="app-icon">${escapeHtml(app.displayName.slice(0, 1).toUpperCase())}</span>
      <span class="app-card-body">
        <span class="app-card-name">${escapeHtml(app.displayName)}</span>
        <span class="app-card-package">${escapeHtml(app.packageName)}</span>
        <span class="app-card-meta">${meta}</span>
      </span>
      <span class="status-badge ${app.status.toLowerCase()}">${labelForStatus(app.status)}</span>`;
    card.addEventListener("click", () => {
      state.selectedId = app.id;
      renderApps();
      renderEditor();
      if (window.matchMedia("(max-width: 980px)").matches) editor.scrollIntoView({ behavior: "smooth", block: "start" });
    });
    appList.append(card);
    fillIcon($(".app-icon", card), app);
  });
}

function currentApp() {
  return state.apps.find((app) => app.id === state.selectedId) || null;
}

function editorError(message = "") {
  const node = $("[data-editor-error]", editor);
  if (node) node.textContent = message;
}

function renderEditor() {
  const app = currentApp();
  if (!app) {
    editor.className = "editor-panel empty";
    editor.innerHTML = '<div class="empty-state"><span>+</span><h2>Selecciona una aplicación</h2><p>Desde aquí podrás cambiar sus datos, icono, APK, accesos y estado.</p></div>';
    return;
  }

  // Conserva qué secciones estaban abiertas al volver a pintar la misma app.
  const openSections = editor.dataset.appId === app.id
    ? $$("details.section", editor).map((section) => section.open)
    : null;

  editor.className = "editor-panel";
  editor.dataset.appId = app.id;
  editor.replaceChildren($("#editor-template").content.cloneNode(true));
  applyPermissions(editor);
  if (openSections) $$("details.section", editor).forEach((section, index) => { section.open = openSections[index] ?? section.open; });

  $("[data-name]", editor).textContent = app.displayName;
  $("[data-package]", editor).textContent = app.packageName;
  const icon = $("[data-icon-preview]", editor);
  icon.textContent = app.displayName.slice(0, 1).toUpperCase();
  fillIcon(icon, app);

  const status = $("[data-status]", editor);
  status.value = app.status;
  status.disabled = !can("app.status.update");
  const badge = $("[data-status-badge]", editor);
  badge.textContent = labelForStatus(app.status);
  badge.classList.add(app.status.toLowerCase());

  const form = $("[data-edit-form]", editor);
  form.displayName.value = app.displayName;
  form.slug.value = app.slug;
  form.shortDescription.value = app.shortDescription || "";
  form.description.value = app.description || "";
  form.category.value = app.category || "";
  form.requiresExplicitAccess.checked = app.requiresExplicitAccess;

  const notice = $("[data-visibility-notice]", editor);
  const hasApk = Boolean(app.versions?.length);
  const visibilityMessage = app.status !== "ACTIVE"
    ? `No aparece en la PDB Store de los celulares porque su estado es «${labelForStatus(app.status)}». Cámbialo a «Activa» para publicarla.`
    : !hasApk ? "Está activa pero aún no tiene APK: los celulares no la verán hasta que subas uno." : "";
  notice.textContent = visibilityMessage;
  notice.classList.toggle("hidden", !visibilityMessage);

  renderVersions(app);
  setupDropzone($("[data-dropzone]", editor));
  bindEditor(app);

  const accessSection = $("[data-access-section]", editor);
  if (can("app.access.manage")) {
    if (accessSection.open) renderAccess(app);
    accessSection.addEventListener("toggle", () => { if (accessSection.open) renderAccess(app); });
  }
}

function renderVersions(app) {
  const container = $("[data-versions]", editor);
  if (!app.versions?.length) {
    container.innerHTML = '<p class="muted">Aún no hay APKs cargados.</p>';
    return;
  }
  const canToggle = can("app.version.mandatory.update");
  container.innerHTML = app.versions.map((version, index) => {
    const details = [
      `código ${version.versionCode}`,
      formatDate(version.releasedAt),
      formatBytes(version.fileSizeBytes),
      version.createdBy?.username ? `por ${escapeHtml(version.createdBy.username)}` : "",
    ].filter(Boolean).join(" · ");
    const changelog = version.changelog
      ? `<details class="changelog"><summary>Novedades</summary><p>${escapeHtml(version.changelog)}</p></details>`
      : "";
    return `
      <div class="version-row">
        <div class="version-main">
          <strong>${escapeHtml(version.versionName)}${index === 0 ? ' <span class="pill">Actual</span>' : ""}</strong>
          <span>${details}</span>
          ${changelog}
        </div>
        <label class="switch" title="Los celulares deberán instalar esta versión">
          <input type="checkbox" data-mandatory="${escapeHtml(version.id)}" ${version.isMandatory ? "checked" : ""} ${canToggle ? "" : "disabled"} />
          <span>Obligatoria</span>
        </label>
      </div>`;
  }).join("");

  $$("[data-mandatory]", container).forEach((input) => {
    input.addEventListener("change", async () => {
      input.disabled = true;
      try {
        await api(`/api/admin/versions/${input.dataset.mandatory}/mandatory`, { method: "PATCH", body: json({ isMandatory: input.checked }) });
        showToast(input.checked ? "La versión ahora es obligatoria." : "La versión ya no es obligatoria.");
        await loadApps(app.id);
      } catch (error) {
        input.checked = !input.checked;
        input.disabled = false;
        editorError(error.message);
      }
    });
  });
}

async function ensureUsers() {
  if (!state.users) {
    const payload = await api("/api/admin/users");
    state.users = payload.items || [];
  }
  return state.users;
}

async function renderAccess(app) {
  const container = $("[data-access]", editor);
  if (!container) return;
  container.innerHTML = '<p class="muted">Cargando accesos…</p>';
  try {
    const [access, users] = await Promise.all([api(`/api/admin/apps/${app.id}/access`), ensureUsers()]);
    if (!container.isConnected) return;
    const roleRows = ROLE_ORDER.map((roleCode) => {
      const permission = access.roles.find((entry) => entry.roleCode === roleCode);
      return accessRow({ key: `role:${roleCode}`, label: ROLE_LABELS[roleCode], permission });
    }).join("");
    const grantedIds = new Set(access.users.map((entry) => entry.user.id));
    const userRows = access.users.length
      ? access.users.map((entry) => accessRow({
        key: `user:${entry.user.id}`,
        label: entry.user.username,
        sublabel: entry.user.status === "ACTIVE" ? entry.user.email : `${entry.user.email} · desactivado`,
        permission: entry,
        removable: true,
      })).join("")
      : '<p class="muted small">Ningún usuario tiene acceso individual.</p>';
    const options = users
      .filter((user) => !grantedIds.has(user.id) && user.status === "ACTIVE")
      .map((user) => `<option value="${escapeHtml(user.id)}">${escapeHtml(user.username)} · ${escapeHtml(user.email)}</option>`)
      .join("");

    container.innerHTML = `
      ${app.requiresExplicitAccess
        ? '<p class="muted">Solo ven esta app los roles y usuarios marcados aquí.</p>'
        : '<p class="notice">Esta app es visible para todos. Los accesos de abajo solo se aplican si activas «Requiere autorización explícita» en Información.</p>'}
      <h4>Por rol</h4>
      <div class="access-list">${roleRows}</div>
      <h4>Por usuario</h4>
      <div class="access-list">${userRows}</div>
      ${options ? `<div class="add-access"><select data-add-user aria-label="Usuario"><option value="">Agregar usuario…</option>${options}</select><button type="button" class="button secondary small" data-add-user-button>Agregar</button></div>` : ""}`;

    $$("[data-access-row]", container).forEach((row) => {
      const view = $('[data-flag="canView"]', row);
      const install = $('[data-flag="canInstall"]', row);
      const save = (canView, canInstall) => saveAccess(app, row.dataset.accessRow, { canView, canInstall });
      view.addEventListener("change", () => {
        if (!view.checked) install.checked = false;
        save(view.checked, install.checked);
      });
      install.addEventListener("change", () => {
        if (install.checked) view.checked = true;
        save(view.checked, install.checked);
      });
      $("[data-remove-access]", row)?.addEventListener("click", () => save(false, false));
    });
    $("[data-add-user-button]", container)?.addEventListener("click", () => {
      const userId = $("[data-add-user]", container).value;
      if (userId) saveAccess(app, `user:${userId}`, { canView: true, canInstall: true });
    });
  } catch (error) {
    container.innerHTML = `<p class="form-error">${escapeHtml(error.message)}</p>`;
  }
}

function accessRow({ key, label, sublabel = "", permission, removable = false }) {
  return `
    <div class="access-row" data-access-row="${escapeHtml(key)}">
      <div><strong>${escapeHtml(label)}</strong>${sublabel ? `<span>${escapeHtml(sublabel)}</span>` : ""}</div>
      <label class="checkbox"><input type="checkbox" data-flag="canView" ${permission?.canView ? "checked" : ""} /> Ver</label>
      <label class="checkbox"><input type="checkbox" data-flag="canInstall" ${permission?.canInstall ? "checked" : ""} /> Instalar</label>
      ${removable ? '<button type="button" class="text-button danger" data-remove-access>Quitar</button>' : ""}
    </div>`;
}

async function saveAccess(app, key, flags) {
  const [kind, id] = key.split(":");
  const path = kind === "role"
    ? `/api/admin/apps/${app.id}/roles/${encodeURIComponent(id)}/access`
    : `/api/admin/apps/${app.id}/users/${encodeURIComponent(id)}/access`;
  try {
    await api(path, { method: "PUT", body: json(flags) });
    showToast(flags.canView || flags.canInstall ? "Acceso actualizado." : "Acceso retirado.");
  } catch (error) {
    showToast(error.message, true);
  }
  renderAccess(app);
}

function bindEditor(app) {
  const status = $("[data-status]", editor);
  status.addEventListener("change", async () => {
    const next = status.value;
    const hasApk = Boolean(app.versions?.length);
    let question = null;
    if (app.status === "ACTIVE") question = `«${app.displayName}» dejará de aparecer en la PDB Store de todos los celulares. ¿Cambiar a «${labelForStatus(next)}»?`;
    else if (next === "ACTIVE" && !hasApk) question = "La app aún no tiene APK: se publicará, pero los celulares no la verán hasta que subas uno. ¿Continuar?";
    else if (next === "ACTIVE") question = `¿Publicar «${app.displayName}» en la PDB Store de los celulares?`;
    if (question && !window.confirm(question)) {
      status.value = app.status;
      return;
    }
    status.disabled = true;
    try {
      await api(`/api/admin/apps/${app.id}/status`, { method: "PATCH", body: json({ status: next }) });
      showToast("Estado actualizado.");
      await loadApps(app.id);
    } catch (error) {
      status.value = app.status;
      status.disabled = false;
      editorError(error.message);
    }
  });

  $("[data-edit-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault();
    editorError();
    const form = event.currentTarget;
    const data = {
      displayName: form.displayName.value.trim(),
      slug: form.slug.value.trim(),
      shortDescription: form.shortDescription.value.trim() || null,
      description: form.description.value.trim() || null,
      category: form.category.value.trim() || null,
      requiresExplicitAccess: form.requiresExplicitAccess.checked,
    };
    await withBusy($("button[type=submit]", form), "Guardando…", async () => {
      try {
        await api(`/api/admin/apps/${app.id}`, { method: "PATCH", body: json(data) });
        showToast("Datos guardados.");
        await loadApps(app.id);
      } catch (error) {
        editorError(error.message);
      }
    });
  });

  $("[data-icon-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault();
    editorError();
    const form = event.currentTarget;
    try {
      requireFile(form, "icon", "Elige una imagen para el icono.");
      await withBusy($("button[type=submit]", form), "Subiendo…", async () => {
        await api(`/api/admin/apps/${app.id}/icon`, { method: "POST", body: new FormData(form) });
        showToast("Icono actualizado.");
        await loadApps(app.id);
      });
    } catch (error) {
      editorError(error.message);
    }
  });

  $("[data-delete-icon]", editor).addEventListener("click", async () => {
    if (!app.iconPath) {
      showToast("Esta aplicación no tiene icono.");
      return;
    }
    if (!window.confirm("¿Quitar el icono de esta aplicación?")) return;
    try {
      await api(`/api/admin/apps/${app.id}/icon`, { method: "DELETE" });
      showToast("Icono retirado.");
      await loadApps(app.id);
    } catch (error) {
      editorError(error.message);
    }
  });

  $("[data-version-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault();
    editorError();
    const form = event.currentTarget;
    try {
      requireFile(form, "apkFile", "Elige o arrastra un archivo APK.");
    } catch (error) {
      editorError(error.message);
      return;
    }
    const body = new FormData(form);
    body.set("isMandatory", form.isMandatory.checked ? "true" : "false");
    const button = $("button[type=submit]", form);
    const progress = $("[data-upload-progress]", form);
    button.disabled = true;
    button.textContent = "Subiendo APK…";
    progress.value = 0;
    progress.classList.remove("hidden");
    try {
      const payload = await uploadWithProgress(`/api/admin/apps/${app.id}/versions`, body, (percent) => {
        progress.value = percent;
        button.textContent = percent < 100 ? `Subiendo APK… ${percent}%` : "Verificando APK…";
      });
      form.reset();
      showToast(`Versión ${payload.version.versionName} (código ${payload.version.versionCode}) cargada.`);
      if (app.status !== "ACTIVE" && can("app.status.update")
        && window.confirm("El APK se cargó. ¿Publicar la aplicación ahora para que aparezca en la PDB Store de los celulares?")) {
        await api(`/api/admin/apps/${app.id}/status`, { method: "PATCH", body: json({ status: "ACTIVE" }) });
        showToast("Aplicación publicada en la PDB Store.");
      }
      await loadApps(app.id);
    } catch (error) {
      editorError(error.message);
    } finally {
      if (button.isConnected) {
        button.disabled = false;
        button.textContent = "Subir APK";
        progress.classList.add("hidden");
      }
    }
  });

  $("[data-delete-app]", editor).addEventListener("click", async () => {
    const confirmed = await confirmTyped({
      title: `Eliminar ${app.displayName}`,
      message: "Se eliminarán definitivamente la aplicación, todos sus APKs, permisos e historial de instalaciones. Si solo quieres ocultarla, cambia su estado a «Archivada».",
      expected: app.packageName,
    });
    if (!confirmed) return;
    try {
      await api(`/api/admin/apps/${app.id}`, { method: "DELETE" });
      state.selectedId = null;
      showToast("Aplicación eliminada.");
      await loadApps();
    } catch (error) {
      editorError(error.message);
    }
  });
}

async function loadApps(selectId = state.selectedId) {
  const payload = await api("/api/admin/apps");
  state.apps = payload.items || [];
  state.selectedId = state.apps.some((app) => app.id === selectId) ? selectId : state.apps[0]?.id || null;
  renderApps();
  renderEditor();
}

$("#app-search").addEventListener("input", renderApps);
$("#app-filter").addEventListener("change", renderApps);
$$("#metrics .metric").forEach((metric) => metric.addEventListener("click", () => {
  const filter = $("#app-filter");
  filter.value = filter.value === metric.dataset.filter ? "ALL" : metric.dataset.filter;
  renderApps();
}));
$("#refresh-button").addEventListener("click", () => loadApps().then(() => showToast("Catálogo actualizado.")).catch((error) => showToast(error.message, true)));

// ---------------------------------------------------------------- nueva aplicación

const createDialog = $("#new-app-dialog");
const apkCreateForm = $("#new-app-apk-form");
const manualCreateForm = $("#new-app-form");
closeOnBackdrop(createDialog);
setupDropzone($("[data-dropzone]", apkCreateForm));

function setCreateMode(mode) {
  $$("[data-create-mode]", createDialog).forEach((tab) => tab.classList.toggle("active", tab.dataset.createMode === mode));
  apkCreateForm.classList.toggle("hidden", mode !== "apk");
  manualCreateForm.classList.toggle("hidden", mode !== "manual");
}

$$("[data-create-mode]", createDialog).forEach((tab) => tab.addEventListener("click", () => setCreateMode(tab.dataset.createMode)));

$("#new-app-button").addEventListener("click", () => {
  apkCreateForm.reset();
  manualCreateForm.reset();
  $$("[data-form-error]", createDialog).forEach((node) => { node.textContent = ""; });
  setCreateMode("apk");
  createDialog.showModal();
});

apkCreateForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const error = $("[data-form-error]", form);
  error.textContent = "";
  try {
    requireFile(form, "apkFile", "Elige o arrastra un archivo APK.");
  } catch (err) {
    error.textContent = err.message;
    return;
  }
  const body = new FormData(form);
  body.set("requiresExplicitAccess", form.requiresExplicitAccess.checked ? "true" : "false");
  const button = $("button[type=submit]", form);
  const progress = $("[data-upload-progress]", form);
  button.disabled = true;
  progress.value = 0;
  progress.classList.remove("hidden");
  try {
    const payload = await uploadWithProgress("/api/admin/apps/from-apk", body, (percent) => {
      progress.value = percent;
      button.textContent = percent < 100 ? `Subiendo… ${percent}%` : "Leyendo APK…";
    });
    createDialog.close();
    showToast(`Borrador «${payload.app.displayName}» creado con la versión ${payload.version.versionName}.`);
    $("#app-filter").value = "ALL";
    await loadApps(payload.app.id);
  } catch (err) {
    error.textContent = err.message;
  } finally {
    button.disabled = false;
    button.textContent = "Crear desde APK";
    progress.classList.add("hidden");
  }
});

manualCreateForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const error = $("[data-form-error]", form);
  error.textContent = "";
  const data = {
    displayName: form.displayName.value.trim(),
    packageName: form.packageName.value.trim(),
    slug: form.slug.value.trim() || undefined,
    shortDescription: form.shortDescription.value.trim() || undefined,
    category: form.category.value.trim() || undefined,
    requiresExplicitAccess: form.requiresExplicitAccess.checked,
    status: "DRAFT",
  };
  if (!data.displayName || !data.packageName) {
    error.textContent = "El nombre y el paquete son obligatorios.";
    return;
  }
  await withBusy($("button[type=submit]", form), "Creando…", async () => {
    try {
      const payload = await api("/api/admin/apps", { method: "POST", body: json(data) });
      createDialog.close();
      showToast("Borrador creado. Ahora puedes cargar su icono y APK.");
      $("#app-filter").value = "ALL";
      await loadApps(payload.app.id);
    } catch (err) {
      error.textContent = err.message;
    }
  });
});

// ---------------------------------------------------------------- usuarios

async function loadUsers() {
  state.users = null;
  await ensureUsers();
  renderUsers();
}

function renderUsers() {
  const rows = $("#user-rows");
  const query = normalize($("#user-search").value.trim());
  const filter = $("#user-filter").value;
  const users = (state.users || []).filter((user) => (filter === "ALL" || user.status === filter)
    && (!query || normalize(`${user.username} ${user.email} ${user.firstName || ""} ${user.lastName || ""}`).includes(query)));
  if (!users.length) {
    rows.innerHTML = '<tr><td colspan="6" class="empty-cell">No hay usuarios que coincidan.</td></tr>';
    return;
  }
  const selfId = state.session?.user?.userId;
  const canToggle = can("user.revoke");
  rows.innerHTML = users.map((user) => {
    const fullName = [user.firstName, user.lastName].filter(Boolean).join(" ");
    const active = user.status === "ACTIVE";
    const action = !canToggle || user.id === selfId
      ? ""
      : `<button type="button" class="text-button ${active ? "danger" : ""}" data-user-status="${escapeHtml(user.id)}" data-next="${active ? "DISABLED" : "ACTIVE"}">${active ? "Desactivar" : "Reactivar"}</button>`;
    return `
      <tr>
        <td><strong>${escapeHtml(user.username)}</strong><span class="cell-sub">${escapeHtml(fullName ? `${fullName} · ${user.email}` : user.email)}</span></td>
        <td>${user.roles.map((role) => `<span class="pill">${escapeHtml(ROLE_LABELS[role] || role)}</span>`).join(" ")}</td>
        <td><span class="status-badge ${active ? "active" : "disabled"}">${active ? "Activo" : "Desactivado"}</span>${user.passwordMustChange ? '<span class="cell-sub">Debe cambiar contraseña</span>' : ""}</td>
        <td>${formatDate(user.lastLoginAt)}</td>
        <td>${user.deviceCount}</td>
        <td class="actions-cell">${action}</td>
      </tr>`;
  }).join("");

  $$("[data-user-status]", rows).forEach((button) => button.addEventListener("click", async () => {
    const user = state.users.find((entry) => entry.id === button.dataset.userStatus);
    const next = button.dataset.next;
    const question = next === "DISABLED"
      ? `¿Desactivar a ${user.username}? Se cerrarán sus sesiones en todos los dispositivos y no podrá entrar a la tienda.`
      : `¿Reactivar a ${user.username}?`;
    if (!window.confirm(question)) return;
    await withBusy(button, "…", async () => {
      try {
        await api(`/api/admin/users/${user.id}/status`, { method: "PATCH", body: json({ status: next }) });
        showToast(next === "DISABLED" ? "Usuario desactivado y sesiones cerradas." : "Usuario reactivado.");
        await loadUsers();
      } catch (error) {
        showToast(error.message, true);
      }
    });
  }));
}

$("#user-search").addEventListener("input", renderUsers);
$("#user-filter").addEventListener("change", renderUsers);

const userDialog = $("#new-user-dialog");
const userForm = $("#new-user-form");
closeOnBackdrop(userDialog);

function generatePassword() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const values = crypto.getRandomValues(new Uint32Array(12));
  return [...values].map((value) => alphabet[value % alphabet.length]).join("");
}

$("[data-generate-password]", userForm).addEventListener("click", () => {
  userForm.password.value = generatePassword();
});

$("#new-user-button").addEventListener("click", () => {
  userForm.reset();
  userForm.password.value = generatePassword();
  $("[data-form-error]", userForm).textContent = "";
  userDialog.showModal();
});

userForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const error = $("[data-form-error]", userForm);
  error.textContent = "";
  const roleCodes = $$('input[name="roleCodes"]:checked', userForm).map((input) => input.value);
  const data = {
    email: userForm.email.value.trim(),
    username: userForm.username.value.trim(),
    password: userForm.password.value,
    firstName: userForm.firstName.value.trim() || undefined,
    lastName: userForm.lastName.value.trim() || undefined,
    roleCodes,
  };
  if (!roleCodes.length) {
    error.textContent = "Elige al menos un rol.";
    return;
  }
  if (data.password.length < 8) {
    error.textContent = "La contraseña temporal debe tener al menos 8 caracteres.";
    return;
  }
  await withBusy($("button[type=submit]", userForm), "Creando…", async () => {
    try {
      await api("/api/admin/users", { method: "POST", body: json(data) });
      userDialog.close();
      const copied = await navigator.clipboard?.writeText(`${data.username} / ${data.password}`).then(() => true, () => false);
      showToast(`Usuario ${data.username} creado.${copied ? " Credenciales copiadas al portapapeles." : ""}`);
      await loadUsers();
    } catch (err) {
      error.textContent = err.message;
    }
  });
});

// ---------------------------------------------------------------- instalaciones

const logFilters = $("#log-filters");

async function fillLogFilterOptions() {
  const appSelect = logFilters.appId;
  const userSelect = logFilters.userId;
  if (appSelect.options.length <= 1) {
    if (!state.apps.length) state.apps = (await api("/api/admin/apps")).items || [];
    appSelect.insertAdjacentHTML("beforeend", state.apps.map((app) => `<option value="${escapeHtml(app.id)}">${escapeHtml(app.displayName)}</option>`).join(""));
  }
  if (userSelect.options.length <= 1 && can("user.create user.revoke app.access.manage")) {
    const users = await ensureUsers().catch(() => []);
    userSelect.insertAdjacentHTML("beforeend", users.map((user) => `<option value="${escapeHtml(user.id)}">${escapeHtml(user.username)}</option>`).join(""));
  }
}

async function loadLogs() {
  await fillLogFilterOptions();
  const params = new URLSearchParams();
  new FormData(logFilters).forEach((value, key) => { if (value) params.set(key, String(value)); });
  const rows = $("#log-rows");
  rows.innerHTML = '<tr><td colspan="7" class="empty-cell">Cargando…</td></tr>';
  const payload = await api(`/api/admin/installation-logs?${params}`);
  const logs = payload.items || [];
  if (!logs.length) {
    rows.innerHTML = '<tr><td colspan="7" class="empty-cell">No hay registros con estos filtros.</td></tr>';
    return;
  }
  rows.innerHTML = logs.map((log) => {
    const version = log.appVersion ? `v${escapeHtml(log.appVersion.versionName)}` : log.requestedVersionCode ? `código ${log.requestedVersionCode}` : "";
    const statusClass = { SUCCESS: "active", FAILED: "disabled", PENDING: "draft" }[log.status] || "";
    return `
      <tr>
        <td class="nowrap">${formatDate(log.createdAt)}</td>
        <td><strong>${escapeHtml(log.app?.displayName || "—")}</strong><span class="cell-sub">${version}</span></td>
        <td>${escapeHtml(ACTION_LABELS[log.action] || log.action)}</td>
        <td><span class="status-badge ${statusClass}">${escapeHtml(RESULT_LABELS[log.status] || log.status)}</span></td>
        <td>${escapeHtml(log.user?.username || "—")}</td>
        <td>${escapeHtml(log.device?.name || log.device?.deviceIdentifier || "—")}</td>
        <td class="details-cell">${escapeHtml(log.details || "")}</td>
      </tr>`;
  }).join("");
}

logFilters.addEventListener("change", () => loadLogs().catch((error) => showToast(error.message, true)));
$("#refresh-logs-button").addEventListener("click", () => loadLogs().then(() => showToast("Registros actualizados.")).catch((error) => showToast(error.message, true)));

// ---------------------------------------------------------------- login

setupPasswordToggles();

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  authError.textContent = "";
  const form = event.currentTarget;
  const identifier = form.identifier.value.trim();
  if (!identifier || !form.password.value) {
    authError.textContent = "Escribe tu usuario y tu contraseña.";
    return;
  }
  await withBusy($("button[type=submit]", form), "Entrando…", async () => {
    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: json({ identifier, password: form.password.value }),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok) throw new Error(apiError(data, "No fue posible iniciar sesión."));
      state.session = { accessToken: data.accessToken, refreshToken: data.refreshToken, user: data.user };
      saveSession();
      if (data.user.passwordMustChange) {
        loginForm.classList.add("hidden");
        passwordForm.classList.remove("hidden");
        passwordForm.currentPassword.focus();
        return;
      }
      await enterAdmin();
    } catch (error) {
      authError.textContent = error.message;
      form.password.select();
    }
  });
});

passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  authError.textContent = "";
  const form = event.currentTarget;
  if (form.newPassword.value.length < 8) {
    authError.textContent = "La nueva contraseña debe tener al menos 8 caracteres.";
    return;
  }
  await withBusy($("button[type=submit]", form), "Guardando…", async () => {
    try {
      const payload = await api("/api/auth/change-password", {
        method: "POST",
        body: json({ currentPassword: form.currentPassword.value, newPassword: form.newPassword.value }),
      });
      if (payload?.accessToken) state.session.accessToken = payload.accessToken;
      if (payload?.refreshToken) state.session.refreshToken = payload.refreshToken;
      state.session.user = payload.user;
      saveSession();
      await enterAdmin();
    } catch (error) {
      authError.textContent = error.message;
    }
  });
});

$("#logout-button").addEventListener("click", async () => {
  try {
    if (state.session?.refreshToken) await api("/api/auth/logout", { method: "POST", body: json({ refreshToken: state.session.refreshToken }) });
  } catch {
    /* La sesión se limpia localmente de todos modos. */
  }
  clearSession();
});

if (state.session?.accessToken) {
  enterAdmin().catch((error) => {
    clearSession();
    authError.textContent = error.message;
  });
}
