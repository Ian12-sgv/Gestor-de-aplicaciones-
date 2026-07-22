# Configuracion

## Requisitos

- Node.js 22+
- Flutter estable
- SQL Server accesible desde el backend
- Caddy instalado en el servidor de despliegue

## Variables de entorno sugeridas

Backend:

```bash
NODE_ENV="development"
HOST="127.0.0.1"
PORT=3000
API_PREFIX="/api"
CORS_ORIGIN="https://store.empresa.com"
TRUST_PROXY="loopback"
DATABASE_URL="sqlserver://localhost:1433;database=pdb_store;user=sa;password=ChangeMe123!;encrypt=true;trustServerCertificate=true"
JWT_SECRET="replace-with-a-long-random-secret-of-at-least-32-characters"
JWT_EXPIRES_IN="15m"
REFRESH_TOKEN_TTL_DAYS=30
APK_STORAGE_DIR="./storage/apks"
APK_AUTO_IMPORT_ENABLED="false"
APK_AUTO_IMPORT_POLL_INTERVAL_MS=4000
APK_AUTO_IMPORT_STABLE_MS=6000
# ANDROID_AAPT_PATH="/absolute/path/to/aapt"
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=240
RATE_LIMIT_MAX_BUCKETS=10000
AUTH_RATE_LIMIT_WINDOW_MS=900000
AUTH_RATE_LIMIT_MAX_REQUESTS=10
LOG_LEVEL="info"
ALLOW_DOTENV_IN_PROD="false"
SEED_ADMIN_EMAIL="admin@empresa.local"
SEED_ADMIN_USERNAME="admin"
SEED_ADMIN_PASSWORD="change-this-before-seeding"
SEED_ADMIN_FIRST_NAME="Admin"
SEED_ADMIN_LAST_NAME="Inicial"
```

## Comandos del backend

```bash
npm install
npm run prisma:generate
npm run prisma:seed
npm run apk:auto-import:once
npm run build
npm run dev
```

## Comandos del cliente Flutter

```bash
flutter pub get
flutter analyze
flutter test
```

## Estructura recomendada

```text
/opt/private-store/
  back/
  front/
  apks/
  public/
  logs/
```

## Flujo de puesta en marcha

1. Instalar dependencias del backend con `npm install`.
2. En desarrollo, copiar `back/.env.example` a un `.env` local y completar valores.
3. En produccion, inyectar secretos solo por variables de entorno del servicio; no usar `.env` persistido en disco.
4. Ejecutar `npm run prisma:generate`.
5. Crear la base `pdb_store` en SQL Server y aplicar migraciones con `npm run prisma:migrate:deploy`.
6. Ejecutar `npm run prisma:seed` para crear roles base y usuario admin inicial.
7. Colocar APKs en el almacenamiento privado del servidor.
8. Ajustar el `Caddyfile` con el dominio real.
9. Levantar Node.js solo en `127.0.0.1:3000`.
10. Probar acceso por HTTPS a traves de Caddy.

## Reglas duras de produccion

Cuando `NODE_ENV=production`, el backend valida la configuracion antes de arrancar:

- `HOST` debe quedar en loopback, normalmente `127.0.0.1`.
- `CORS_ORIGIN` no puede ser `*`; debe listar origenes confiables concretos.
- `APK_STORAGE_DIR` debe ser una ruta absoluta privada, por ejemplo `/opt/private-store/apks`.
- `JWT_SECRET` debe venir del entorno real y no conservar el placeholder.
- `ALLOW_DOTENV_IN_PROD` debe quedar en `false`.
- `API_PREFIX` debe empezar por `/`.
- `TRUST_PROXY` debe reflejar el proxy real; con Caddy local usar `loopback`.
- `RATE_LIMIT_MAX_BUCKETS` debe tener una cota explicita para evitar crecimiento indefinido de memoria.

Ejemplo minimo para produccion:

```bash
NODE_ENV="production"
HOST="127.0.0.1"
PORT=3000
API_PREFIX="/api"
CORS_ORIGIN="https://store.empresa.com"
TRUST_PROXY="loopback"
DATABASE_URL="sqlserver://127.0.0.1:1433;database=pdb_store;user=store_app;password=***;encrypt=true;trustServerCertificate=true"
JWT_SECRET="generar-un-secreto-largo-y-unico"
APK_STORAGE_DIR="/opt/private-store/apks"
RATE_LIMIT_MAX_BUCKETS=10000
ALLOW_DOTENV_IN_PROD="false"
LOG_LEVEL="info"
```

## Politica de secretos y entorno

- `JWT_SECRET`, `DATABASE_URL` y cualquier secreto operativo deben venir del entorno del proceso en produccion.
- El backend rechaza arrancar en `production` si `JWT_SECRET` conserva el placeholder.
- El backend tambien rechaza CORS abierto, storage relativo, bind publico y `.env` habilitado en produccion.
- El health expone `configSource` para distinguir si el proceso arranco con `.env` local o con entorno real.
- `ALLOW_DOTENV_IN_PROD` solo debe usarse temporalmente para pruebas controladas.

## Flujo operativo para TI

### Opcion automatica: copiar el APK y listo

