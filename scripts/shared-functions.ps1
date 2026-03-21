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
