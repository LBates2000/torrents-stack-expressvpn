# Backup configs and important data

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/shared-functions.ps1"

$stackContext = Get-StackContext -ScriptRoot $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $stackContext.RepoRoot 'backups'
New-DirectoryIfMissing -Path $backupDir
$archive = Join-Path $backupDir "stack-backup-$timestamp.zip"

$paths = @(
    $stackContext.ConfigsRoot,
    $stackContext.DownloadsRoot
)
Compress-Archive -Path $paths -DestinationPath $archive
Write-Host "[Backup] Created: $archive" -ForegroundColor Green
