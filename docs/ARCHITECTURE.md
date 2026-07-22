# Arquitectura

## Objetivo

Construir un portal privado de apps Android para aplicaciones internas de la empresa, con autenticacion, catalogo, control de versiones, trazabilidad y una base preparada para evolucionar hacia MDM o Android Enterprise.

## Componentes

- `Flutter mobile app`: cliente principal para usuarios finales.
- `Caddy`: terminacion HTTPS, reverse proxy y unico punto expuesto.
- `Node.js + Express`: API principal de negocio.
- `Prisma`: acceso tipado a datos.
- `SQL Server`: persistencia central.
- `Almacenamiento de APKs`: carpeta local o volumen montado en el servidor, no publico.

## Flujo de red

1. El dispositivo Android abre la app Flutter.
2. Flutter llama a la API por HTTPS a traves del dominio publico.
3. Caddy recibe la peticion.
4. Caddy enruta `/api/*` hacia Node.js en `127.0.0.1:3000`.
5. Node.js consulta SQL Server por medio de Prisma.
6. Para descargar APKs, Node valida permisos y sirve el archivo mediante stream protegido.
7. Para iconos o assets pequenos, Caddy puede servir contenido estatico si se decide habilitar esa ruta.

## Flujo de autenticacion

- El usuario inicia sesion con email o usuario y password.
- El backend valida credenciales con `bcrypt`.
- Si es correcto, emite un `accessToken` JWT corto y un `refreshToken` rotativo.
- Flutter guarda ambos tokens y envia `Authorization: Bearer <accessToken>`.
- Cada request autenticado vuelve a validar el usuario en base de datos y su `sessionVersion`.

## Flujo de catalogo

- Flutter consulta `GET /api/apps`.
- El backend devuelve apps activas, versiones disponibles y metadatos.
- El cliente cruza el `packageName` con la instalacion local reportada o detectada por el propio sistema Android para mostrar instalado, version y estado de actualizacion.

## Flujo de descarga

- Flutter solicita `GET /api/apps/:id/download`.
- El backend verifica autenticacion, permisos y version objetivo.
- El archivo APK se lee desde almacenamiento privado y se devuelve como descarga controlada.
- Se registra el evento en `InstallationLog` o una tabla equivalente.

## Instalacion y actualizacion

- En Android estandar no se asume instalacion silenciosa.
- La app principal descarga el APK y lanza el instalador del sistema.
- El usuario confirma la instalacion o actualizacion.
- El backend conserva trazabilidad de descarga, intento e instalacion reportada.
- La base queda preparada para evolucionar a MDM o Android Enterprise si luego se habilita.

## Identificacion de apps instaladas

- La app Flutter puede comparar el `packageName` del catalogo con la lista local de paquetes instalados.
- El backend puede recibir reportes de instalacion por dispositivo para auditoria y version historica.
- La version instalada se representa por `versionName` y, si aplica, `versionCode`.

## Apertura de apps instaladas

- Si la app esta instalada, Flutter puede invocar el launcher del paquete.
- La app no necesita pasar por el backend para abrir una aplicacion local.
- El backend solo conserva el estado y la trazabilidad.

## Responsabilidades por capa

- `Flutter`: autenticacion, UI, deteccion local, apertura de apps, descarga e instalacion guiada.
- `Caddy`: HTTPS, headers, reverse proxy, archivos publicos pequenos.
- `Node.js`: reglas de negocio, autorizacion, metadatos, descargas y auditoria.
- `Prisma` y `SQL Server`: persistencia, relaciones y consulta.
