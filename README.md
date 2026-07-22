# Corporate App Store

Base inicial de una tienda privada corporativa de aplicaciones Android.

## Stack

- Mobile: Flutter
- Backend: Node.js + TypeScript + Express
- ORM: Prisma
- Database: SQL Server
- Reverse proxy / HTTPS: Caddy

## Estructura

```text
/
  back/
  front/
  docs/
  ARCHITECTURE.md
  ROADMAP.md
  Caddyfile
```

## Estado de esta base

- Backend modular implementado y compilando
- Prisma modelado para SQL Server y cliente generado
- Endpoints base de auth, apps, devices y admin
- Sesiones con `accessToken` corto + `refreshToken` rotativo
- Rate limiting, logs estructurados y health extendido
- Importacion automatica de APKs al copiar archivos en `apks/`
- Mobile Flutter con scaffold Android, UI inicial y flujo real de Android
- Documentacion de arquitectura, API, setup, deployment y seguridad

## Validaciones ejecutadas

- `npm install`
- `npm audit --omit=dev`
- `npm run prisma:generate`
- `npm run build`
- `flutter create --platforms=android ...`
- `flutter analyze`
- `flutter test`

## Documentacion clave

- [ROADMAP](ROADMAP.md)
- [Arquitectura](ARCHITECTURE.md)
- [Docs operativas](docs/README.md)
- [API](docs/API_SPEC.md)
- [Setup](docs/SETUP.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Operations](docs/OPERATIONS.md)
- [Seguridad](docs/SECURITY.md)
