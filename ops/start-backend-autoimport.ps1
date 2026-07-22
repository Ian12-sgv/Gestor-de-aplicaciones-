param(
  [int]$Port = 3100
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $repoRoot "back"

Set-Location $backendPath
$env:PORT = [string]$Port

Write-Host "Starting corporate app store backend on port $Port with APK auto-import enabled..."
node dist/server.js
