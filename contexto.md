# Contexto del Proyecto — Corporate App Store

## 1. Descripción del Proyecto (Overview)

**Corporate App Store** es una tienda privada de aplicaciones Android para uso interno de la empresa (similar a Google Play, pero corporativa). Permite a los empleados autenticarse, ver el catálogo de apps que tienen permitido usar, descargar/instalar/actualizar APKs y abrir las apps instaladas desde un único punto.

Funcionalidades principales:

- **Autenticación** con `accessToken` JWT de corta duración + `refreshToken` opaco y rotativo (guardado hasheado en BD). Soporta cambio de contraseña obligatorio en el primer login (`passwordMustChange`).
- **Catálogo filtrado** según estado de la app (`DRAFT`, `ACTIVE`, `DISABLED`, `ARCHIVED`) y permisos por usuario o por rol (`requiresExplicitAccess`).
- **Descarga de APKs** siempre a través del backend (autenticación, autorización y auditoría). Caddy solo sirve estáticos menores (iconos, banners).
- **Instalación/actualización** mediante el instalador del sistema Android; la app reporta el resultado a `POST /api/devices/report-installation`.
- **Detección de actualizaciones** comparando `installedVersionCode` con el `versionCode` más reciente; soporte de versiones obligatorias (`isMandatory`).
- **Panel de administración** (API): alta de apps y versiones, gestión de permisos, usuarios y logs de auditoría.
- **Importación automática de APKs** al copiar archivos en la carpeta de storage (`APK_AUTO_IMPORT_ENABLED`).
- Arquitectura preparada para evolucionar hacia MDM / Android Enterprise.

**Entorno productivo actual:** la API corre en el servidor detrás de Caddy en `https://pdbstore.apipalacio.com` (reverse proxy a `127.0.0.1:5201`). La app móvil apunta a esa URL por defecto.

Flujo lógico:

```text
Dispositivo Android
  -> App Flutter (Corporate Store)
      -> HTTPS -> Caddy (dominio público, único punto expuesto)
         -> Reverse proxy -> API Node/Express (127.0.0.1)
            -> Prisma Client -> SQL Server (privado)
            -> File system (storage de APKs)
      -> Package Manager / instalador del sistema Android
```

Documentación ampliada: [ARCHITECTURE.md](ARCHITECTURE.md), [docs/API_SPEC.md](docs/API_SPEC.md), [docs/SETUP.md](docs/SETUP.md), [docs/SECURITY.md](docs/SECURITY.md).

---

## 2. Stack Tecnológico (Tech Stack)

### Backend (`back/`)

| Área | Tecnología |
|---|---|
| Runtime | Node.js >= 22 |
| Lenguaje | TypeScript 5 (`strict: true`, target ES2022, módulos CommonJS) |
| Framework HTTP | Express 4 |
| ORM | Prisma 6 (`prisma-client-js`) |
| Base de datos | Microsoft SQL Server |
| Validación | Zod 3 |
| Auth | `jsonwebtoken` (JWT) + `bcrypt` |
| Seguridad | `helmet`, `cors`, rate limiting propio en memoria |
| Uploads | `multer` |
| Logs | `morgan` + logger estructurado propio (`utils/logger.ts`) |
| Dev / tests | `tsx` (watch y runner), `node:test` vía `tsx --test` |

Scripts clave (`back/package.json`): `dev`, `build`, `test`, `start`, `prisma:generate`, `prisma:migrate:dev`, `prisma:migrate:deploy`, `prisma:seed`, `prisma:smoke`, `prisma:create-db`, `apk:auto-import:once`.

### Mobile (`front/`)

| Área | Tecnología |
|---|---|
| Framework | Flutter (Dart SDK >= 3.4 < 4.0), plataforma Android |
| Estado / DI | `flutter_riverpod` 2 |
| Navegación | `go_router` 14 |
| HTTP | `dio` 5 |
| Persistencia local | `shared_preferences` |
| Otros | `package_info_plus`, `uuid` |
| Nativo Android | Kotlin (`MainActivity.kt`) vía platform channel para instalar/abrir/consultar apps |
| Lints | `flutter_lints` 5 + reglas estrictas |

