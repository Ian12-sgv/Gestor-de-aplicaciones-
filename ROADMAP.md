# ROADMAP

## Proposito

Construir un portal interno corporativo para distribuir y actualizar aplicaciones Android de la empresa.

El sistema debe permitir que el personal autorizado:

- inicie sesion
- vea las apps que le corresponden
- descargue la version correcta
- actualice sus apps de forma mas practica
- reporte estado basico de instalacion por usuario y dispositivo

No es una tienda publica ni un marketplace abierto.

## Meta Operativa

Esta base se considerara lista para uso interno cuando cumpla esto:

- Un empleado puede iniciar sesion y ver solo las apps autorizadas
- Puede descargar, instalar, actualizar y abrir apps corporativas desde Android
- El backend registra descargas e instalaciones por usuario y dispositivo
- Un administrador puede publicar nuevas versiones APK de forma controlada
- La plataforma corre detras de HTTPS corporativo con SQL Server privado

## Estado Actual

- Ultima actualizacion: 2026-04-23
- Estado general: flujo principal funcional con endurecimiento operativo minimo para piloto interno
- Lo ya construido: backend modular, esquema Prisma, sesiones con refresh token rotativo, rate limiting, logs estructurados, health extendido, app Flutter con flujo Android real, Caddyfile y publicacion segura de APKs
- Brecha principal: terminar configuracion real de entorno, definir permisos finos por negocio y validar despliegue corporativo completo

## Alcance de esta etapa

Incluye:

- Autenticacion para personal de la empresa
- Catalogo de apps corporativas segun permisos
- Descarga protegida de APKs
- Registro de dispositivo y reporte de instalacion/actualizacion
- Publicacion de versiones por administradores
- Auditoria basica de descargas e instalaciones

No incluye por ahora:

- Funciones de marketplace publico
- Pagos, resenas, comentarios o recomendaciones
- Soporte iOS
- Instalacion silenciosa fuera de entornos administrados
- Multiempresa o multitenancy
- Panel admin web como requisito de la primera puesta en marcha
- CI/CD formal como condicion de salida de la primera version

## Base ya completada

- [x] Monorepo con `back/`, `front/` y `docs/`
- [x] Backend base en Node.js + TypeScript + Express
- [x] Modelo principal en Prisma para SQL Server
- [x] Endpoints base de auth, apps, devices y admin
- [x] Flujo protegido de descarga de APKs por backend
- [x] App Flutter con login, catalogo, detalle y modo demo
- [x] Caddyfile y documentacion de setup, deployment, seguridad y arquitectura
- [x] Validaciones base ejecutadas: `npm install`, `npm run build`, `flutter analyze`, `flutter test`

## Prioridad 1 - Entorno real y datos base

- [x] Crear migraciones Prisma reales sobre SQL Server del entorno
- [x] Crear seed de roles base: `SUPER_ADMIN`, `ADMIN`, `APP_ADMIN`, `EMPLOYEE`
- [x] Crear usuario administrador inicial
- [ ] Definir variables reales para backend, Caddy y almacenamiento de APKs
- [ ] Verificar estructura fisica de almacenamiento y permisos del directorio de APKs

## Prioridad 2 - Alinear contrato entre Flutter y backend

- [x] Unificar request y response de `POST /api/auth/login`
- [x] Unificar response de `GET /api/auth/me`
- [x] Unificar response de `GET /api/apps`
- [x] Unificar response de `GET /api/apps/:id/latest-version`
- [x] Unificar el modelo de `App` y `AppVersion` entre backend y Flutter
- [x] Definir si se usaran solo `accessToken` o tambien `refreshToken`
- [x] Desactivar modo demo por defecto para entornos reales
- [x] Probar login, catalogo, detalle y versiones contra backend real

## Prioridad 3 - Flujo Android real para empleados

