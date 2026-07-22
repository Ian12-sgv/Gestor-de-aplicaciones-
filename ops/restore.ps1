param(
  [Parameter(Mandatory = $true)][string]$BackupDir,
  [string]$BackendEnvPath = "D:\google play blumer\back\.env",
  [string]$ApkStoragePath = "D:\google play blumer\back\storage\apks"
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
    throw "DATABASE_URL must use sqlserver:// for SQL Server restore."
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

if (-not (Test-Path $BackupDir)) {
  throw "Backup directory not found: $BackupDir"
}

$dbBackupPath = Join-Path $BackupDir "database.bak"
$apkArchivePath = Join-Path $BackupDir "apks.zip"

if (-not (Test-Path $dbBackupPath)) {
  throw "Missing database backup: $dbBackupPath"
}

if (-not (Test-Path $apkArchivePath)) {
  throw "Missing APK archive: $apkArchivePath"
}

$databaseUrl = Get-EnvValue -Path $BackendEnvPath -Key "DATABASE_URL"
$databaseInfo = Parse-SqlServerDatabaseUrl -DatabaseUrl $databaseUrl

if ([string]::IsNullOrWhiteSpace($databaseInfo.Database)) {
  throw "DATABASE_URL must include database=<name>."
}

$databaseName = Escape-SqlIdentifier -Value $databaseInfo.Database
$backupSqlPath = Escape-SqlString -Value (Resolve-Path $dbBackupPath).Path
$restoreQuery = @"
ALTER DATABASE [$databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$databaseName] FROM DISK = N'$backupSqlPath' WITH REPLACE;
ALTER DATABASE [$databaseName] SET MULTI_USER;
"@

Invoke-SqlCmdChecked -DatabaseInfo $databaseInfo -Query $restoreQuery

New-Item -ItemType Directory -Force -Path $ApkStoragePath | Out-Null
Expand-Archive -Path $apkArchivePath -DestinationPath $ApkStoragePath -Force

[ordered]@{
  restoredFrom = $BackupDir
  databaseBackup = $dbBackupPath
  apkArchive = $apkArchivePath
  apkStoragePath = $ApkStoragePath
  warning = "Se recomienda restaurar sobre una base controlada para evitar duplicados o perdida accidental de datos."
} | ConvertTo-Json -Depth 4
