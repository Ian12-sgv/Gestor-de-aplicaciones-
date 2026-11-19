const $ = (selector, parent = document) => parent.querySelector(selector);
const sessionKey = "pdb-store.admin.session";
const state = { session: readSession(), apps: [], selectedId: null, iconUrls: new Map() };

const loginView = $("#login-view");
const adminView = $("#admin-view");
const loginForm = $("#login-form");
const passwordForm = $("#password-form");
const authError = $("#auth-error");
const appList = $("#app-list");
const editor = $("#editor");
const toast = $("#toast");
const createDialog = $("#new-app-dialog");

function readSession() {
  try { return JSON.parse(sessionStorage.getItem(sessionKey) || "null"); } catch { return null; }
}

function saveSession() { sessionStorage.setItem(sessionKey, JSON.stringify(state.session)); }

function clearSession() {
  state.session = null;
  state.apps = [];
  state.selectedId = null;
  sessionStorage.removeItem(sessionKey);
  loginView.classList.remove("hidden");
  adminView.classList.add("hidden");
  passwordForm.classList.add("hidden");
  loginForm.classList.remove("hidden");
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
}

function labelForStatus(status) {
  return ({ ACTIVE: "Activa", DRAFT: "Borrador", DISABLED: "Desactivada", ARCHIVED: "Archivada" })[status] || status;
}

function showToast(message, isError = false) {
  toast.textContent = message;
  toast.classList.toggle("error", isError);
  toast.classList.add("visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => toast.classList.remove("visible"), 3600);
}

const errorTranslations = [
  [/^The APK belongs to package (\S+), but this app is (\S+)\./, (m) => `Este APK es del paquete ${m[1]}, pero esta aplicacion es ${m[2]}. Subelo en la aplicacion correcta.`],
  [/^Version code (\d+) already exists/, (m) => `La version con codigo ${m[1]} ya esta cargada. Para actualizar, genera el APK con un versionCode mayor.`],
  [/^The APK has versionCode (\d+)/, (m) => `El APK tiene el codigo ${m[1]}, distinto al indicado.`],
  [/^The file is not a readable Android APK/, () => "El archivo no es un APK de Android valido."],
  [/^An application with package (\S+) already exists/, (m) => `Ya existe una aplicacion con el paquete ${m[1]}.`],
  [/^An application with the same slug already exists/, () => "Ya existe una aplicacion con ese slug."],
  [/^Invalid credentials/i, () => "Usuario o contrasena incorrectos."],
];

function apiError(payload, fallback) {
  const message = payload?.error?.message || payload?.message || fallback;
  for (const [pattern, translate] of errorTranslations) { const match = String(message).match(pattern); if (match) return translate(match); }
  return message;
}

async function refreshSession() {
  if (!state.session?.refreshToken) return false;
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
}

async function api(path, options = {}, retried = false) {
  const headers = new Headers(options.headers || {});
  if (state.session?.accessToken) headers.set("Authorization", `Bearer ${state.session.accessToken}`);
  if (options.body && !(options.body instanceof FormData) && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...options, headers });
  if (response.status === 401 && !retried && await refreshSession()) return api(path, options, true);
  if (response.status === 401) { clearSession(); throw new Error("Tu sesion expiro. Inicia sesion nuevamente."); }
  const isJson = response.headers.get("content-type")?.includes("application/json");
  const payload = isJson ? await response.json() : null;
  if (!response.ok) throw new Error(apiError(payload, "No se pudo completar la operacion."));
  return payload;
}

function sendUpload(path, formData, onProgress) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open("POST", path);
    request.setRequestHeader("Authorization", `Bearer ${state.session?.accessToken || ""}`);
    request.upload.addEventListener("progress", (event) => { if (event.lengthComputable) onProgress(Math.round((event.loaded / event.total) * 100)); });
    request.addEventListener("load", () => { let payload = null; try { payload = JSON.parse(request.responseText); } catch { /* not JSON */ } resolve({ status: request.status, payload }); });
    request.addEventListener("error", () => reject(new Error("Se perdio la conexion mientras se subia el archivo.")));
    request.send(formData);
  });
}

