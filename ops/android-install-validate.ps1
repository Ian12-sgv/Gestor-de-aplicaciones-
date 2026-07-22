param(
  [string]$ManifestPath = "D:\google play blumer\front\android\app\src\main\AndroidManifest.xml",
  [string]$MainActivityPath = "D:\google play blumer\front\android\app\src\main\kotlin\com\company\corporateappstore\corporate_app_store\MainActivity.kt",
  [string]$StorePackageName = "com.company.corporateappstore.corporate_app_store"
)

$ErrorActionPreference = "Stop"

function Get-AdbPath {
  return Join-Path $env:USERPROFILE "AppData\Local\Android\sdk\platform-tools\adb.exe"
}

function Get-ConnectedAdbDevice {
  $adbPath = Get-AdbPath

  if (-not (Test-Path $adbPath)) {
    return $null
  }

  $lines = & $adbPath devices
  $deviceLines = $lines | Where-Object { $_ -match "device$" -and $_ -notmatch "^List of devices" }

  if (-not $deviceLines) {
    return $null
  }

  return ($deviceLines[0] -split "\s+")[0]
}

$manifestContent = Get-Content -Path $ManifestPath -Raw
$mainActivityContent = Get-Content -Path $MainActivityPath -Raw

$staticChecks = [ordered]@{
  hasRequestInstallPackagesPermission = $manifestContent -match 'android\.permission\.REQUEST_INSTALL_PACKAGES'
  hasQueryAllPackagesPermission = $manifestContent -match 'android\.permission\.QUERY_ALL_PACKAGES'
  hasFileProvider = $manifestContent -match 'androidx\.core\.content\.FileProvider'
  canOpenUnknownSourcesSettings = $mainActivityContent -match 'Settings\.ACTION_MANAGE_UNKNOWN_APP_SOURCES'
  checksCanRequestPackageInstalls = $mainActivityContent -match 'canRequestPackageInstalls\(\)'
  exposesInstallEnvironmentInfo = $mainActivityContent -match 'getInstallEnvironmentInfo'
}

$adbDevice = Get-ConnectedAdbDevice
$deviceChecks = [ordered]@{
  adbDevice = $adbDevice
  manufacturer = $null
  model = $null
  androidVersion = $null
  storeAppInstalled = $false
  blockedReason = $null
}

if ($adbDevice) {
  $adbPath = Get-AdbPath
  $deviceChecks.manufacturer = (& $adbPath -s $adbDevice shell getprop ro.product.manufacturer).Trim()
  $deviceChecks.model = (& $adbPath -s $adbDevice shell getprop ro.product.model).Trim()
  $deviceChecks.androidVersion = (& $adbPath -s $adbDevice shell getprop ro.build.version.release).Trim()
  $packagesOutput = (& $adbPath -s $adbDevice shell pm list packages $StorePackageName)
  $deviceChecks.storeAppInstalled = [bool]($packagesOutput | Select-String $StorePackageName)
} else {
  $deviceChecks.blockedReason = "No hay un dispositivo ADB conectado para validar fabricante, modelo y politicas reales."
}

[ordered]@{
  staticChecks = $staticChecks
  deviceChecks = $deviceChecks
  overallStaticOk = ($staticChecks.Values | Where-Object { -not $_ }).Count -eq 0
} | ConvertTo-Json -Depth 6
