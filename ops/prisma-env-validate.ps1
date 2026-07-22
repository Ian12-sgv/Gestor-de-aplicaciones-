param(
  [string]$BackendDir = "D:\google play blumer\back"
)

$ErrorActionPreference = "Stop"

Push-Location $BackendDir

try {
  $validateOutput = & npm.cmd run prisma:validate
  if ($LASTEXITCODE -ne 0) {
    throw "npm run prisma:validate failed"
  }

  $smokeJson = & npm.cmd run prisma:smoke --silent
  if ($LASTEXITCODE -ne 0) {
    throw "npm run prisma:smoke failed"
  }

  $smokeText = $smokeJson -join "`n"
  $jsonStart = $smokeText.IndexOf("{")
  if ($jsonStart -lt 0) {
    throw "Could not find JSON payload in prisma smoke output"
  }

  $smokePayload = $smokeText.Substring($jsonStart) | ConvertFrom-Json

  [ordered]@{
    validateOutput = $validateOutput -join "`n"
    smoke = $smokePayload
  } | ConvertTo-Json -Depth 8
} finally {
  Pop-Location
}
