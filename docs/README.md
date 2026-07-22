# Tienda Privada Android

Repositorio base para una tienda privada de apps Android para empresa.

## Documentos

- [Arquitectura](ARCHITECTURE.md)
- [Especificacion de API](API_SPEC.md)
- [Setup](SETUP.md)
- [Deployment](DEPLOYMENT.md)
- [Operations](OPERATIONS.md)
- [Seguridad](SECURITY.md)
- [Migracion a SQL Server](SQLSERVER_MIGRATION.md)

## Decisiones base

- Caddy es el unico punto expuesto a internet.
- Node.js corre localmente, por ejemplo en `127.0.0.1:3000`.
- SQL Server no se expone a internet.
- Los APKs se descargan por un endpoint protegido del backend.
- Los archivos publicos pequenos, como iconos o logos, pueden servirse directamente desde Caddy cuando convenga.