- [x] Registrar dispositivo real con `POST /api/devices/register`
- [x] Detectar apps instaladas por `packageName`
- [x] Detectar version instalada local
- [x] Descargar APK real desde el endpoint protegido
- [x] Lanzar instalador del sistema Android
- [x] Abrir apps ya instaladas desde el portal
- [x] Reportar `DOWNLOAD`, `INSTALL`, `UPDATE`, `OPEN` y `REMOVE` al backend
- [x] Implementar UX de actualizacion obligatoria

## Prioridad 4 - Publicacion segura de apps

- [x] Calcular `sha256` automaticamente al subir APKs
- [x] Validar integridad y extension del archivo subido
- [x] Guardar tamano y metadatos tecnicos del APK publicado
- [x] Evitar duplicados de `versionCode` por app con mensajes claros
- [x] Validar que el APK exista antes de exponerlo en catalogo
- [x] Documentar flujo operativo para TI: crear app, subir version, activar version

## Prioridad 5 - Seguridad y operacion minima

- [x] Agregar rate limiting
- [x] Definir estrategia de sesion y renovacion de tokens
- [x] Definir politica de revocacion de acceso cuando un empleado deja de estar autorizado
- [x] Mover secretos fuera de archivos locales al mecanismo del entorno
- [x] Agregar logs estructurados y health extendido
- [x] Definir retencion de auditoria y backups de base de datos + APKs

## Criterios de salida para primera puesta en marcha

- [x] Un admin puede cargar al menos 1 app y 2 versiones desde el entorno real
- [x] Un empleado puede iniciar sesion y ver solo sus apps habilitadas
- [ ] Un dispositivo Android puede descargar e instalar una version publicada
- [x] El sistema detecta cuando hay actualizacion disponible
- [x] El backend registra trazabilidad minima por usuario, app y dispositivo
- [ ] El despliegue corre con HTTPS corporativo y base de datos privada
- [x] Existe al menos un procedimiento basico de respaldo y recuperacion

Notas de validacion:

- El piloto automatizado `ops/pilot-validate.ps1` valido publicacion, acceso por empleado, deteccion de update y trazabilidad el `2026-04-23`.
- El criterio de instalacion en dispositivo real queda pendiente hasta reconectar una PDA o telefono Android por ADB.
- El criterio de HTTPS corporativo queda pendiente hasta validar dominio real, Caddy y servidor del entorno.

## Riesgos que se deben validar en pruebas

- [ ] Comportamiento de instalacion de APKs segun fabricante y politicas del dispositivo
- [x] Permisos Android requeridos para instalar apps fuera de Play Store
- [ ] Calidad de la red corporativa al descargar APKs grandes
- [x] Manejo correcto de permisos por usuario y por rol
- [x] Operacion de Prisma con SQL Server del entorno real

Notas de validacion de riesgos:

- `ops/android-install-validate.ps1` confirmo manifest, `REQUEST_INSTALL_PACKAGES`, `FileProvider`, chequeo de `canRequestPackageInstalls()` y apertura de ajustes de origenes desconocidos el `2026-04-23`.
- `ops/permissions-validate.ps1` valido acceso por rol, acceso por usuario y bloqueo de descarga sin permiso de instalacion el `2026-04-23`.
- `ops/prisma-env-validate.ps1` valido schema Prisma y round-trip de escritura/borrado sobre `pdb_store` el `2026-04-23`.
- `ops/network-validate.ps1` dejo una linea base local de descarga de un APK de `148324344` bytes en `172.06s` con `0.82 MB/s`; falta repetirlo contra la URL corporativa real.
- El comportamiento por fabricante/politicas sigue pendiente hasta reconectar una PDA Android por ADB y ejecutar `ops/android-install-validate.ps1` junto con `ops/pilot-validate.ps1`.

## Orden recomendado de implementacion

1. Migraciones, seed y admin inicial.
2. Contrato unico entre backend y Flutter.
3. Login real y catalogo real sin modo demo.
4. Registro de dispositivo y reporte de eventos.
5. Descarga, instalacion y apertura real en Android.
6. Integridad de APKs y flujo operativo de publicacion.
7. Seguridad minima, observabilidad y backups.