Configuración por `--dart-define`: `API_BASE_URL` (por defecto `https://pdbstore.apipalacio.com`, la API real) y `USE_DEMO_DATA` (usa repositorios demo sin backend). Las rutas del cliente ya incluyen `/api`, así que la base es solo el dominio.

Para probar en local: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5201` (emulador) — `127.0.0.1` en un dispositivo apunta al propio teléfono.

### Infraestructura

- **Caddy**: terminación HTTPS y reverse proxy ([Caddyfile](Caddyfile)).
- **Scripts de operación** en PowerShell (`ops/`): backup, restore, validaciones de red, permisos, instalación Android y piloto.
- Despliegue objetivo en Windows (`D:\corporate-store\apks\`) o Linux (`/srv/corporate-store/apks/`).

---

## 3. Convenciones de Código y Estilo

### Generales

- Documentación y textos de negocio en **español**; código, identificadores y mensajes de error de la API en **inglés**.
- No subir secretos: `back/.env` está en `.gitignore`; usar `back/.env.example` como plantilla.
- No versionar APKs, `storage/`, `artifacts/` ni builds.

### Backend (TypeScript)

- **Nombres de archivo** en `kebab-case` con sufijo por responsabilidad: `<modulo>.routes.ts`, `<modulo>.controller.ts`, `<modulo>.service.ts`, `<modulo>.schemas.ts`, `<modulo>.types.ts`.
- **Capas por módulo** (responsabilidades estrictas):
  - `routes`: define el `Router`, encadena middlewares (`validate(schema)`, `authorize`) y exporta `export const <modulo>Routes = router;`.
  - `controller`: fino; envuelto en `asyncHandler`, llama al service y responde `res.status(...).json(...)`. Sin lógica de negocio ni acceso a Prisma.
  - `service`: lógica de negocio y acceso a datos vía el singleton `prisma` de `config/prisma.ts`. Exporta funciones (no clases). Se importa como `import * as xService from "./x.service"`.
  - `schemas`: esquemas Zod + tipos inferidos (`export type XInput = z.infer<typeof xSchema>`).
- **Validación**: toda entrada (`body`, `query`, `params`) pasa por el middleware `validate(schema, source)`; los strings usan `.trim()` y `.max()` alineado con el tamaño de columna en BD.
- **Errores**: lanzar `new ApiError(statusCode, "Mensaje en inglés", details?)`; el `errorHandler` global los serializa. No hacer `try/catch` en controllers.
- **Constantes de dominio** (estados, roles, acciones, permisos) centralizadas en `config/domain.ts` como arrays `as const`; reutilizarlas en Zod (`z.enum(APP_STATUSES)`) y nunca escribir strings mágicos sueltos.
- **Autorización** por permisos (`hasPermission(user.roles, PERMISSIONS.X)`), no comparando roles directamente.
- **Variables de entorno** solo a través de `config/env.ts` (validado), nunca `process.env` disperso.
- Estilo: comillas dobles, punto y coma, indentación de 2 espacios, trailing commas, funciones `async/await`, `import type` para tipos.

### Mobile (Flutter / Dart)

- **Organización feature-first** con capas `data/`, `domain/`, `presentation/` por feature.
- **Repositorios** definidos como clase `abstract` con implementaciones `Remote*Repository` (API real) y `Demo*Repository` (datos simulados), seleccionadas por provider según `AppConfig.useDemoData`.
- **Estado** con Riverpod: `Provider` para dependencias, `AsyncNotifier`/`AsyncNotifierProvider` para controllers, `FutureProvider.family` para detalles; usar `AsyncValue.guard` al refrescar.
- **Nombres**: archivos en `snake_case.dart`; pantallas `*_screen.dart`; controllers `*_controller.dart`; providers terminan en `Provider`.
- **Lints obligatorios** (`analysis_options.yaml`): `strict-casts`, `strict-inference`, `strict-raw-types`, `always_declare_return_types`, `annotate_overrides`, `avoid_dynamic_calls`, `prefer_single_quotes`.
- Constructores `const` siempre que sea posible; imports relativos dentro de `lib/src`.
- Antes de entregar cambios: `flutter analyze` y `flutter test` sin errores.
- **Build limpio**: en este equipo Flutter a veces reutiliza el `kernel_blob.bin` viejo y el APK sale sin los cambios de Dart. Si los cambios no aparecen, ejecutar `flutter clean && flutter pub get` antes de `flutter build apk`.

### Diseño de UI (Flutter)

- **Colores y estilos centralizados** en `lib/src/core/theme/app_theme.dart`:
  - `AppPalette`: tokens de color (`primary` `#0B7468`, `ink`, `muted`, `border`, `background`, `mint`, `sky`, `blush`, `danger`…). Usar siempre estos tokens, no colores sueltos.
  - `AppTheme.light()`: tema Material 3 (inputs redondeados 12, `FilledButton` 52 px de alto, `Card` con borde, `OutlinedButton` gris claro).
