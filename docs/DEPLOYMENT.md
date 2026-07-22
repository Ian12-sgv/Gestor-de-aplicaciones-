# Despliegue

## Principio de despliegue

- Solo Caddy expuesto a internet.
- Node.js escucha en loopback.
- SQL Server permanece privado.
- Los APKs no deben quedar publicos si requieren autenticacion o trazabilidad.
- El backend debe arrancar con `NODE_ENV=production` y variables inyectadas por el servicio.

## Estructura de servidor sugerida

```text
/opt/private-store/
  back/
  apks/
  logs/
  backups/
```

## Secretos y runtime

- Inyectar `DATABASE_URL`, `JWT_SECRET` y demas secretos desde el servicio del sistema, contenedor o plataforma de despliegue.
- No copiar `.env` al servidor de produccion como mecanismo permanente.
- Verificar `configSource` en `GET /api/health` despues del despliegue.
- Mantener `ALLOW_DOTENV_IN_PROD=false`.
- Usar `HOST=127.0.0.1`, `TRUST_PROXY=loopback` y `CORS_ORIGIN=https://store.empresa.com` o el dominio corporativo real.
- Usar `APK_STORAGE_DIR` absoluto y privado, por ejemplo `/opt/private-store/apks`.

## Manejo de APKs

- Guardar APKs en un directorio privado o volumen dedicado.
- Permitir lectura y escritura solo al usuario del proceso backend.
- Registrar en base de datos ruta, hash, version y metadatos del archivo.
- Servir la descarga por el backend para poder validar permisos.

## Reverse proxy

- Caddy atiende el dominio publico con HTTPS automatico.
- Las rutas `/api/*` se proxyan al backend local.
- Los assets publicos pequenos pueden servirse por separado si no son sensibles.
- El puerto de Node no debe abrirse en firewall publico.
- Si Caddy y Node no corren en la misma maquina, ajustar `TRUST_PROXY` al rango o proxy confiable correspondiente antes de exponerlo.
- El backend calcula la IP cliente con `req.ip`, no leyendo `x-forwarded-for` manualmente. Por eso `TRUST_PROXY` debe coincidir con el proxy real.
- Con Caddy en la misma maquina, usar `TRUST_PROXY=loopback` y mantener Node en `HOST=127.0.0.1`.

Cabeceras esperadas en el reverse proxy:

```caddyfile
reverse_proxy 127.0.0.1:3000 {
  header_up Host {host}
  header_up X-Forwarded-Host {host}
  header_up X-Forwarded-Proto {scheme}
}
```

## Rate limiting

El backend aplica dos capas:

- limite general sobre `/api/*`, excepto `/api/health`
- limite reforzado en `POST /api/auth/login` por combinacion de IP resuelta e identificador
- limite reforzado en `POST /api/auth/refresh` por IP resuelta

Variables:

- `RATE_LIMIT_WINDOW_MS`: ventana del limite general
- `RATE_LIMIT_MAX_REQUESTS`: solicitudes permitidas por ventana general
- `RATE_LIMIT_MAX_BUCKETS`: cantidad maxima de buckets en memoria antes de purgar los menos recientes
- `AUTH_RATE_LIMIT_WINDOW_MS`: ventana de autenticacion
- `AUTH_RATE_LIMIT_MAX_REQUESTS`: intentos permitidos para login/refresh

Para una sola instancia o piloto, el limitador en memoria es suficiente. Si el backend se escala a multiples procesos o servidores, mover rate limiting a una capa compartida, por ejemplo Redis, WAF o el proxy corporativo.

## Validaciones antes de marcar produccion

- `NODE_ENV=production npm run build` compila sin errores.
- El proceso falla si `CORS_ORIGIN=*`, `HOST=0.0.0.0`, `APK_STORAGE_DIR` relativo o `ALLOW_DOTENV_IN_PROD=true`.
- `GET /api/health` responde con `environment=production`, `configSource=runtime-environment` y checks `database`/`apkStorage` en `ok`.
- `GET /api/health` muestra los valores efectivos de rate limiting, incluyendo `maxBuckets`.
- Un request con `X-Forwarded-For` falsificado no debe cambiar la identidad de cliente si no proviene del proxy confiable configurado.
- Desde otra maquina no debe ser posible conectar directo al puerto Node; solo al dominio HTTPS de Caddy.
- SQL Server debe aceptar conexiones solo desde localhost/red privada.

## Flujo recomendado

1. Usuario accede a `https://store.empresa.com`.
2. Caddy termina TLS.
3. Las solicitudes API van a Node.
4. Node consulta SQL Server.
5. Node entrega descargas de APKs protegidas.
6. El cliente registra instalaciones y eventos.

## Operacion minima

- Habilitar logs de acceso en Caddy.
- Mantener logs estructurados del backend en JSON.
- Restringir el puerto de SQL Server a red privada o localhost.
- Configurar monitoreo del health del backend y de espacio en disco del storage.

## Health y monitoreo

- `GET /api/health` debe responder `200` solo si base y storage estan disponibles.
- Un `503` indica degradacion real y debe levantar alerta operativa.
- Supervisar por separado Caddy, backend, SQL Server y storage de APKs.

## Backups y retencion

Politica minima recomendada:

- SQL Server:
  - snapshot o backup logico diario
  - retencion diaria: 14 dias
  - retencion semanal: 8 semanas
  - retencion mensual: 6 meses
- APKs:
  - copia incremental diaria del storage
  - copia completa semanal
  - retencion minima: 90 dias
- Auditoria y logs:
  - `InstallationLog`: 180 dias minimo, 365 dias recomendado
  - logs de backend: 30 a 90 dias

Scripts incluidos en el repo:

- backup: `powershell -ExecutionPolicy Bypass -File .\ops\backup.ps1`
- restore: `powershell -ExecutionPolicy Bypass -File .\ops\restore.ps1 -BackupDir .\artifacts\backups\<timestamp>`

## Recuperacion

- Probar restauracion de base y storage al menos una vez por trimestre.
- Documentar el ultimo backup valido y el tiempo objetivo de recuperacion esperado.
- Restaurar base y APKs del mismo punto temporal cuando se necesite consistencia historica.
