# Seguridad

## Controles base

- `helmet` para cabeceras seguras.
- `cors` restringido al dominio de la app.
- Validacion de entrada con esquemas estrictos.
- `bcrypt` para hashing de contrasenas.
- Respuestas de error sin stack traces ni detalles internos.
- Rate limiting general y reforzado en autenticacion.

## Estrategia de sesion

- `accessToken` JWT de vida corta. Valor por defecto: `15m`.
- `refreshToken` opaco, rotativo y almacenado hasheado en SQL Server.
- Cada refresh invalida el token anterior y emite un nuevo par de tokens.
- Cada request autenticado rehidrata el usuario desde la base y valida:
  - que siga en estado `ACTIVE`
  - que `sessionVersion` siga vigente
  - que sus roles actuales sigan autorizados

## Politica de revocacion

Cuando un empleado deja de estar autorizado:

1. TI o administracion debe marcarlo como `DISABLED`.
2. Debe ejecutarse `POST /api/admin/users/:id/revoke-access`.
3. Esa operacion incrementa `sessionVersion` y revoca todos los refresh tokens activos.
4. El siguiente request autenticado del usuario queda invalidado inmediatamente.

Cuando el cambio es solo por permisos de apps:

- se revoca `AppUserPermission` o `AppRolePermission`
- el usuario deja de ver la app en el siguiente refresh del catalogo
- si tambien se necesita cerrar sesion, se usa la revocacion total anterior

## Control de permisos

Los permisos administrativos se centralizan en codigo y se derivan de roles. Las rutas no deben autorizarse por nombre de usuario ni por una condicion generica de "es admin".

Roles base:

- `SUPER_ADMIN`: control total, incluyendo borrado definitivo de apps.
- `ADMIN`: operacion administrativa general sin borrado definitivo de apps.
- `APP_ADMIN`: gestion de catalogo, versiones, estado y accesos de apps.
- `EMPLOYEE`: uso final del catalogo.

Capacidades principales:

- `app.catalog.bypass`: ve apps activas sin depender de permisos explicitos.
- `app.create`, `app.version.create`, `app.status.update`, `app.access.manage`, `app.version.mandatory.update`: administracion del catalogo.
- `app.delete`: borrado definitivo de app y archivos asociados.
- `user.create`, `user.revoke`: gestion de usuarios.
- `audit.log.read`: consulta de trazabilidad.
- `device.report.any`: reporte administrativo sobre dispositivos ajenos.

Reglas operativas:

- El borrado definitivo de apps queda reservado a `SUPER_ADMIN`.
- Las apps con `requiresExplicitAccess=false` son visibles e instalables por usuarios activos; para apps sensibles usar `requiresExplicitAccess=true`.
- Los permisos por usuario o rol (`canView`, `canInstall`) controlan visibilidad y descarga cuando una app requiere acceso explicito.

## Secretos

- En desarrollo se puede usar `.env`.
- En produccion los secretos deben inyectarse por el mecanismo del entorno del sistema o del orquestador.
- No persistir `JWT_SECRET`, `DATABASE_URL` ni credenciales operativas en archivos versionados.
- El backend rechaza arrancar en `production` si `JWT_SECRET` conserva el placeholder.
- `ALLOW_DOTENV_IN_PROD` solo debe usarse en pruebas controladas y temporales.

## Politica de contrasenas

- Los usuarios creados por administracion quedan con `passwordMustChange=true`.
- El usuario puede iniciar sesion con una contrasena temporal, pero no puede usar catalogo, dispositivos ni rutas admin hasta cambiarla.
- `POST /api/auth/change-password` exige la contrasena actual y una nueva contrasena.
- La nueva contrasena debe tener al menos 8 caracteres, minuscula, mayuscula, numero y simbolo.
- La nueva contrasena no puede contener el username ni la parte local del email.
- La nueva contrasena debe ser distinta de la actual.
- Al cambiarla correctamente se actualizan `passwordMustChange=false` y `passwordChangedAt`.

## Descargas de APK

- No servir APKs sensibles como archivos anonimos.
- Toda descarga debe pasar por el backend para validar permisos y dejar traza.
- Cada version debe guardar `sha256`, tamano y metadatos tecnicos.
- El catalogo no expone versiones cuyo APK ya no exista en `APK_STORAGE_DIR`.

## Observabilidad y auditoria

- Logs HTTP y de error en formato estructurado JSON.
- `GET /api/health` valida base de datos, storage de APKs y origen de configuracion.
- `InstallationLog` conserva acciones como `DOWNLOAD`, `INSTALL`, `UPDATE`, `OPEN` y `REMOVE`.
- Retencion recomendada:
  - auditoria en base de datos: 180 dias minimo, 365 dias recomendado
  - logs estructurados de aplicacion: 30 a 90 dias segun capacidad operativa

## Aislamiento

- Caddy es el unico punto expuesto.
- Node escucha solo en `127.0.0.1` en produccion.
- SQL Server no debe exponerse a internet.
- El almacenamiento de APKs debe vivir en disco privado o volumen restringido.
- El backend rechaza arranques productivos con bind publico, CORS abierto, storage relativo o `.env` habilitado.
- `TRUST_PROXY=loopback` es el valor esperado cuando Caddy esta en la misma maquina; no usar confianza global del proxy en produccion.

## Rate limiting y proxy

- El backend usa `req.ip`, calculado por Express segun `TRUST_PROXY`, para identificar clientes.
- No se debe leer ni confiar directamente en `x-forwarded-for` recibido desde internet.
- `POST /api/auth/login` se limita por IP resuelta e identificador normalizado.
- `POST /api/auth/refresh` se limita por IP resuelta.
- El limite general aplica a `/api/*`; `GET /api/health` queda fuera para monitoreo.
- `RATE_LIMIT_MAX_BUCKETS` acota la memoria usada por buckets y purga los menos recientes si se supera.
- Si se ejecutan multiples instancias del backend, el limitador en memoria debe sustituirse o complementarse con una capa compartida.
