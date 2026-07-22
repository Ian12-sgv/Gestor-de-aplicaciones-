# Arquitectura Inicial

## Resumen

La solucion se compone de cuatro piezas principales:

1. App movil Flutter para usuarios finales.
2. API privada en Node.js + TypeScript + Express.
3. Base de datos SQL Server gestionada mediante Prisma.
4. Caddy como terminador HTTPS y reverse proxy, unico punto expuesto a internet.

## Diagrama Logico

```text
Android Device
  -> Flutter Corporate Store App
      -> HTTPS -> Caddy (public domain)
         -> Reverse proxy -> Node/Express API (127.0.0.1:3000)
            -> Prisma Client
            -> SQL Server
            -> File system / APK storage
      -> Android Package Manager / system installer
```

## Flujo Entre Componentes

### 1. Autenticacion

- La app Flutter envia credenciales por HTTPS a `POST /api/auth/login`.
- Caddy termina TLS y reenvia al backend local.
- El backend valida usuario y contrasena con bcrypt.
- Si el login es valido, el backend emite un `accessToken` JWT corto y un `refreshToken` rotativo.
- La app guarda ambos tokens y usa `Authorization: Bearer <accessToken>` en rutas protegidas.
- En cada request autenticado, el backend rehidrata el usuario desde SQL Server y valida `sessionVersion`.

### 2. Consulta de catalogo

- Flutter llama `GET /api/apps`.
- El backend identifica al usuario autenticado.
- El backend filtra el catalogo segun estado de la app y permisos por usuario o rol.
- Opcionalmente, si Flutter envia `deviceId`, el backend adjunta estado conocido de instalacion para ese dispositivo.

### 3. Descarga de APK

- Flutter solicita `GET /api/apps/:id/download`.
- El backend valida autenticacion, permisos y version solicitada.
- El backend resuelve la ruta fisica del APK dentro del storage corporativo.
- El backend registra la descarga en logs de auditoria.
- El backend sirve el archivo al cliente con cabeceras de descarga.

Recomendacion:

- Iconos, banners u otros archivos estaticos pequenos pueden servirse directamente por Caddy.
- Los APKs deben descargarse a traves del backend para conservar autenticacion, autorizacion y trazabilidad.

### 4. Instalacion o actualizacion

- La app Flutter descarga el APK.
- La app Flutter invoca el instalador del sistema Android.
- El usuario confirma la instalacion en Android estandar.
- Despues de la instalacion o del intento, Flutter reporta el resultado al backend usando `POST /api/devices/report-installation`.

### 5. Apertura de una app instalada

- Flutter consulta si la app objetivo esta instalada mediante integracion nativa Android por `packageName`.
- Si esta instalada, Flutter intenta abrirla mediante intent explicito o launcher intent.
- Opcionalmente reporta evento de apertura al backend para trazabilidad.

## Almacenamiento de APKs

### Recomendacion

- Mantener una raiz dedicada, por ejemplo:
  - `/srv/corporate-store/apks/` en Linux
  - `D:\corporate-store\apks\` en Windows
- Guardar cada APK por app y version:
  - `apks/com.company.sales/120/sales-v120.apk`
  - `apks/com.company.inventory/42/inventory-v42.apk`

### Principios

- La base de datos almacena metadatos y rutas relativas, no blobs de APK.
- El backend resuelve y sirve el archivo.
- Deben almacenarse tambien hash `sha256`, tamano y changelog por version.

## Autenticacion y Autorizacion

### Autenticacion

- `accessToken` JWT con expiracion corta configurable.
- `refreshToken` opaco, rotativo y almacenado hasheado en la base de datos.
- Contrasenas con bcrypt.
- `GET /api/auth/me` devuelve el contexto del usuario autenticado.

### Autorizacion

- Roles globales como `ADMIN`, `APP_ADMIN`, `EMPLOYEE`.
- Permisos por app a nivel usuario y rol.
- Campo `requiresExplicitAccess` para apps que no deban estar visibles a toda la empresa.

## Como se identifica si una app esta instalada

La verificacion ocurre en dos capas:

1. Capa local en Android:
   - Flutter consulta el `packageName` mediante codigo nativo.
   - Esto permite saber si la app esta instalada y si se puede abrir.
2. Capa servidor:
   - El backend mantiene un estado reportado por dispositivo y app.
   - Ese estado sirve para auditoria, catalogo enriquecido, deteccion de actualizaciones y soporte.

## Como se determina si hay actualizacion

- El backend guarda `versionCode` y `versionName` por cada `AppVersion`.
- El dispositivo reporta la version instalada.
- Si `installedVersionCode < latest.versionCode`, existe actualizacion.
- Si la version nueva tiene `isMandatory = true`, la app principal puede bloquear o forzar el flujo de actualizacion en UX.

## Modelo de Datos Propuesto

Entidades base:

- `User`
- `Role`
- `UserRole`
- `Device`
- `App`
- `AppVersion`
- `DeviceAppState`
- `InstallationLog`
- `AppUserPermission`
- `AppRolePermission`

### Motivo de `DeviceAppState`

No basta con guardar eventos historicos. Tambien hace falta un registro de estado actual por combinacion dispositivo + app para responder rapido:

- si la app esta instalada
- que version esta instalada
- cuando fue el ultimo reporte
- si la app se abrio recientemente

## Consideraciones Especificas de Prisma + SQL Server

- Prisma usa `provider = "sqlserver"` en el schema.
- Los identificadores principales se modelan como `UNIQUEIDENTIFIER`.
- Los campos largos como descripciones y changelogs se almacenan como `TEXT`.
- El `DATABASE_URL` usa formato `sqlserver://host:1433;database=pdb_store;user=...;password=...;encrypt=true;trustServerCertificate=true`.
- SQL Server debe permanecer privado y no quedar expuesto publicamente.

## Preparacion para Evolucion Futura con MDM

La arquitectura se deja lista para ampliar hacia:

- Android Enterprise
- dispositivos administrados
- instalacion silenciosa cuando el entorno lo permita
- politicas remotas de actualizacion obligatoria
- inventario de dispositivos y cumplimiento

En esa evolucion, la capa backend y el modelo de datos seguiran siendo validos; cambiaria principalmente la capacidad del cliente Android y la integracion de gestion empresarial.
