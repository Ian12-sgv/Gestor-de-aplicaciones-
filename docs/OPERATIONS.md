# Operacion y Piloto

## Validacion piloto

El repo incluye un runbook ejecutable para validar la salida minima del piloto:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\pilot-validate.ps1 -StartBackend
```

Ese script hace esto:

1. levanta el backend en `3100`
2. valida `GET /api/health`
3. inicia sesion como admin
4. crea un empleado piloto
5. crea una app piloto y una app restringida
6. publica 2 versiones APK de la app piloto
7. otorga acceso solo al empleado de piloto
8. registra un dispositivo piloto
9. reporta una instalacion inicial
10. valida que el catalogo del empleado muestre solo la app habilitada
11. descarga la version publicada mas reciente
12. consulta trazabilidad desde admin

Si hay un dispositivo ADB conectado, el mismo script intenta instalar:

- `0.1.0+101`
- luego la version descargada `0.1.1+102`

Si no hay PDA o telefono conectado, ese criterio queda reportado como bloqueado por entorno.

## Validaciones de riesgo

## Importacion automatica de APKs

Si el backend corre con `APK_AUTO_IMPORT_ENABLED=true`, cualquier `.apk` que copies en `apks/` o `apks/.incoming/` se procesa solo.

Lanzador rapido del backend para esta carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\start-backend-autoimport.ps1
```

Comando manual para forzar una pasada inmediata:

```bash
npm run apk:auto-import:once
```

Comportamiento esperado:

- si la app no existe, se crea usando los metadatos del APK
- si la version es nueva, se publica y la app queda `ACTIVE`
- si el `versionCode` ya existia, el archivo se mueve a `apks/.duplicate/`
- si el archivo falla validacion o importacion, se mueve a `apks/.failed/` con un `.json` explicando la causa

Permisos por usuario y rol:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\permissions-validate.ps1 -StartBackend
```

Red de descarga para APKs grandes:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\network-validate.ps1 -StartBackend
```

Diagnostico Android de instalacion fuera de Play Store:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\android-install-validate.ps1
```

Validacion Prisma + SQL Server:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\prisma-env-validate.ps1
```

Interpretacion recomendada:

- `permissions-validate.ps1`: debe confirmar visibilidad por rol, visibilidad por usuario y bloqueo de descarga cuando `canInstall=false`.
- `network-validate.ps1`: deja una linea base de tiempo y throughput; si se ejecuta contra `127.0.0.1`, es solo referencia local.
- `android-install-validate.ps1`: valida manifest, bridge nativo y, si hay ADB, reporta fabricante/modelo para revisar politicas reales.
- `prisma-env-validate.ps1`: valida schema, conectividad y round-trip de escritura/borrado contra SQL Server.

## Respaldo

Crear backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\backup.ps1
```

Salida esperada:

- `database.bak`
- `apks.zip`
- `manifest.json`

Todo queda en `artifacts/backups/<timestamp>/`.

## Recuperacion

Restaurar backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\ops\restore.ps1 -BackupDir .\artifacts\backups\<timestamp>
```

Notas:

- restaurar preferiblemente sobre una base controlada o vacia
- validar despues con `GET /api/health`
- revisar que `APK_STORAGE_DIR` quede con los archivos esperados

## Despliegue real

El criterio de HTTPS corporativo no se debe marcar completo solo con configuracion local.

Para cerrarlo en entorno real hace falta:

1. dominio corporativo resolviendo al servidor
2. Caddy atendiendo ese dominio con HTTPS valido
3. backend corriendo en loopback
4. SQL Server privado, no expuesto publicamente
5. health respondiendo correctamente detras del reverse proxy
