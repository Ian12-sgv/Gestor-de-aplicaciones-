param(
  [string]$ApiBaseUrl = "http://127.0.0.1:3100",
  [string]$BackendDir = "D:\google play blumer\back",
  [string]$ArtifactsDir = "D:\google play blumer\artifacts\pilot",
  [string]$AdminIdentifier = "admin@empresa.local",
  [string]$AdminPassword = "Admin1234!",
  [switch]$StartBackend
)

$ErrorActionPreference = "Stop"

function Invoke-JsonRequest {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Uri,
    [hashtable]$Headers,
    [object]$Body
  )

  $requestParams = @{
    Method      = $Method
    Uri         = $Uri
    Headers     = $Headers
    ContentType = "application/json"
  }

  if ($null -ne $Body) {
    $requestParams.Body = ($Body | ConvertTo-Json -Depth 10)
  }

  return Invoke-RestMethod @requestParams
}

function Invoke-MultipartUpload {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][hashtable]$Fields
  )

  $curlArguments = @(
    "-sS",
    "-X", "POST",
    $Uri,
    "-H", "Authorization: Bearer $Token"
  )

  foreach ($entry in $Fields.GetEnumerator()) {
    $curlArguments += "-F"
    $curlArguments += "$($entry.Key)=$($entry.Value)"
  }

  $curlArguments += "-F"
  $curlArguments += "apkFile=@$FilePath;type=application/vnd.android.package-archive"

  $rawResponse = & curl.exe @curlArguments

  if ($LASTEXITCODE -ne 0) {
    throw "curl upload failed for $Uri"
  }

  return $rawResponse | ConvertFrom-Json
}

function Wait-ForHealth {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [int]$TimeoutSeconds = 45
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-RestMethod -Uri $Uri -Method Get
      if ($response.status -eq "ok" -or $response.status -eq "degraded") {
        return $response
      }
    } catch {
      Start-Sleep -Milliseconds 800
    }
  }

  throw "Backend health check did not respond in time at $Uri"
}

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

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$adbDevice = Get-ConnectedAdbDevice
$pilotAppPackage = if ($adbDevice) { "com.company.corporateappstore.corporate_app_store" } else { "com.company.pilot.$timestamp" }
$pilotHiddenPackage = "com.company.hidden.$timestamp"
$employeeEmail = "empleado.$timestamp@empresa.local"
$employeeUsername = "empleado$timestamp"
$employeePassword = "Empleado123!"
$deviceIdentifier = "pilot-device-$timestamp"
$downloadedApkPath = Join-Path $ArtifactsDir "downloaded-latest-$timestamp.apk"
$version101Apk = Join-Path $ArtifactsDir "corporate-store-0.1.0+101.apk"
$version102Apk = Join-Path $ArtifactsDir "corporate-store-0.1.1+102.apk"

if (-not (Test-Path $version101Apk)) {
  throw "Missing pilot APK: $version101Apk"
}

if (-not (Test-Path $version102Apk)) {
  throw "Missing pilot APK: $version102Apk"
}

$backendProcess = $null

