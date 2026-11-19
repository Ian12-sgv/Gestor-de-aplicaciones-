# Crea deploy\back (y deploy\back.zip) listo para copiar encima de la carpeta back del servidor.
# Excluye lo que pertenece solo al servidor o a esta PC: .env, storage (APKs), node_modules, dist y logs.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "back"
$deployRoot = Join-Path $repoRoot "deploy"
$target = Join-Path $deployRoot "back"
$zipPath = Join-Path $deployRoot "back.zip"

if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force $target | Out-Null

robocopy $source $target /E /NFL /NDL /NJH /NJS /NP `
  /XD node_modules dist storage logs test `
  /XF .env *.log | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy fallo con codigo $LASTEXITCODE" }

if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path $target -DestinationPath $zipPath

Write-Host "Paquete listo:" -ForegroundColor Green
Write-Host "  Carpeta: $target"
Write-Host "  ZIP:     $zipPath"
Write-Host "Copia su contenido encima de la carpeta back del servidor y ejecuta ACTUALIZAR.bat alli."
exit 0