// Large APKs take a while: use XHR so the admin sees real upload progress.
async function uploadWithProgress(path, formData, onProgress) {
  let result = await sendUpload(path, formData, onProgress);
  if (result.status === 401 && await refreshSession()) result = await sendUpload(path, formData, onProgress);
  if (result.status === 401) { clearSession(); throw new Error("Tu sesion expiro. Inicia sesion nuevamente."); }
  if (result.status < 200 || result.status >= 300) throw new Error(apiError(result.payload, "No se pudo subir el archivo."));
  return result.payload;
}

async function setUser() {
  const payload = await api("/api/auth/me");
  state.session.user = payload.user;
  saveSession();
  $("#user-name").textContent = payload.user.username || payload.user.email;
  $("#user-roles").textContent = (payload.user.roles || []).join(" / ");
}

async function enterAdmin() {
  authError.textContent = "";
  loginView.classList.add("hidden");
  adminView.classList.remove("hidden");
  await setUser();
  await loadApps();
}

function updateMetrics() {
  $("#metric-total").textContent = state.apps.length;
  $("#metric-active").textContent = state.apps.filter((app) => app.status === "ACTIVE").length;
  $("#metric-draft").textContent = state.apps.filter((app) => app.status === "DRAFT").length;
  $("#catalog-summary").textContent = `${state.apps.length} aplicacion${state.apps.length === 1 ? "" : "es"} administrable${state.apps.length === 1 ? "" : "s"}`;
}

async function getIconUrl(app) {
  const appId = app.id;
  if (!app.iconPath) return null;
  if (state.iconUrls.has(appId)) return state.iconUrls.get(appId);
  try {
    // Admin endpoint: the public one hides icons of apps that are not ACTIVE (drafts, disabled).
    const response = await fetch(`/api/admin/apps/${appId}/icon`, { headers: { Authorization: `Bearer ${state.session.accessToken}` } });
    if (!response.ok) return null;
    const url = URL.createObjectURL(await response.blob());
    state.iconUrls.set(appId, url);
    return url;
  } catch { return null; }
}

async function fillIcon(node, app) {
  const url = await getIconUrl(app);
  if (!url || !node.isConnected) return;
  node.innerHTML = `<img src="${url}" alt="" />`;
}

function renderApps() {
  updateMetrics();
  appList.innerHTML = "";
  if (state.apps.length === 0) {
    appList.innerHTML = '<div class="empty-state"><span>+</span><h2>Sin aplicaciones</h2><p>Crea la primera aplicacion para comenzar.</p></div>';
    return;
  }
  state.apps.forEach((app) => {
    const latest = app.versions?.[0];
    const card = document.createElement("button");
    card.type = "button";
    card.className = `app-card ${state.selectedId === app.id ? "selected" : ""}`;
    card.innerHTML = `<span class="app-icon">${escapeHtml(app.displayName.slice(0, 1).toUpperCase())}</span><span><span class="app-card-name">${escapeHtml(app.displayName)}</span><span class="app-card-package">${escapeHtml(app.packageName)}</span><span class="app-card-meta">${latest ? `v${escapeHtml(latest.versionName)} - ` : ""}${labelForStatus(app.status)}</span></span><span class="status-badge ${app.status.toLowerCase()}">${labelForStatus(app.status)}</span>`;
    card.addEventListener("click", () => { state.selectedId = app.id; renderApps(); renderEditor(); });
    appList.append(card);
    fillIcon($(".app-icon", card), app);
  });
}

function currentApp() { return state.apps.find((app) => app.id === state.selectedId) || null; }

function editorError(message = "") { const node = $("[data-editor-error]", editor); if (node) node.textContent = message; }

