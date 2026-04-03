# Restore configs and important data from backup
param(
    [Parameter(Mandatory)]
    [string]$Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/shared-functions.ps1"

$stackContext = Get-StackContext -ScriptRoot $PSScriptRoot

Expand-Archive -Path $Archive -DestinationPath $stackContext.RepoRoot -Force
Write-Host "[Restore] Restored from: $Archive" -ForegroundColor Green