- **Login** (`login_screen.dart`): solo **Iniciar sesión**. No hay registro ("Crear cuenta") ni login con Google; las cuentas las crea un administrador. El campo "Correo corporativo" acepta correo o usuario (p. ej. `sistema`).
- **Catálogo** (`apps_list_screen.dart`): encabezado con logo, tarjeta "Sesión activa", tarjeta de permiso de instalación (estado "Prepara las instalaciones" / "Instalaciones preparadas"), sección "Catálogo" y tarjetas de app con avatar numerado de color, paquete, versión disponible y botón de acción (Instalar / Actualizar / Abrir) que ejecuta la acción directamente.
- **Detalle** (`app_detail_screen.dart`): avatar con inicial, "pdb Corporativo", tarjeta Estado / Versión / Prioridad, aviso de permiso, Novedades, botón principal y acciones "Quitar de este dispositivo" / "Retirar del catálogo" (solo en el detalle).
- `widgets/app_avatar_tile.dart`: avatar de app reutilizable; el color se elige de forma estable por `id` (`AppPalette.tileColorFor`).

### Marca (logo e icono)

- Logo fuente: `front/assets/branding/PDBStore.svg`.
- Logo para la UI: `front/assets/branding/pdbstore_logo.png` (redondo, 384 px, fondo transparente), registrado en `pubspec.yaml` y usado en el login (84 px) y en el encabezado del catálogo (44 px).
- Icono Android: `mipmap-*/ic_launcher.png`, `ic_launcher_round.png` e `ic_launcher_foreground.png` generados desde el SVG. El icono adaptativo (`mipmap-anydpi-v26`) usa `@mipmap/ic_launcher_foreground` sobre el color `launcher_background` `#242E36`. Si cambia el logo, regenerar todos los tamaños (mdpi → xxxhdpi) manteniendo el círculo dentro de ~72/108 dp.

---

## 4. Estructura de Carpetas (Architecture)