function renderEditor() {
  const app = currentApp();
  if (!app) {
    editor.className = "editor-panel empty";
    editor.innerHTML = '<div class="empty-state"><span>+</span><h2>Selecciona una aplicacion</h2><p>Desde aqui podras modificar sus datos, imagen, APK y estado.</p></div>';
    return;
  }
  const fragment = $("#editor-template").content.cloneNode(true);
  editor.className = "editor-panel";
  editor.replaceChildren(fragment);
  $("[data-name]", editor).textContent = app.displayName;
  $("[data-package]", editor).textContent = app.packageName;
  const icon = $("[data-icon-preview]", editor);
  icon.textContent = app.displayName.slice(0, 1).toUpperCase();
  fillIcon(icon, app);
  const status = $("[data-status]", editor);
  status.value = app.status;
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
    ? `No aparece en la PDB Store de los celulares porque su estado es "${labelForStatus(app.status)}". Cambialo a "Activa" para publicarla.`
    : !hasApk ? "Esta activa pero aun no tiene APK: los celulares no la veran hasta que subas uno." : "";
  notice.textContent = visibilityMessage;
  notice.classList.toggle("hidden", !visibilityMessage);
  const versions = $("[data-versions]", editor);
  versions.innerHTML = app.versions?.length ? app.versions.map((version) => `<div class="version-row"><strong>${escapeHtml(version.versionName)}</strong><span>codigo ${version.versionCode}${version.isMandatory ? " - Obligatoria" : ""}</span></div>`).join("") : '<p class="muted">Aun no hay APKs cargados.</p>';
  bindEditor(app);
}

function jsonBody(data) { return JSON.stringify(data); }

function bindEditor(app) {
  $("[data-status]", editor).addEventListener("change", async (event) => {
    try { await api(`/api/admin/apps/${app.id}/status`, { method: "PATCH", body: jsonBody({ status: event.target.value }) }); showToast("Estado actualizado."); await loadApps(app.id); } catch (error) { editorError(error.message); }
  });
  $("[data-edit-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault(); editorError(); const form = event.currentTarget;
    const data = { displayName: form.displayName.value.trim(), slug: form.slug.value.trim(), shortDescription: form.shortDescription.value.trim() || null, description: form.description.value.trim() || null, category: form.category.value.trim() || null, requiresExplicitAccess: form.requiresExplicitAccess.checked };
    try { await api(`/api/admin/apps/${app.id}`, { method: "PATCH", body: jsonBody(data) }); showToast("Datos guardados."); await loadApps(app.id); } catch (error) { editorError(error.message); }
  });
  $("[data-icon-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault(); const form = event.currentTarget; const body = new FormData(form);
    try { await api(`/api/admin/apps/${app.id}/icon`, { method: "POST", body }); state.iconUrls.delete(app.id); showToast("Icono actualizado."); await loadApps(app.id); } catch (error) { editorError(error.message); }
  });
  $("[data-delete-icon]", editor).addEventListener("click", async () => {
    if (!window.confirm("Quitar el icono de esta aplicacion?")) return;
    try { await api(`/api/admin/apps/${app.id}/icon`, { method: "DELETE" }); const url = state.iconUrls.get(app.id); if (url) URL.revokeObjectURL(url); state.iconUrls.delete(app.id); showToast("Icono retirado."); await loadApps(app.id); } catch (error) { editorError(error.message); }
  });
  $("[data-version-form]", editor).addEventListener("submit", async (event) => {
    event.preventDefault(); editorError(); const form = event.currentTarget; const body = new FormData(form); body.set("isMandatory", form.isMandatory.checked ? "true" : "false");
    const button = $('button[type="submit"]', form); const progress = $("[data-upload-progress]", form);
    button.disabled = true; button.textContent = "Subiendo APK..."; progress.value = 0; progress.classList.remove("hidden");
    try {
      const payload = await uploadWithProgress(`/api/admin/apps/${app.id}/versions`, body, (percent) => { progress.value = percent; button.textContent = percent < 100 ? `Subiendo APK... ${percent}%` : "Verificando APK..."; });
      form.reset();
      showToast(`Version ${payload.version.versionName} (codigo ${payload.version.versionCode}) cargada.`);
      if (app.status !== "ACTIVE" && window.confirm("El APK se cargo. Publicar la aplicacion ahora para que aparezca en la PDB Store de los celulares?")) {
        await api(`/api/admin/apps/${app.id}/status`, { method: "PATCH", body: jsonBody({ status: "ACTIVE" }) });
        showToast("Aplicacion publicada en la PDB Store.");
      }
      await loadApps(app.id);
    } catch (error) { editorError(error.message); } finally { if (button.isConnected) { button.disabled = false; button.textContent = "Subir APK"; progress.classList.add("hidden"); } }
  });
  $("[data-delete-app]", editor).addEventListener("click", async () => {
    if (!window.confirm(`Eliminar definitivamente ${app.displayName}? Tambien se eliminaran sus APKs, permisos e historial.`)) return;
    try { await api(`/api/admin/apps/${app.id}`, { method: "DELETE" }); const url = state.iconUrls.get(app.id); if (url) URL.revokeObjectURL(url); state.iconUrls.delete(app.id); state.selectedId = null; showToast("Aplicacion eliminada."); await loadApps(); } catch (error) { editorError(error.message); }
  });
}