1. Levantar el backend con `APK_AUTO_IMPORT_ENABLED=true`.
2. Copiar el `.apk` directamente en la carpeta `apks/` o en `apks/.incoming/`.
3. Esperar unos segundos mientras el backend confirma que el archivo dejo de crecer.
4. El importador extrae `packageName`, `versionCode`, `versionName` y `displayName` desde el APK con `aapt`.
5. Si la app no existia, la crea en `DRAFT`, publica la version y la deja en `ACTIVE`.
6. Si el APK ya estaba publicado con el mismo `versionCode`, el archivo se mueve a `apks/.duplicate/`.
7. Si el APK no se puede importar, el archivo se mueve a `apks/.failed/` con un `.json` al lado explicando la razon.

Notas:

- El backend necesita acceso a `aapt`; si no esta en el SDK detectado automaticamente, define `ANDROID_AAPT_PATH`.
- El importador automatico usa el admin inicial o el primer usuario `ADMIN` activo para registrar la publicacion.
- Si quieres procesar manualmente lo que ya dejaste en la carpeta, ejecuta `npm run apk:auto-import:once`.

### Opcion manual por API

1. Crear la app con `POST /api/admin/apps` y dejarla en `DRAFT`.
2. Subir la version con `POST /api/admin/apps/:id/versions` usando `multipart/form-data` y el campo `apkFile`.
3. Revisar la respuesta del backend:
   - confirma `sha256` calculado automaticamente
   - confirma `fileSizeBytes`
   - confirma metadatos tecnicos como `contentType`, `fileExtension` y `archiveEntryCount`
4. Si TI ya coloco el APK en storage por otro proceso, puede usar `apkRelativePath`, pero el backend seguira validando que el archivo exista y sea un APK legible.
5. Activar la app con `PATCH /api/admin/apps/:id/status` a `ACTIVE`.
6. Iniciar sesion desde un dispositivo de prueba y confirmar catalogo, descarga e instalacion.
7. Si una version debe ser forzada, cargarla con `isMandatory=true` y, si aplica, `minSupportedVersionCode`.

## Sesion y revocacion

- `accessToken`: corto, pensado para durar `15m` por defecto.
- `refreshToken`: opaco, rotativo y persistido hasheado en la base de datos.
- Cada refresh invalida el token anterior y entrega uno nuevo.
- Cada request autenticado revalida el usuario en base de datos y revisa `sessionVersion`.
- Cuando un empleado deja de estar autorizado, TI debe:
  1. llamar `POST /api/admin/users/:id/revoke-access`
  2. dejar el usuario en `DISABLED`
  3. confirmar que el siguiente `GET /api/auth/me` falle con `403` o `401`

## Publicacion segura de APKs

- No confiar en el nombre del archivo subido: el backend valida extension e integridad.
- El hash `sha256` siempre se calcula en el servidor.
- Si TI envia un `sha256`, se usa como verificacion adicional.
- No reutilizar `versionCode`; cada version por app debe ser unica.
- El catalogo solo expone versiones cuyo APK sigue existiendo en `APK_STORAGE_DIR`.

## Seed inicial

- El seed crea los roles `SUPER_ADMIN`, `ADMIN`, `APP_ADMIN` y `EMPLOYEE`.
- Tambien crea o actualiza un usuario admin inicial y le asigna `SUPER_ADMIN`.
- Por defecto usa:
  - email: `admin@empresa.local`
  - usuario: `sistema`
  - password: `j2094l,.`
- Puedes cambiar esos valores con las variables `SEED_ADMIN_*`.

## Roles y permisos administrativos

El backend usa permisos centralizados por rol:

- `SUPER_ADMIN`: puede crear usuarios, revocar accesos, administrar apps, leer auditoria y borrar apps definitivamente.
- `ADMIN`: puede crear usuarios, revocar accesos, administrar apps y leer auditoria, pero no borrar apps definitivamente.
- `APP_ADMIN`: puede crear apps/versiones, cambiar estado, marcar versiones obligatorias y gestionar accesos de apps.
- `EMPLOYEE`: solo consume el catalogo autorizado.

Para apps sensibles, crear la app con `requiresExplicitAccess=true` y conceder acceso por usuario o rol usando los endpoints `PUT /api/admin/apps/:id/users/:userId/access` o `PUT /api/admin/apps/:id/roles/:roleCode/access`.

## Cambio inicial de contrasena

- Los usuarios creados desde administracion reciben `passwordMustChange=true`.
- Al iniciar sesion, la app movil redirige a una pantalla de cambio de contrasena si esa bandera esta activa.
- Mientras la bandera siga activa, el backend bloquea catalogo, dispositivos y admin con `PASSWORD_CHANGE_REQUIRED`.
- La contrasena nueva debe cumplir la politica minima: 8 caracteres, mayuscula, minuscula, numero y simbolo.
- La contrasena nueva no puede contener el username ni la parte local del correo.

## Desarrollo local

- El backend puede ejecutarse detras de Caddy o, en desarrollo, directamente contra `localhost`.
- Flutter puede trabajar con modo demo mientras el backend real se conecta.
- El scaffold Android ya puede regenerarse o ampliarse con `flutter create`.
- No exponer SQL Server a internet.