```text
/
├── back/                         # API Node.js + TypeScript + Express
│   ├── prisma/
│   │   ├── schema.prisma         # Modelo de datos (SQL Server)
│   │   ├── migrations/           # Migraciones activas SQL Server
│   │   ├── postgres_migrations_archive/  # Histórico PostgreSQL (NO aplicar)
│   │   └── seed.ts               # Datos iniciales (roles, admin)
│   ├── scripts/                  # Utilidades: crear BD, usuarios, smoke test
│   ├── src/
│   │   ├── app.ts                # Configuración Express, middlewares y montaje de rutas
│   │   ├── server.ts             # Arranque HTTP
│   │   ├── cli/                  # Comandos one-shot (auto-import de APKs)
│   │   ├── config/               # env.ts, prisma.ts, domain.ts (roles/permisos/estados)
│   │   ├── middlewares/          # authenticate, authorize, validate, rate-limit, upload, error-handler, request-context
│   │   ├── modules/              # Un módulo por dominio
│   │   │   ├── auth/             # login, refresh, logout, me, cambio de contraseña
│   │   │   ├── apps/             # catálogo, detalle, descarga de APK
│   │   │   ├── devices/          # registro de dispositivo, reporte de instalación
│   │   │   ├── admin/            # gestión de apps, versiones, permisos, usuarios, auto-import
│   │   │   └── health/           # health check (incluye ping a BD)
│   │   ├── types/                # Extensiones de tipos (express.d.ts → req.user)
│   │   └── utils/                # api-error, async-handler, jwt, password, apk, apk-manifest, fs, logger
│   └── test/                     # Tests de integración (node:test)
│
├── front/                        # App móvil Flutter (Android)
│   ├── android/                  # Proyecto nativo; MainActivity.kt con el bridge de instalación; iconos en res/mipmap-*
│   ├── assets/branding/          # PDBStore.svg (fuente) y pdbstore_logo.png (logo usado en la UI)
│   ├── lib/
│   │   ├── main.dart
│   │   └── src/
│   │       ├── app.dart          # MaterialApp.router
│   │       ├── core/             # config (API_BASE_URL), network (Dio ApiClient), theme (AppPalette + AppTheme), utils
│   │       ├── features/
│   │       │   ├── apps/         # data / domain / presentation (+ widgets/app_avatar_tile.dart)
│   │       │   ├── auth/         # login, cambio de contraseña, sesión
│   │       │   └── device/       # perfil y registro del dispositivo
│   │       └── routing/          # app_router.dart (GoRouter + redirects de auth)
│   └── test/
│
├── docs/                         # API_SPEC, ARCHITECTURE, DEPLOYMENT, OPERATIONS, SECURITY, SETUP, SQLSERVER_MIGRATION
├── ops/                          # Scripts PowerShell de operación y validación
├── tools/inventario-update-fixture/  # App Android de prueba para validar actualizaciones
├── Caddyfile                     # Reverse proxy + HTTPS
├── ARCHITECTURE.md
├── ROADMAP.md / ROADMAP_PRODUCCION.md
└── README.md
```

### Rutas de la API (prefijo `API_PREFIX`, por defecto `/api`)

| Ruta | Protección |
|---|---|
| `/api/health` | Pública (sin rate limit general) |
| `/api/auth/*` | Pública + rate limit específico de auth |
| `/api/apps/*` | `authenticate` + `requirePasswordReady` |
| `/api/devices/*` | `authenticate` + `requirePasswordReady` |
| `/api/admin/*` | `authenticate` + `requirePasswordReady` + permisos |

### Despliegue de backend en el servidor

- Ubicacion de produccion: `C:\\Users\\Administrator\\Documents\\servicios IAN\\servicio-pdbStore`.
- Antes de cada despliegue, ejecutar `npm.cmd run build` dentro de `back` y preparar `deploy/` con: `dist`, `admin-web`, `node_modules`, `prisma`, `package.json` y `package-lock.json`.
- Copiar el contenido de `deploy/` a la carpeta de produccion, aceptando reemplazar solo los archivos incluidos.
- Nunca sobrescribir ni borrar en el servidor: `.env`, `storage/`, `media/` o archivos `.log`; contienen configuracion privada, APKs publicadas, iconos y registros.
- Despues de copiar, ejecutar el `.bat` habitual de inicio de servicios para reiniciar pdbStore (`node dist/server.js`).
- Si cambia Prisma: incluir `prisma/`, generar el cliente antes de desplegar y aplicar en produccion unicamente `npm run prisma:migrate:deploy` cuando exista una migracion nueva.

### Almacenamiento de APKs

- Raíz configurable con `APK_STORAGE_DIR`.
- Estructura por paquete y versión: `apks/<packageName>/<versionCode>/<archivo>.apk`.
- La BD guarda **rutas relativas** y metadatos (sha256, tamaño, changelog), nunca el binario.

---

## 5. Reglas de Base de Datos

### Motor y conexión

