param(
  [string]$ApiBaseUrl = "http://127.0.0.1:3100",
  [string]$BackendDir = "D:\google play blumer\back",
  [string]$AdminIdentifier = "admin@empresa.local",
  [string]$AdminPassword = "Admin1234!",
  [string]$PilotApkPath = "D:\google play blumer\artifacts\pilot\corporate-store-0.1.1+102.apk",
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
$employeeEmail = "network.$timestamp@empresa.local"
$employeeUsername = "network$timestamp"
$employeePassword = "Empleado123!"
$deviceIdentifier = "network-device-$timestamp"
$downloadPath = "D:\google play blumer\artifacts\pilot\network-download-$timestamp.apk"
$networkAppPackage = "com.company.network.$timestamp"

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
    firstName = "Network"
    lastName  = "Validation"
    status    = "ACTIVE"
    roleCodes = @("EMPLOYEE")
  }

  $app = Invoke-JsonRequest -Method Post -Uri "$ApiBaseUrl/api/admin/apps" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    packageName            = $networkAppPackage
    slug                   = "network-app-$timestamp"
    displayName            = "Network Validation App"
    shortDescription       = "APK grande para medir descarga"
    description            = "Se usa para medir tiempo, throughput y estabilidad de descarga."
    category               = "ops"
    requiresExplicitAccess = $true
    status                 = "DRAFT"
  }

  $version = Invoke-MultipartUpload -Uri "$ApiBaseUrl/api/admin/apps/$($app.app.id)/versions" -Token $adminToken -FilePath $PilotApkPath -Fields @{
    versionName = "0.1.1"
    versionCode = "102"
    changelog   = "Large download validation"
  }

  $null = Invoke-JsonRequest -Method Patch -Uri "$ApiBaseUrl/api/admin/apps/$($app.app.id)/status" -Headers @{
    Authorization = "Bearer $adminToken"
  } -Body @{
    status = "ACTIVE"
  }

  $null = Invoke-JsonRequest -Method Put -Uri "$ApiBaseUrl/api/admin/apps/$($app.app.id)/users/$($employee.user.id)/access" -Headers @{
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
    name             = "Network Validation Device"
    manufacturer     = "Validation"
    model            = "Bandwidth"
    osVersion        = "14"
    appVersionName   = "1.0.0"
  }

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  Invoke-WebRequest -Uri "$ApiBaseUrl/api/apps/$($app.app.id)/download?deviceId=$($device.device.id)" -Method Get -Headers @{
    Authorization = "Bearer $employeeToken"
  } -OutFile $downloadPath | Out-Null
  $stopwatch.Stop()

  $downloadedFile = Get-Item $downloadPath
  $sizeBytes = [double]$downloadedFile.Length
  $elapsedSeconds = [Math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
  $throughputMbps = [Math]::Round((($sizeBytes / 1MB) / $elapsedSeconds), 2)

  [ordered]@{
    health = $health
    download = @{
      appId = $app.app.id
      versionId = $version.version.id
      filePath = $downloadPath
      fileSizeBytes = [Int64]$downloadedFile.Length
      elapsedSeconds = [Math]::Round($elapsedSeconds, 2)
      throughputMBps = $throughputMbps
      apiBaseUrl = $ApiBaseUrl
      note = if ($ApiBaseUrl -like "http://127.0.0.1*") {
        "Resultado base en entorno local. Repite este script contra la URL corporativa para validar red real."
      } else {
        "Resultado tomado contra la URL indicada. Revisar tambien perdida, cortes y latencia del enlace corporativo."
      }
    }
  } | ConvertTo-Json -Depth 8
} finally {
  if ($backendProcess -and !$backendProcess.HasExited) {
    $backendProcess.Kill()
    $backendProcess.WaitForExit()
  }
}
