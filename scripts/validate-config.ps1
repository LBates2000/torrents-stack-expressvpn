# Validate stack configuration files

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/shared-functions.ps1"

$stackContext = Get-StackContext -ScriptRoot $PSScriptRoot
$errors = @()

if (-not (Test-Path -LiteralPath $stackContext.EnvPath)) {
    $errors += ".env file is missing. Copy .env.example and set required values."
} else {
    $required = @('EXPRESSVPN_ACTIVATION_CODE','EXPRESSVPN_REGION')
    foreach ($key in $required) {
        if (-not $stackContext.EnvMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($stackContext.EnvMap[$key])) {
            $errors += ".env missing required key: $key"
        }
    }
}

$qbConf = Join-Path $stackContext.ConfigsRoot 'qBittorrent/qBittorrent.conf'
if (-not (Test-Path -LiteralPath $qbConf)) {
    $errors += "qBittorrent.conf missing in $($stackContext.ConfigsRoot)/qBittorrent/"
}

$jackettConf = Join-Path $stackContext.ConfigsRoot 'Jackett/ServerConfig.json'
if (-not (Test-Path -LiteralPath $jackettConf)) {
    $errors += "Jackett ServerConfig.json missing in $($stackContext.ConfigsRoot)/Jackett/"
}

if ($errors.Count -eq 0) {
    Write-Host "[Config Validation] All required config files and keys are present." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[Config Validation] ERRORS FOUND:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
