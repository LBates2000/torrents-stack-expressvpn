# Validate stack configuration inputs.

[CmdletBinding()]
param(
    [switch]$AllowExampleFallback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/shared-functions.ps1"

function Test-JsonObjectValue {
    param(
        [string]$Key,
        [string]$RawValue,
        [ref]$Errors
    )

    if ([string]::IsNullOrWhiteSpace($RawValue)) {
        return
    }

    try {
        $parsed = $RawValue | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -isnot [System.Collections.IDictionary] -and $parsed -isnot [pscustomobject]) {
            $Errors.Value += "$Key must be a JSON object when provided."
        }
    } catch {
        $Errors.Value += "$Key contains invalid JSON: $($_.Exception.Message)"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot '.env'
$exampleEnvPath = Join-Path $repoRoot '.env.example'
$envSourcePath = $envPath

if (-not (Test-Path -LiteralPath $envSourcePath)) {
    if ($AllowExampleFallback -and (Test-Path -LiteralPath $exampleEnvPath)) {
        $envSourcePath = $exampleEnvPath
    } else {
        Write-Host '[Config Validation] ERRORS FOUND:' -ForegroundColor Red
        Write-Host '.env file is missing. Copy .env.example and set required values.' -ForegroundColor Red
        exit 1
    }
}

$envMap = Get-EnvMap -Path $envSourcePath
$errors = @()

$required = @(
    'EXPRESSVPN_ACTIVATION_CODE',
    'EXPRESSVPN_REGION'
)

foreach ($key in $required) {
    if (-not $envMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envMap[$key])) {
        $errors += "$([System.IO.Path]::GetFileName($envSourcePath)) missing required key: $key"
    }
}

Test-JsonObjectValue -Key 'QBITTORRENT_CFG_CATEGORIES_JSON' -RawValue $envMap['QBITTORRENT_CFG_CATEGORIES_JSON'] -Errors ([ref]$errors)
Test-JsonObjectValue -Key 'QBITTORRENT_CFG_WATCHED_FOLDERS_JSON' -RawValue $envMap['QBITTORRENT_CFG_WATCHED_FOLDERS_JSON'] -Errors ([ref]$errors)

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'docker-compose.yml'))) {
    $errors += 'docker-compose.yml is missing from the repository root.'
}

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/bootstrap-qbittorrent-jackett.sh'))) {
    $errors += 'bootstrap-qbittorrent-jackett.sh is missing from scripts/.'
}

if ($errors.Count -eq 0) {
    Write-Host "[Config Validation] Required repository inputs are valid using $([System.IO.Path]::GetFileName($envSourcePath))." -ForegroundColor Green
    exit 0
}

Write-Host '[Config Validation] ERRORS FOUND:' -ForegroundColor Red
$errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
exit 1
