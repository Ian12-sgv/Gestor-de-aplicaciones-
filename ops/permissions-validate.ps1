param(
  [string]$ApiBaseUrl = "http://127.0.0.1:3100",
  [string]$BackendDir = "D:\google play blumer\back",
  [string]$AdminIdentifier = "admin@empresa.local",
  [string]$AdminPassword = "Admin1234!",
  [string]$PilotApkPath = "D:\google play blumer\artifacts\pilot\corporate-store-0.1.0+101.apk",
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

  Invoke-RestMethod @requestParams
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

  $rawResponse | ConvertFrom-Json
}

function Wait-ForHealth {
  param([string]$Uri)

  $deadline = (Get-Date).AddSeconds(45)
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

  throw "Backend health check timed out at $Uri"
}

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$employeeEmail = "roles.$timestamp@empresa.local"
$employeeUsername = "roles$timestamp"
$employeePassword = "Empleado123!"
$deviceIdentifier = "roles-device-$timestamp"
$roleAppPackage = "com.company.role.$timestamp"
$userAppPackage = "com.company.user.$timestamp"
$hiddenAppPackage = "com.company.hidden.$timestamp"
$roleDownloadPath = "D:\google play blumer\artifacts\pilot\role-download-$timestamp.apk"
$userDownloadPath = "D:\google play blumer\artifacts\pilot\user-download-$timestamp.apk"

if (-not (Test-Path $PilotApkPath)) {
  throw "Missing pilot APK: $PilotApkPath"
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
    firstName = "Roles"
    lastName  = "Validation"
    status    = "ACTIVE"
    roleCodes = @("EMPLOYEE")
  }

  $roleApp = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $roleAppPackage
    slug                   = "role-app-$timestamp"
    displayName            = "Role Access App"
    shortDescription       = "Visible por rol, sin permiso de instalacion"
    description            = "Se usa para validar permisos de rol."
    category               = "ops"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  $userApp = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $userAppPackage
    slug                   = "user-app-$timestamp"
    displayName            = "User Access App"
    shortDescription       = "Visible por permiso explicito de usuario"
    description            = "Se usa para validar permisos directos por usuario."
    category               = "ops"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  $hiddenApp = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $hiddenAppPackage
    slug                   = "hidden-app-$timestamp"
    displayName            = "Hidden Access App"
    shortDescription       = "Sin permisos para el empleado"
    description            = "No debe aparecer en el catalogo del empleado."
    category               = "ops"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  foreach ($appId in @($roleApp.app.id, $userApp.app.id, $hiddenApp.app.id)) {
    $null = Invoke-MultipartUpload -Uri "$ApiBaseUrl/api/admin/apps/$appId/versions" -Token $adminToken -FilePath $PilotApkPath -Fields @{
      versionName = "0.1.0"
      versionCode = "101"
      changelog   = "Permissions validation build"
    }

    $null = Invoke-JsonRequest -Method Patch -Uri "$ApiBaseUrl/api/admin/apps/$appId/status" -Headers @{
      Authorization = "Bearer $adminToken"
    } -Body @{
      status = "ACTIVE"
    }
  }

  $rolePermission = Invoke-JsonRequest -Method Put -Uri "$ApiBaseUrl/api/admin/apps/$($roleApp.app.id)/roles/EMPLOYEE/access" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    canView    = $true
    canInstall = $false
  }

  $userPermission = Invoke-JsonRequest -Method Put -Uri "$ApiBaseUrl/api/admin/apps/$($userApp.app.id)/users/$($employee.user.id)/access" -Headers @{
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

  $device = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/devices/register" -Headers @{
    Authorization = "Bearer $employeeToken"
  } -Body @{
    deviceIdentifier = $deviceIdentifier
    name             = "Roles Validation Device"
    manufacturer     = "Validation"
    model            = "Policy"
    osVersion        = "14"
    appVersionName   = "1.0.0"
  }

  $catalog = Invoke-RestMethod -Uri "$ApiBaseUrl/api/apps?deviceId=$($device.device.id)" -Method Get -Headers @{
    Authorization = "Bearer $employeeToken"
  }

  $roleDownloadStatus = $null
  try {
    Invoke-WebRequest -Uri "$ApiBaseUrl/api/apps/$($roleApp.app.id)/download?deviceId=$($device.device.id)" -Method Get -Headers @{
      Authorization = "Bearer $employeeToken"
    } -OutFile $roleDownloadPath | Out-Null
    $roleDownloadStatus = 200
  } catch {
    $roleDownloadStatus = $_.Exception.Response.StatusCode.value__
  }

  $userDownloadOk = $false
  try {
    Invoke-WebRequest -Uri "$ApiBaseUrl/api/apps/$($userApp.app.id)/download?deviceId=$($device.device.id)" -Method Get -Headers @{
      Authorization = "Bearer $employeeToken"
    } -OutFile $userDownloadPath | Out-Null
    $userDownloadOk = Test-Path $userDownloadPath
  } catch {
    $userDownloadOk = $false
  }

  [ordered]@{
    health = $health
    employee = $employee.user
    permissions = @{
      rolePermission = $rolePermission.permission
      userPermission = $userPermission.permission
    }
    results = @{
      catalogAppNames = @($catalog.items | ForEach-Object { $_.displayName })
      roleGrantedVisibility = @($catalog.items | Where-Object { $_.id -eq $roleApp.app.id }).Count -eq 1
      userGrantedVisibility = @($catalog.items | Where-Object { $_.id -eq $userApp.app.id }).Count -eq 1
      hiddenAppExcluded = @($catalog.items | Where-Object { $_.id -eq $hiddenApp.app.id }).Count -eq 0
      rolePermissionBlockedInstall = $roleDownloadStatus -eq 404
      userPermissionAllowedInstall = $userDownloadOk
      overallOk =
        (@($catalog.items | Where-Object { $_.id -eq $roleApp.app.id }).Count -eq 1) -and
        (@($catalog.items | Where-Object { $_.id -eq $userApp.app.id }).Count -eq 1) -and
        (@($catalog.items | Where-Object { $_.id -eq $hiddenApp.app.id }).Count -eq 0) -and
        ($roleDownloadStatus -eq 404) -and
        $userDownloadOk
    }
  } | ConvertTo-Json -Depth 10
} finally {
  if ($backendProcess -and !$backendProcess.HasExited) {
    $backendProcess.Kill()
    $backendProcess.WaitForExit()
  }
}
