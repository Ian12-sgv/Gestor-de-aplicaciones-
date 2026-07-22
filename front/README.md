# Corporate App Store Mobile

Base Flutter para una tienda privada corporativa de apps Android.

## Enfoque

- `lib/src/core` concentra configuracion, networking, routing y UI compartida.
- `lib/src/features/auth` maneja inicio de sesion y sesion local.
- `lib/src/features/apps` modela catalogo, detalle, changelog y estado instalar/actualizar/abrir.
- `lib/src/features/device` prepara registro de dispositivo y reporte de instalacion.

## Notas

- La instalacion silenciosa no se asume disponible en Android estandar.
- Esta base deja preparado el flujo para descargar APK, abrir instalador del sistema y reportar eventos al backend.
- El modo demo sigue disponible, pero el comportamiento por defecto ya apunta al backend real.

## Variables de entorno

Usa `--dart-define`:

- `API_BASE_URL`
- `USE_DEMO_DATA`

Ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=USE_DEMO_DATA=false
```
