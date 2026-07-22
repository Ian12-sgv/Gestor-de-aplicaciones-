param(
  [string]$BackendEnvPath = "D:\google play blumer\back\.env",
  [string]$ApkStoragePath = "D:\google play blumer\back\storage\apks",
  [string]$OutputRoot = "D:\google play blumer\artifacts\backups"
)

$ErrorActionPreference = "Stop"

function Get-EnvValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Key
  )

  $line = Get-Content -Path $Path | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1

  if (-not $line) {
    throw "Missing $Key in $Path"
  }

  return ($line -split "=", 2)[1].Trim().Trim('"')
}

function Parse-SqlServerDatabaseUrl {
  param([Parameter(Mandatory = $true)][string]$DatabaseUrl)

  if (-not $DatabaseUrl.StartsWith("sqlserver://")) {
    throw "DATABASE_URL must use sqlserver:// for SQL Server backups."
  }

  $withoutScheme = $DatabaseUrl.Substring("sqlserver://".Length)
  $parts = $withoutScheme -split ";"
  $endpoint = $parts[0]
  $hostParts = $endpoint -split ":", 2
  $settings = @{}

  foreach ($part in $parts | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($part)) {
      continue
    }

    $keyValue = $part -split "=", 2
    if ($keyValue.Length -eq 2) {
      $settings[$keyValue[0].ToLowerInvariant()] = [System.Uri]::UnescapeDataString($keyValue[1])
    }
  }

  return @{
    Host     = $hostParts[0]
    Port     = if ($hostParts.Length -gt 1) { [int]$hostParts[1] } else { 1433 }
    User     = $settings["user"]
    Password = $settings["password"]
    Database = $settings["database"]
  }
}

function Escape-SqlIdentifier {
  param([Parameter(Mandatory = $true)][string]$Value)
  return $Value.Replace("]", "]]")
}

function Escape-SqlString {
  param([Parameter(Mandatory = $true)][string]$Value)
  return $Value.Replace("'", "''")
}

function Invoke-SqlCmdChecked {
  param(
    [Parameter(Mandatory = $true)][hashtable]$DatabaseInfo,
    [Parameter(Mandatory = $true)][string]$Query
  )

  $server = "$($DatabaseInfo.Host),$($DatabaseInfo.Port)"
  $args = @("-S", $server, "-b", "-Q", $Query)

  if ([string]::IsNullOrWhiteSpace($DatabaseInfo.User)) {
    $args = @("-S", $server, "-E", "-b", "-Q", $Query)
  } else {
    $args = @("-S", $server, "-U", $DatabaseInfo.User, "-P", $DatabaseInfo.Password, "-b", "-Q", $Query)
  }

  & sqlcmd.exe @args

  if ($LASTEXITCODE -ne 0) {
    throw "sqlcmd failed with exit code $LASTEXITCODE"
  }
}

$databaseUrl = Get-EnvValue -Path $BackendEnvPath -Key "DATABASE_URL"
$databaseInfo = Parse-SqlServerDatabaseUrl -DatabaseUrl $databaseUrl

if ([string]::IsNullOrWhiteSpace($databaseInfo.Database)) {
  throw "DATABASE_URL must include database=<name>."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $OutputRoot $timestamp
$dbBackupPath = Join-Path $backupDir "database.bak"
$apkArchivePath = Join-Path $backupDir "apks.zip"
$manifestPath = Join-Path $backupDir "manifest.json"

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$databaseName = Escape-SqlIdentifier -Value $databaseInfo.Database
$backupSqlPath = Escape-SqlString -Value $dbBackupPath
$backupQuery = "BACKUP DATABASE [$databaseName] TO DISK = N'$backupSqlPath' WITH COPY_ONLY, INIT"
Invoke-SqlCmdChecked -DatabaseInfo $databaseInfo -Query $backupQuery

if (-not (Test-Path $ApkStoragePath)) {
  throw "APK storage path not found: $ApkStoragePath"
}

Compress-Archive -Path (Join-Path $ApkStoragePath "*") -DestinationPath $apkArchivePath -Force

$manifest = [ordered]@{
  createdAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  database = @{
    engine = "sqlserver"
    host = $databaseInfo.Host
    port = $databaseInfo.Port
    name = $databaseInfo.Database
    user = $databaseInfo.User
    backupFile = $dbBackupPath
  }
  apkStorage = @{
    sourcePath = $ApkStoragePath
    archiveFile = $apkArchivePath
  }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

[ordered]@{
  backupDir = $backupDir
  databaseBackup = $dbBackupPath
  apkArchive = $apkArchivePath
  manifest = $manifestPath
} | ConvertTo-Json -Depth 4