try {
  if ($StartBackend) {
    $backendProcess = Start-Process -FilePath cmd.exe -ArgumentList "/c", "set PORT=3100 && cd /d `"$BackendDir`" && node dist\server.js" -PassThru
  }

  $health = Wait-ForHealth -Uri "$ApiBaseUrl/api/health"

  $adminSession = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/auth/login" -Body @{
    identifier = $AdminIdentifier
    password   = $AdminPassword
  }

  $adminToken = $adminSession.accessToken

  $employee = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/users" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    email     = $employeeEmail
    username  = $employeeUsername
    password  = $employeePassword
    firstName = "Empleado"
    lastName  = "Piloto"
    status    = "ACTIVE"
    roleCodes = @("EMPLOYEE")
  }

  $pilotApp = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $pilotAppPackage
    slug                   = "portal-pilot-$timestamp"
    displayName            = "Portal Corporativo Pilot"
    shortDescription       = "Validacion piloto de publicacion y updates"
    description            = "App de piloto para validar catalogo, descarga, update y trazabilidad."
    category               = "internal"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  $hiddenApp = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $pilotHiddenPackage
    slug                   = "solo-admin-$timestamp"
    displayName            = "Solo Admin Pilot"
    shortDescription       = "App no autorizada para el empleado"
    description            = "Se usa para validar filtrado de catalogo por permiso explicito."
    category               = "internal"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  $version101 = Invoke-MultipartUpload -Uri "$ApiBaseUrl/api/admin/apps/$($pilotApp.app.id)/versions" -Token $adminToken -FilePath $version101Apk -Fields @{
    versionName = "0.1.0"
    versionCode = "101"
    changelog   = "Version piloto inicial"
  }

  $version102 = Invoke-MultipartUpload -Uri "$ApiBaseUrl/api/admin/apps/$($pilotApp.app.id)/versions" -Token $adminToken -FilePath $version102Apk -Fields @{
    versionName             = "0.1.1"
    versionCode             = "102"
    changelog               = "Version piloto con update disponible"
    minSupportedVersionCode = "101"
  }

  $null = Invoke-MultipartUpload -Uri "$ApiBaseUrl/api/admin/apps/$($hiddenApp.app.id)/versions" -Token $adminToken -FilePath $version101Apk -Fields @{
    versionName = "0.1.0"
    versionCode = "101"
    changelog   = "Version restringida"
  }

  $null = Invoke-JsonRequest -Method Patch -Uri "$ApiBaseUrl/api/admin/apps/$($pilotApp.app.id)/status" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    status = "ACTIVE"
  }

  $null = Invoke-JsonRequest -Method Patch -Uri "$ApiBaseUrl/api/admin/apps/$($hiddenApp.app.id)/status" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    status = "ACTIVE"
  }

  $permission = Invoke-JsonRequest -Method Put -Uri "$ApiBaseUrl/api/admin/apps/$($pilotApp.app.id)/users/$($employee.user.id)/access" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    canView    = $true
    canInstall = $true
  }

  $employeeSession = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/auth/login" -Body @{
    identifier = $employeeEmail
    password   = $employeePassword
  }

  $employeeToken = $employeeSession.accessToken

  $registeredDevice = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/devices/register" -Headers @{
    Authorization = "Bearer $employeeToken"
  } -Body @{
    deviceIdentifier = $deviceIdentifier
    name             = "PDA Piloto"
    manufacturer     = "Zebra"
    model            = "TC52"
    osVersion        = "14"
    appVersionName   = "pilot"
  }

  $null = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/devices/report-installation" -Headers @{
    Authorization = "Bearer $employeeToken"
  } -Body @{
    deviceId              = $registeredDevice.device.id
    appId                 = $pilotApp.app.id
    appVersionId          = $version101.version.id
    installedVersionCode  = 101
    installedVersionName  = "0.1.0"
    action                = "INSTALL"
    status                = "SUCCESS"
    deviceAppStatus       = "INSTALLED"
    notes                 = "Instalacion piloto inicial"
  }

  $catalogBeforeUpdate = Invoke-RestMethod -Uri "$ApiBaseUrl/api/apps?deviceId=$($registeredDevice.device.id)" -Method Get -Headers @{
    Authorization = "Bearer $employeeToken"
  }

  Invoke-WebRequest -Uri "$ApiBaseUrl/api/apps/$($pilotApp.app.id)/download?deviceId=$($registeredDevice.device.id)" -Method Get -Headers @{
    Authorization = "Bearer $employeeToken"
  } -OutFile $downloadedApkPath | Out-Null

  $deviceInstall = @{
    usedAdbDevice = $false
    installed101  = $false
    installed102  = $false
    blockedReason = $null
  }

  if ($adbDevice) {
    $adbPath = Get-AdbPath
    & $adbPath -s $adbDevice install -r $version101Apk | Out-Null
    $deviceInstall.installed101 = $LASTEXITCODE -eq 0
    $deviceInstall.usedAdbDevice = $true

    & $adbPath -s $adbDevice install -r $downloadedApkPath | Out-Null
    $deviceInstall.installed102 = $LASTEXITCODE -eq 0
  } else {
    $deviceInstall.blockedReason = "No hay un dispositivo ADB conectado en este momento."
  }

  $null = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/devices/report-installation" -Headers @{
    Authorization = "Bearer $employeeToken"
  } -Body @{
    deviceId              = $registeredDevice.device.id
    appId                 = $pilotApp.app.id
    appVersionId          = $version102.version.id
    installedVersionCode  = 102
    installedVersionName  = "0.1.1"
    action                = "UPDATE"
    status                = if ($deviceInstall.installed102) { "SUCCESS" } else { "PENDING" }
    deviceAppStatus       = "INSTALLED"
    notes                 = if ($deviceInstall.installed102) { "Update piloto aplicado" } else { "Descarga piloto lista para instalar" }
  }

  $catalogAfterDownload = Invoke-RestMethod -Uri "$ApiBaseUrl/api/apps?deviceId=$($registeredDevice.device.id)" -Method Get -Headers @{
    Authorization = "Bearer $employeeToken"
  }

  $installationLogs = Invoke-RestMethod -Uri "$ApiBaseUrl/api/admin/installation-logs?appId=$($pilotApp.app.id)&deviceId=$($registeredDevice.device.id)&limit=20" -Method Get -Headers @{
    Authorization = "Bearer $adminToken"
  }

  $summary = [ordered]@{
    health = $health
    pilot = @{
      employeeEmail     = $employeeEmail
      pilotAppId        = $pilotApp.app.id
      hiddenAppId       = $hiddenApp.app.id
      registeredDeviceId = $registeredDevice.device.id
      permission        = $permission.permission
    }
    criteria = @{
      adminPublishedAppWithTwoVersions = ($version101.version.id -and $version102.version.id)
      employeeSeesOnlyEnabledApps = (($catalogBeforeUpdate.items | Measure-Object).Count -eq 1 -and $catalogBeforeUpdate.items[0].id -eq $pilotApp.app.id)
      updateAvailableDetected = [bool]$catalogBeforeUpdate.items[0].updateAvailable
      downloadedPublishedVersion = (Test-Path $downloadedApkPath)
      backendTraceabilityCaptured = (($installationLogs.items | Measure-Object).Count -ge 2)
      androidDeviceInstalledPublishedVersion = [bool]$deviceInstall.installed102
      androidDeviceValidationBlockedReason = $deviceInstall.blockedReason
    }
    catalogBeforeUpdate = $catalogBeforeUpdate
    catalogAfterDownload = $catalogAfterDownload
    installationLogs = $installationLogs
    deviceInstall = $deviceInstall
  }

  $summary | ConvertTo-Json -Depth 12
} finally {
  if ($backendProcess -and !$backendProcess.HasExited) {
    $backendProcess.Kill()
    $backendProcess.WaitForExit()
  }
}