- **SQL Server** con Prisma (`provider = "sqlserver"`). Base de datos por defecto: `pdb_store`.
- `DATABASE_URL` con formato: `sqlserver://host:1433;database=pdb_store;user=...;password=...;encrypt=true;trustServerCertificate=true`.
- SQL Server **nunca** se expone públicamente; solo el backend (o red interna autorizada) accede a él.
- Un único `PrismaClient` compartido: importar siempre `prisma` desde `back/src/config/prisma.ts`.

### Migraciones

- El esquema se modifica **solo** editando `back/prisma/schema.prisma` y generando una migración (`npm run prisma:migrate:dev`). No alterar tablas a mano.
- En producción se aplica con `npm run prisma:migrate:deploy`; nunca `migrate dev` ni `db push`.
- No editar migraciones ya aplicadas; crear una nueva.
- `prisma/postgres_migrations_archive/` es histórico: **no** aplicar ni mezclar su `_prisma_migrations` con SQL Server.
- Tras cambiar el schema: `npm run prisma:generate` y `npm run build`; validar con `npm run prisma:smoke`.
- Puesta en marcha limpia: `prisma:create-db` → `prisma:generate` → `prisma:migrate:deploy` → `prisma:seed`.

### Convenciones de modelado

- **Modelos** en `PascalCase` singular (`User`, `AppVersion`); **campos** en `camelCase`.
- **Claves primarias**: `String @id @default(uuid()) @db.UniqueIdentifier`. Las FKs también usan `@db.UniqueIdentifier`.
- Tablas intermedias puras usan PK compuesta (`UserRole: @@id([userId, roleId])`); las que tienen atributos propios usan `id` + `@@unique` sobre la combinación (`AppUserPermission`, `AppRolePermission`, `DeviceAppState`).
- **Strings** siempre con longitud explícita `@db.VarChar(n)`; textos largos (descripción, changelog) con `@db.Text`. La longitud de Zod debe coincidir con la de la columna.
- **Estados/enums** como `String @db.VarChar(30)` con `@default(...)`, no enums de Prisma. Los valores válidos viven en `config/domain.ts` y se validan con Zod.
- **Auditoría temporal**: `createdAt DateTime @default(now())` y, en entidades mutables, `updatedAt DateTime @updatedAt`.
- **Relaciones**: siempre `onDelete: NoAction, onUpdate: NoAction` (SQL Server no admite múltiples rutas de cascada). Los borrados en cascada se hacen **explícitamente en código** dentro de `prisma.$transaction`, eliminando primero los hijos (ver `deleteAppFromStore` en `admin.service.ts`: logs → estados → permisos → versiones → app).
- Añadir `@@index` a campos de filtrado frecuente (`status`, FKs, pares `[appId, createdAt]`).
- Tamaños de archivo como `BigInt` (`fileSizeBytes`); serializar a string/number antes de enviar en JSON.

### Integridad y reglas de negocio

- `App.packageName` y `App.slug` son únicos; `AppVersion` es única por `[appId, versionCode]`.
- `DeviceAppState` mantiene **un único estado actual** por `[deviceId, appId]` (usar `upsert`); `InstallationLog` es el **histórico** inmutable de eventos.
- Preferir estados (`DISABLED`, `ARCHIVED`, `RETIRED`) sobre borrado físico; el borrado real se reserva para operaciones de admin con permiso `app.delete`.
- Un dispositivo (`deviceIdentifier`) no puede re-vincularse a otro usuario si ya tiene dueño (409).

### Seguridad de datos

- Contraseñas solo como hash bcrypt (`passwordHash`); nunca en texto plano ni en logs.
- `RefreshToken.tokenHash` guarda el hash del token, no el token.
- `User.sessionVersion` invalida todas las sesiones al incrementarse (revocación, cambio de contraseña).
- Prohibido `$queryRawUnsafe` / `$executeRawUnsafe` con entrada de usuario; si se necesita SQL crudo, usar las variantes con template tag (`$queryRaw\`...\``) que parametrizan.
- Credenciales de BD solo en `back/.env` (no versionado); cambiar usuario `sa` y contraseñas de ejemplo en producción.
- Backups y restauración con `ops/backup.ps1` y `ops/restore.ps1`.
