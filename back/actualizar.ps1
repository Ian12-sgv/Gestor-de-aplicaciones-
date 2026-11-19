# Despliegue autocontenido de PDB Store en Windows.
# Uso: copia deploy\back encima de la carpeta back del servidor y ejecuta
# ACTUALIZAR.bat. El servidor necesita Node.js 22+, SQL Server accesible y Caddy.

[CmdletBinding()]
param(
  [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$backPath = $PSScriptRoot
$envFile = Join-Path $backPath '.env'
$logDir = Join-Path $backPath 'logs'
Set-Location $backPath

function Step([string]$message) {
  Write-Host ''
  Write-Host "==> $message" -ForegroundColor Cyan
}

function Fail([string]$message) {
  Write-Host ''
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

function Run([string]$command) {
  cmd /c $command
  if ($LASTEXITCODE -ne 0) {
    Fail "Fallo el comando: $command"
  }
}

function Import-EnvironmentFile([string]$path) {
  foreach ($rawLine in Get-Content -LiteralPath $path) {
    $line = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
      continue
    }

    $match = [regex]::Match($line, '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
    if (-not $match.Success) {
      Fail "Linea no valida en .env: $rawLine"
    }

    $name = $match.Groups[1].Value
    $value = $match.Groups[2].Value.Trim()
    if ($value.Length -ge 2 -and (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    )) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    Set-Item -Path "Env:$name" -Value $value
  }
}

function Set-EnvironmentFileValue([string]$name, [string]$value) {
  $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $envFile)
  $replaced = $false
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match "^$([regex]::Escape($name))=") {
      $lines[$index] = "$name=$value"
      $replaced = $true
      break
    }
  }
  if (-not $replaced) {
    $lines.Add("$name=$value")
  }

  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($envFile, $lines, $utf8)
  Set-Item -Path "Env:$name" -Value $value
}

function Require-Setting([string]$name) {
  $value = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    Fail "Falta $name en back\.env."
  }
  return $value
}

function Resolve-ProductionDirectory([string]$name, [string]$fallbackRelativePath) {
  $configured = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ([string]::IsNullOrWhiteSpace($configured)) {
    $configured = $fallbackRelativePath
  }

  $absolutePath = if ([System.IO.Path]::IsPathRooted($configured)) {
    $configured
  } else {
    Join-Path $backPath $configured
  }
  $absolutePath = [System.IO.Path]::GetFullPath($absolutePath)

  New-Item -ItemType Directory -Force -Path $absolutePath | Out-Null
  Set-Item -Path "Env:$name" -Value $absolutePath
  return $absolutePath
}

if (-not (Test-Path -LiteralPath $envFile)) {
  $template = Join-Path $backPath '.env.example'
  if (-not (Test-Path -LiteralPath $template)) {
    Fail 'No existe back\.env ni back\.env.example.'
  }
  Copy-Item -LiteralPath $template -Destination $envFile
  Write-Host 'Se creo back\.env desde .env.example.' -ForegroundColor Yellow
}

Step 'Cargando configuracion'
Import-EnvironmentFile $envFile

# El actualizador inyecta estos valores al proceso Node, por lo que no depende
# de dotenv en produccion y el health check reporta runtime-environment.
Set-Item -Path 'Env:NODE_ENV' -Value 'production'
Set-Item -Path 'Env:ALLOW_DOTENV_IN_PROD' -Value 'false'

$corsOrigin = [Environment]::GetEnvironmentVariable('CORS_ORIGIN', 'Process')
if ([string]::IsNullOrWhiteSpace($corsOrigin) -or $corsOrigin -eq '*' -or $corsOrigin -eq 'https://apps.company.com') {
  Set-Item -Path 'Env:CORS_ORIGIN' -Value 'https://pdbstore.apipalacio.com'
}

if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('TRUST_PROXY', 'Process'))) {
  Set-Item -Path 'Env:TRUST_PROXY' -Value 'loopback'
}

$jwtSecret = Require-Setting 'JWT_SECRET'
if ($jwtSecret.Length -lt 32 -or $jwtSecret.Contains('replace-with-a-long-random-secret')) {
  $randomBytes = New-Object byte[] 48
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
  $jwtSecret = [Convert]::ToBase64String($randomBytes)
  Set-EnvironmentFileValue 'JWT_SECRET' $jwtSecret
  Write-Host 'Se genero y guardo un JWT_SECRET seguro en back\.env.' -ForegroundColor Yellow
}

$databaseUrl = Require-Setting 'DATABASE_URL'
if ($databaseUrl.Contains('ChangeMe123')) {
  Fail 'DATABASE_URL conserva la credencial de ejemplo. Configura la conexion real de SQL Server en back\.env.'
}

$apkStorageDirectory = Resolve-ProductionDirectory 'APK_STORAGE_DIR' 'storage\apks'
$mediaStorageDirectory = Resolve-ProductionDirectory 'MEDIA_STORAGE_DIR' 'storage\media'
$adminWebDirectory = Resolve-ProductionDirectory 'ADMIN_WEB_DIR' 'admin-web'
if (-not (Test-Path -LiteralPath (Join-Path $adminWebDirectory 'index.html'))) {
  Fail "No se encontro admin-web\index.html en $adminWebDirectory."
}

if ($Port -eq 0) {
  $configuredPort = [Environment]::GetEnvironmentVariable('PORT', 'Process')
  $Port = if ([string]::IsNullOrWhiteSpace($configuredPort)) { 5201 } else { [int]$configuredPort }
}
Set-Item -Path 'Env:PORT' -Value ([string]$Port)

Step 'Instalando dependencias bloqueadas'
Run 'npm ci --no-audit --no-fund'

Step 'Generando cliente de base de datos'
Run 'npx prisma generate'

Step 'Compilando backend'
Run 'npm run build'

Step 'Aplicando migraciones pendientes'
Run 'npx prisma migrate deploy'

Step "Reiniciando backend en el puerto $Port"
$listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
foreach ($listener in $listeners) {
  Write-Host "Deteniendo proceso anterior (PID $($listener.OwningProcess))"
  Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
  Fail "Un servicio externo reinicio el proceso en el puerto $Port. Configura sus variables de produccion o deshabilitalo antes de ejecutar ACTUALIZAR.bat."
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Process -FilePath 'node' -ArgumentList 'dist/server.js' -WorkingDirectory $backPath `
  -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $logDir 'server.out.log') `
  -RedirectStandardError (Join-Path $logDir 'server.err.log')

Step 'Comprobando disponibilidad'
$healthy = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
  Start-Sleep -Seconds 2
  try {
    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$Port/api/health"
    if ($response.StatusCode -eq 200) {
      $health = $response.Content | ConvertFrom-Json
      if ($health.environment -eq 'production' -and
        $health.configSource -eq 'runtime-environment' -and
        $health.checks.database.status -eq 'ok' -and
        $health.checks.apkStorage.status -eq 'ok') {
        $healthy = $true
        break
      }
    }
  } catch {
    # El detalle se muestra al finalizar usando el log del backend.
  }
}

Write-Host ''
if ($healthy) {
  Write-Host "LISTO: PDB Store funciona en el puerto $Port." -ForegroundColor Green
  Write-Host 'Panel web: https://pdbstore.apipalacio.com/admin/'
  exit 0
}

Write-Host 'El backend no paso la verificacion de produccion.' -ForegroundColor Red
$errLog = Join-Path $logDir 'server.err.log'
if (Test-Path -LiteralPath $errLog) {
  Get-Content -LiteralPath $errLog -Tail 20
}
exit 1