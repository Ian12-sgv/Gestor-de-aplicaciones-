# Migracion a SQL Server

## Alcance

El backend queda configurado para usar SQL Server con Prisma:

- `back/prisma/schema.prisma` usa `provider = "sqlserver"`.
- Las claves UUID se mapearon a `UNIQUEIDENTIFIER`.
- Las migraciones PostgreSQL anteriores quedaron archivadas en `back/prisma/postgres_migrations_archive/`.
- La migracion activa inicial para SQL Server esta en `back/prisma/migrations/20260429090000_init_sqlserver/`.

## DATABASE_URL

Formato esperado:

```text
sqlserver://localhost:1433;database=pdb_store;user=sa;password=ChangeMe123!;encrypt=true;trustServerCertificate=true
```

En produccion cambia `user`, `password`, host y politica TLS por valores reales. SQL Server debe quedar privado, accesible solo desde el backend o la red interna autorizada.

## Puesta en marcha limpia

1. Configurar `DATABASE_URL` con formato `sqlserver://...`.
2. Crear la base de datos vacia `pdb_store` en SQL Server.
3. Ejecutar:

```bash
npm run prisma:create-db
npm run prisma:generate
npm run prisma:migrate:deploy
npm run prisma:seed
npm run users:create-requested
npm run build
```

4. Validar:

```bash
npm run prisma:smoke
```

`npm run prisma:create-db` se conecta a `master` usando la misma `DATABASE_URL` y crea la base configurada en `database=...` si no existe. `npm run prisma:migrate:deploy` crea las tablas, indices, llaves y la tabla `_prisma_migrations`.

## Migracion de datos existentes

Las migraciones Prisma crean la estructura en SQL Server. Para mover datos reales desde PostgreSQL a SQL Server se debe hacer una migracion de datos controlada, normalmente con:

- exportacion desde PostgreSQL a CSV por tabla
- importacion a SQL Server respetando orden de llaves foraneas
- verificacion de conteos por tabla
- smoke test de login, catalogo, descarga y auditoria

No mezcles la tabla `_prisma_migrations` vieja de PostgreSQL con SQL Server. La base SQL Server debe registrar solo las migraciones nuevas de este proveedor.