async function loadApps(selectId = state.selectedId) {
  const payload = await api("/api/admin/apps");
  state.apps = payload.items || [];
  state.selectedId = state.apps.some((app) => app.id === selectId) ? selectId : state.apps[0]?.id || null;
  renderApps(); renderEditor();
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault(); authError.textContent = ""; const form = event.currentTarget;
  try {
    const payload = await fetch("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: jsonBody({ identifier: form.identifier.value.trim(), password: form.password.value }) });
    const data = await payload.json(); if (!payload.ok) throw new Error(apiError(data, "No fue posible iniciar sesion."));
    state.session = { accessToken: data.accessToken, refreshToken: data.refreshToken, user: data.user }; saveSession();
    if (data.user.passwordMustChange) { loginForm.classList.add("hidden"); passwordForm.classList.remove("hidden"); return; }
    await enterAdmin();
  } catch (error) { authError.textContent = error.message; }
});

passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault(); authError.textContent = ""; const form = event.currentTarget;
  try { const payload = await api("/api/auth/change-password", { method: "POST", body: jsonBody({ currentPassword: form.currentPassword.value, newPassword: form.newPassword.value }) }); state.session.user = payload.user; saveSession(); await enterAdmin(); } catch (error) { authError.textContent = error.message; }
});

$("#new-app-button").addEventListener("click", () => { $("#new-app-error").textContent = ""; createDialog.showModal(); });
document.querySelectorAll("[data-close-dialog]").forEach((button) => button.addEventListener("click", () => createDialog.close()));
$("#new-app-form").addEventListener("submit", async (event) => {
  event.preventDefault(); const form = event.currentTarget; const error = $("#new-app-error"); error.textContent = "";
  const data = { displayName: form.displayName.value.trim(), packageName: form.packageName.value.trim(), slug: form.slug.value.trim() || undefined, shortDescription: form.shortDescription.value.trim() || undefined, category: form.category.value.trim() || undefined, requiresExplicitAccess: form.requiresExplicitAccess.checked, status: "DRAFT" };
  try { const payload = await api("/api/admin/apps", { method: "POST", body: jsonBody(data) }); form.reset(); createDialog.close(); showToast("Borrador creado. Ahora puedes cargar su icono y APK."); await loadApps(payload.app.id); } catch (err) { error.textContent = err.message; }
});

$("#refresh-button").addEventListener("click", () => loadApps().then(() => showToast("Catalogo actualizado.")).catch((error) => showToast(error.message, true)));
$("#logout-button").addEventListener("click", async () => { try { if (state.session?.refreshToken) await api("/api/auth/logout", { method: "POST", body: jsonBody({ refreshToken: state.session.refreshToken }) }); } catch { /* Session is cleared locally regardless. */ } clearSession(); });

if (state.session?.accessToken) {
  enterAdmin().catch((error) => { clearSession(); authError.textContent = error.message; });
}
