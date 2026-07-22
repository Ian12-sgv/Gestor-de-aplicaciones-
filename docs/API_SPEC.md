# API Spec

## Convenciones

- Base path: `/api`
- Autenticacion: `Authorization: Bearer <JWT>`
- Content type: `application/json` excepto descargas de APK
- Rutas publicas: `GET /api/health`, `POST /api/auth/login`, `POST /api/auth/refresh`, `POST /api/auth/logout`
- Rutas privadas: todas las demas
- Rate limit headers:
  - `x-ratelimit-limit`
  - `x-ratelimit-remaining`
  - `x-ratelimit-reset`
  - `retry-after` en respuestas `429`
- Error shape base:

```json
{
  "message": "Validation failed",
  "details": {}
}
```

## Health

### `GET /api/health`

Valida backend, base de datos y storage de APKs.

Response:

```json
{
  "status": "ok",
  "timestamp": "2026-04-23T18:00:00.000Z",
  "service": "corporate-app-store-api",
  "environment": "production",
  "configSource": "runtime-environment",
  "uptimeSeconds": 8421,
  "checks": {
    "database": {
      "status": "ok",
      "latencyMs": 12
    },
    "apkStorage": {
      "status": "ok",
      "path": "/opt/private-store/apks",
      "isDirectory": true,
      "writable": true
    }
  },
  "session": {
    "accessTokenTtl": "15m",
    "refreshTokenTtlDays": 30,
    "revocationStrategy": "Immediate revocation via sessionVersion, user status and refresh token rotation"
  },
  "rateLimit": {
    "generalWindowMs": 60000,
    "generalMaxRequests": 240,
    "maxBuckets": 10000,
    "authWindowMs": 900000,
    "authMaxRequests": 10
  }
}
```

Si alguna dependencia critica falla, responde `503` con `status: "degraded"`.

## Auth

### `POST /api/auth/login`

Inicia sesion y devuelve `accessToken`, `refreshToken` y perfil base.

Request:

```json
{
  "identifier": "usuario@empresa.com",
  "password": "Secret123!"
}
```

Response:

```json
{
  "accessToken": "jwt",
  "refreshToken": "opaque-refresh-token",
  "user": {
    "userId": "8cc6a6b1-1ba8-4c44-8e84-a8a8fca99a45",
    "email": "usuario@empresa.com",
    "username": "usuario",
    "roles": ["EMPLOYEE"],
    "passwordMustChange": false,
    "passwordChangedAt": "2026-04-23T18:00:00.000Z",
    "firstName": "Mariana",
    "lastName": "Perez",
    "status": "ACTIVE",
    "lastLoginAt": "2026-04-23T18:00:00.000Z"
  }
}
```

### `POST /api/auth/refresh`

Rota el refresh token y devuelve un nuevo par de tokens.

Request:

```json
{
  "refreshToken": "opaque-refresh-token"
}
```

Response:

```json
{
  "accessToken": "jwt",
  "refreshToken": "next-opaque-refresh-token",
  "user": {
    "userId": "8cc6a6b1-1ba8-4c44-8e84-a8a8fca99a45",
    "email": "usuario@empresa.com",
    "username": "usuario",
    "roles": ["EMPLOYEE"],
    "firstName": "Mariana",
    "lastName": "Perez",
    "status": "ACTIVE",
    "lastLoginAt": "2026-04-23T18:00:00.000Z"
  }
}
```

### `POST /api/auth/logout`

Revoca el refresh token recibido y responde `204`.

Request:

```json
{
  "refreshToken": "opaque-refresh-token"
}
```

### `GET /api/auth/me`

Devuelve el contexto del usuario autenticado.

### `POST /api/auth/change-password`

Cambia la contrasena del usuario autenticado. Se usa especialmente cuando `passwordMustChange=true`.

Request:

```json
{
  "currentPassword": "temporal",
  "newPassword": "NuevaClave123!"
}
```

Politica minima:

- minimo 8 caracteres
- al menos una minuscula
- al menos una mayuscula
- al menos un numero
- al menos un simbolo
- no debe contener el username ni la parte local del email
- debe ser distinta de la contrasena actual

Response:

