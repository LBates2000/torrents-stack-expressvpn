<#
.SYNOPSIS
    Shared utility functions used across all stack management scripts.

.DESCRIPTION
    This module provides common functions for environment parsing, HTTP operations,
    and INI file manipulation. Used by torrents-stack.ps1, sync-qbittorrent-config.ps1,
    and sync-jackett-config.ps1 to reduce code duplication.
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Parse .env file into a hashtable.

.DESCRIPTION
    Reads a .env file (or any key=value file) and returns a hashtable of
    key-value pairs. Ignores blank lines and comments (lines starting with #).

.PARAMETER Path
    Path to the .env file. If the file doesn't exist, returns an empty hashtable.

.EXAMPLE
    $envMap = Get-EnvMap -Path './.env'
    $value = $envMap['QBITTORRENT_WEBUI_PORT']
#>
function Get-EnvMap {
    param(
        [string]$Path
    )

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1)
        $map[$key] = $value
    }

    return $map
}

<#
.SYNOPSIS
    Get environment variable with fallback to default value.

.DESCRIPTION
    Safely retrieves a value from an environment map. If the key doesn't exist
    or the value is empty/whitespace, returns the default value.

.PARAMETER EnvMap
    Hashtable of environment variables (from Get-EnvMap).

.PARAMETER Key
    The key to look up.

.PARAMETER DefaultValue
    The value to return if key is not found or is empty.

.EXAMPLE
    $port = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_WEBUI_PORT' -DefaultValue '8080'
#>
function Get-EnvOrDefault {
    param(
        [hashtable]$EnvMap,
        [string]$Key,
        [string]$DefaultValue
    )

    if ($null -eq $EnvMap) {
        return $DefaultValue
    }

    if ($EnvMap.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($EnvMap[$Key])) {
        return [string]$EnvMap[$Key]
    }

    return $DefaultValue
}

<#
.SYNOPSIS
    Create and configure an HTTP client for API requests.

.DESCRIPTION
    Initializes a System.Net.Http.HttpClient with a standard timeout (12 seconds).
    Used by authentication check functions. Caller is responsible for disposing.

.PARAMETER TimeoutSeconds
    Timeout in seconds. Default: 12.

.OUTPUTS
    [System.Net.Http.HttpClient]

.EXAMPLE
    $client = New-HttpClient -TimeoutSeconds 12
    try {
        $response = $client.PostAsync("http://...", $content).GetAwaiter().GetResult()
    } finally {
        $client.Dispose()
    }
#>
function New-HttpClient {
    param(
        [int]$TimeoutSeconds = 12
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    return $client
}

# --- Path and Directory Utilities (shared) ---
function Convert-PathPrefix {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return '/downloads'
    }
    $trimmed = $PathValue.Trim()
    while ($trimmed.Length -gt 1 -and $trimmed.EndsWith('/')) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }
    return $trimmed
}

function Resolve-HostPath {
    param(
        [string]$RepoRoot,
        [string]$ConfiguredPath,
        [string]$DefaultRelativePath
    )
    $pathValue = $ConfiguredPath
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
        $pathValue = $DefaultRelativePath
    }
    if ([System.IO.Path]::IsPathRooted($pathValue)) {
        return [System.IO.Path]::GetFullPath($pathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $pathValue))
}

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function New-FileIfMissing {
    param(
        [string]$Path,
        [string]$DefaultContent = ''
    )
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-DirectoryIfMissing -Path $parentPath
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.File]::WriteAllText($Path, $DefaultContent)
    }
}

# --- qBittorrent Login Check (shared) ---
function Test-QbittorrentLogin {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,
        [Parameter(Mandatory=$true)]
        [string]$Username,
        [Parameter(Mandatory=$true)]
        [Object]$Auth
    )
    $client = New-HttpClient
    try {
        $securePassword = $null
        if ($Auth -is [System.Management.Automation.PSCredential]) {
            $securePassword = $Auth.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
        } elseif ($Auth -is [System.Security.SecureString]) {
            $securePassword = $Auth
        } else {
            throw "Auth parameter must be a SecureString or PSCredential."
        }
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
        $escapedUser = [uri]::EscapeDataString($Username)
        $escapedPass = [uri]::EscapeDataString($plainPassword)
        $payload = "username=$escapedUser&password=$escapedPass"
        $content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/x-www-form-urlencoded')
        $response = $client.PostAsync("$BaseUrl/api/v2/auth/login", $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $bodyTrim = $body.Trim()
        $endpoint = "$BaseUrl/api/v2/auth/login"
        if ($response.IsSuccessStatusCode -and ($bodyTrim -eq 'Ok.')) {
            return [pscustomobject]@{
                Ok        = $true
                Message   = 'qBittorrent login check passed'
                Endpoint  = $endpoint
                StatusCode= [int]$response.StatusCode
                Body      = $bodyTrim
            }
        }
        return [pscustomobject]@{
            Ok        = $false
            Message   = "qBittorrent login check failed (status=$([int]$response.StatusCode), body=$bodyTrim)"
            Endpoint  = $endpoint
            StatusCode= [int]$response.StatusCode
            Body      = $bodyTrim
        }
    }
    catch {
        return [pscustomobject]@{
            Ok        = $false
            Message   = "qBittorrent login check failed: $($_.Exception.Message)"
            Endpoint  = "$BaseUrl/api/v2/auth/login"
            StatusCode= -1
            Body      = ''
        }
    }
    finally {
        $client.Dispose()
    }
}

<#+
.SYNOPSIS
    Checks for the presence of Jackett plugin files in the qBittorrent container.
.DESCRIPTION
    Verifies that both jackett.py and jackett.json exist in /config/qBittorrent/nova3/engines inside the qbittorrent container.
    Prints status and returns $true if present, $false otherwise.
#>
function Test-QbittorrentJackettPlugin {
    $runningServices = @(docker compose ps --services --filter status=running)
    if ($runningServices -notcontains 'qbittorrent') {
        Write-Host 'qBittorrent is not running; plugin check skipped.'
        return $null
    }
    $pluginCheck = docker compose exec -T qbittorrent sh -lc "if [ -s /config/qBittorrent/nova3/engines/jackett.py ] && [ -s /config/qBittorrent/nova3/engines/jackett.json ]; then echo OK; else echo MISSING; fi"
    if ($pluginCheck -contains 'OK') {
        Write-Host 'Jackett plugin files present: /config/qBittorrent/nova3/engines/jackett.py and jackett.json'
        return $true
    } else {
        Write-Warning 'Jackett plugin files missing in qBittorrent container (/config/qBittorrent/nova3/engines).'
        Write-Host 'Run: pwsh ./scripts/torrents-stack.ps1 restart'
        return $false
    }
}