```json
{
  "user": {
    "userId": "8cc6a6b1-1ba8-4c44-8e84-a8a8fca99a45",
    "email": "usuario@empresa.com",
    "username": "usuario",
    "roles": ["EMPLOYEE"],
    "passwordMustChange": false,
    "passwordChangedAt": "2026-04-23T18:05:00.000Z",
    "firstName": "Mariana",
    "lastName": "Perez",
    "status": "ACTIVE",
    "lastLoginAt": "2026-04-23T18:00:00.000Z"
  }
}
```

Mientras `passwordMustChange=true`, las rutas de catalogo, dispositivos y admin responden `403` con `details.code = "PASSWORD_CHANGE_REQUIRED"`.

## Apps

### `GET /api/apps`

Lista apps visibles para el usuario.

Query params:

- `deviceId` opcional para enriquecer con estado instalado en ese dispositivo

Response:

```json
{
  "items": [
    {
      "id": "app-id",
      "packageName": "com.empresa.inventario",
      "slug": "inventario",
      "displayName": "Inventario",
      "shortDescription": "App de inventario",
      "description": "Inventario y consulta",
      "iconPath": "assets/icons/inventario.png",
      "bannerPath": null,
      "category": "operations",
      "status": "ACTIVE",
      "requiresExplicitAccess": false,
      "latestVersion": {
        "id": "version-id",
        "versionName": "2.4.1",
        "versionCode": 241,
        "isMandatory": false,
        "releasedAt": "2026-04-23T18:00:00.000Z"
      },
      "installedState": {
        "id": "state-id",
        "status": "INSTALLED",
        "installedVersionId": "version-id",
        "installedVersionName": "2.4.0",
        "installedVersionCode": 240,
        "lastReportedAt": "2026-04-23T17:45:00.000Z",
        "lastOpenedAt": "2026-04-23T17:50:00.000Z"
      },
      "updateAvailable": true
    }
  ]
}
```

Notas:

- Solo se exponen apps con una version publicada y APK fisicamente disponible.
- Si el usuario pierde permisos, la app desaparece del catalogo en el siguiente refresh.

### `GET /api/apps/:id`

Devuelve detalle de una app con la misma estructura base del catalogo.

Query params:

- `deviceId` opcional

### `GET /api/apps/:id/latest-version`

Devuelve la version mas reciente publicada.

Query params:

- `deviceId` opcional

### `GET /api/apps/:id/changelog`

Devuelve historial de versiones publicado.

### `GET /api/apps/:id/download`

Descarga el APK protegido.

Query params:

- `deviceId` opcional para trazabilidad
- `versionCode` opcional para descargar una version concreta; si no se envia, baja la mas reciente

Comportamiento:

- valida autenticacion y permiso de instalacion
- resuelve el archivo dentro de `APK_STORAGE_DIR`
- registra un `InstallationLog` de tipo `DOWNLOAD`
- responde con descarga `attachment`

## Devices

### `POST /api/devices/register`

Registra o actualiza un dispositivo Android ligado al usuario autenticado.

Request:

```json
{
  "deviceIdentifier": "android-uuid-or-managed-id",
  "name": "PDA 04",
  "manufacturer": "Zebra",
  "model": "TC52",
  "osVersion": "14",
  "appVersionName": "0.1.0",
  "pushToken": "optional-token"
}
```

### `POST /api/devices/report-installation`

Reporta descarga, instalacion, actualizacion, apertura o eliminacion observada por el cliente.

Request:

```json
{
  "deviceId": "device-uuid",
  "appId": "app-uuid",
  "appVersionId": "version-uuid",
  "installedVersionCode": 241,
  "installedVersionName": "2.4.1",
  "action": "INSTALL",
  "status": "SUCCESS",
  "notes": "Instalacion confirmada por el sistema"
}
```

Acciones contempladas:

- `DOWNLOAD`
- `INSTALL`
- `UPDATE`
- `OPEN`
- `REMOVE`

## Admin

Las rutas admin usan permisos formales derivados del rol del usuario. Resumen de roles:

- `SUPER_ADMIN`: control total, incluyendo borrado definitivo de apps.
- `ADMIN`: gestion operativa de usuarios, apps, permisos, auditoria y dispositivos, sin borrado definitivo de apps.
- `APP_ADMIN`: gestion de catalogo, versiones, estado de apps y accesos de apps.
- `EMPLOYEE`: usuario final sin permisos administrativos.

Permisos por endpoint:

- `POST /api/admin/users`: `user.create`
- `POST /api/admin/apps`: `app.create`
- `POST /api/admin/apps/:id/versions`: `app.version.create`
- `PATCH /api/admin/apps/:id/status`: `app.status.update`
- `DELETE /api/admin/apps/:id`: `app.delete`
- `PUT /api/admin/apps/:id/users/:userId/access`: `app.access.manage`
- `PUT /api/admin/apps/:id/roles/:roleCode/access`: `app.access.manage`
- `PATCH /api/admin/versions/:id/mandatory`: `app.version.mandatory.update`
- `POST /api/admin/users/:id/revoke-access`: `user.revoke`
- `GET /api/admin/installation-logs`: `audit.log.read`

### `POST /api/admin/users`

Crea un usuario operativo para el portal, por ejemplo un empleado piloto.

Request:

```json
{
  "email": "empleado@empresa.local",
  "username": "empleado01",
  "password": "Empleado123!",
  "firstName": "Empleado",
  "lastName": "Piloto",
  "status": "ACTIVE",
  "roleCodes": ["EMPLOYEE"]
}
```

### `POST /api/admin/apps`

Crea una app en el catalogo.

### `POST /api/admin/apps/:id/versions`

Publica una nueva version.

Formato:

- `multipart/form-data`
- campo de archivo: `apkFile`
- alternativa manual: `apkRelativePath`

Validaciones del backend:

- exige extension `.apk`
- valida que el archivo sea un ZIP/APK legible
- valida presencia de `AndroidManifest.xml` y `classes.dex`
- calcula `sha256` automaticamente
- si se envia `sha256`, verifica que coincida con el contenido real
- rechaza `versionCode` duplicados por app con error `409`

Metadatos guardados por version:

- `apkPath`
- `originalFileName`
- `contentType`
- `fileExtension`
- `archiveEntryCount`
- `fileSizeBytes`
- `sha256`

### `PATCH /api/admin/apps/:id/status`

Actualiza el estado de una app.

### `PUT /api/admin/apps/:id/users/:userId/access`

Asigna o actualiza acceso explicito de una app para un usuario.

Request:

```json
{
  "canView": true,
  "canInstall": true
}
```

Si ambos valores llegan en `false`, el permiso explicito se elimina.

### `PUT /api/admin/apps/:id/roles/:roleCode/access`

Asigna o actualiza acceso explicito de una app para un rol.

Request:

```json
{
  "canView": true,
  "canInstall": false
}
```

Esto permite, por ejemplo, que `EMPLOYEE` vea una app pero no pueda descargarla.

### `PATCH /api/admin/versions/:id/mandatory`

Marca una version como obligatoria u opcional.

### `POST /api/admin/users/:id/revoke-access`

Revoca el acceso del usuario y fuerza cierre de todas sus sesiones activas.

Request:

```json
{
  "status": "DISABLED"
}
```

Comportamiento:

- actualiza el estado del usuario a `DISABLED`
- incrementa `sessionVersion`
- revoca todos los refresh tokens vigentes del usuario

### `GET /api/admin/installation-logs`

Consulta trazabilidad basica por app, usuario y dispositivo.

Query params opcionales:

- `appId`
- `userId`
- `deviceId`
- `action`
- `limit` default `50`

### `DELETE /api/admin/apps/:id`

Elimina completamente una app de la tienda, incluyendo versiones, permisos, estados, logs relacionados y carpeta fisica de APKs.

Requiere:

- permiso `app.delete`
- actualmente solo `SUPER_ADMIN` lo posee por defecto

Response:

```json
{
  "result": {
    "app": {
      "id": "app-id",
      "displayName": "Inventario",
      "packageName": "com.empresa.inventario"
    },
    "deletedCounts": {
      "installationLogs": 12,
      "deviceStates": 3,
      "userPermissions": 1,
      "rolePermissions": 1,
      "versions": 2
    },
    "deletedByUserId": "admin-user-id"
  }
}
```

## Notas de dominio

- `versionCode` se usa para comparacion tecnica y deteccion de updates.
- `versionName` se usa para UI.
- `requiresExplicitAccess` permite ocultar apps hasta conceder permiso por usuario o rol.
- `DeviceAppState` guarda el estado actual por dispositivo y app.
- `InstallationLog` conserva el historial operativo y de auditoria.
