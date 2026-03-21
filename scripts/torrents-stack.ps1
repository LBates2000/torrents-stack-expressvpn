<#
.SYNOPSIS
    Manage the torrents-stack-expressvpn Docker Compose stack.

.DESCRIPTION
    Wrapper script for common stack operations. Syncs configuration from .env
    before starting services so containers always boot with up-to-date config.

.PARAMETER Command
    start     Sync configs then bring the stack up (detached).
    stop      Stop and remove containers (volumes are preserved).
    restart   Stop then start.
    update    Pull latest images then restart.
    status    Show running container status.
    logs      Tail logs for all services (or a specific service).
    sync      Sync config files from .env without touching containers.

.PARAMETER Service
    Optional. Scope 'logs' to a specific service (expressvpn, flaresolverr,
    jackett, qbittorrent).

.PARAMETER Follow
    When used with 'logs', keep streaming output (default: true).

.PARAMETER VerboseAuth
    When used with 'status', prints extra authentication-check diagnostics.

.EXAMPLE
    pwsh ./scripts/torrents-stack.ps1 start
    pwsh ./scripts/torrents-stack.ps1 stop
    pwsh ./scripts/torrents-stack.ps1 restart
    pwsh ./scripts/torrents-stack.ps1 update
    pwsh ./scripts/torrents-stack.ps1 status
    pwsh ./scripts/torrents-stack.ps1 status -VerboseAuth
    pwsh ./scripts/torrents-stack.ps1 logs
    pwsh ./scripts/torrents-stack.ps1 logs -Service jackett
    pwsh ./scripts/torrents-stack.ps1 sync
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('start', 'stop', 'restart', 'update', 'status', 'logs', 'sync')]
    [string]$Command,

    [string]$Service = '',

    [bool]$Follow = $true,

    [switch]$VerboseAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import shared utility functions
. "$PSScriptRoot/shared-functions.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    <#
    .SYNOPSIS
        Sync configuration from .env to all service config files.

    .DESCRIPTION
        Invokes sync scripts for Jackett and qBittorrent in sequence.
        Each sync script applies config changes and optionally restarts
        the service if changes were detected.
    #>
    function Invoke-ConfigSync {
        Write-Host '==> Syncing configs from .env...'
        pwsh -NoProfile -File "$PSScriptRoot/sync-jackett-config.ps1" -SkipRestart
        Write-Host ''
        pwsh -NoProfile -File "$PSScriptRoot/sync-qbittorrent-config.ps1" -SkipRestart
    }

    <#
    .SYNOPSIS
        Test qBittorrent WebUI login.

    .DESCRIPTION
        Makes an HTTP POST request to qBittorrent's auth endpoint with the provided
        credentials. Returns a structured result with success status and diagnostic info.

    .PARAMETER BaseUrl
        Base URL of qBittorrent WebUI (e.g., http://localhost:8080)

    .PARAMETER Username
        qBittorrent WebUI username (typically 'admin')

    .PARAMETER Password
        qBittorrent WebUI password

    .OUTPUTS
        [pscustomobject] with properties:
          - Ok: $true if login succeeded, $false otherwise
          - Message: Human-readable result message
          - Endpoint: Target API endpoint used
          - StatusCode: HTTP status code (-1 if exception)
          - Body: Response body or error message
    #>
    function Test-QbittorrentLogin {
        param(
            [string]$BaseUrl,
            [string]$Username,
            [string]$Password
        )

        $client = New-HttpClient
        try {
            $escapedUser = [uri]::EscapeDataString($Username)
            $escapedPass = [uri]::EscapeDataString($Password)
            $payload = "username=$escapedUser&password=$escapedPass"
            $content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/x-www-form-urlencoded')
            $response = $client.PostAsync("$BaseUrl/api/v2/auth/login", $content).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $bodyTrim = $body.Trim()
            $endpoint = "$BaseUrl/api/v2/auth/login"

            if ($response.IsSuccessStatusCode -and ($bodyTrim -eq 'Ok.')) {
                return [pscustomobject]@{
                    Ok = $true
                    Message = 'qBittorrent login check passed'
                    Endpoint = $endpoint
                    StatusCode = [int]$response.StatusCode
                    Body = $bodyTrim
                }
            }

            return [pscustomobject]@{
                Ok = $false
                Message = "qBittorrent login check failed (status=$([int]$response.StatusCode), body=$bodyTrim)"
                Endpoint = $endpoint
                StatusCode = [int]$response.StatusCode
                Body = $bodyTrim
            }
        }
        catch {
            return [pscustomobject]@{
                Ok = $false
                Message = "qBittorrent login check failed: $($_.Exception.Message)"
                Endpoint = "$BaseUrl/api/v2/auth/login"
                StatusCode = -1
                Body = ''
            }
        }
        finally {
            $client.Dispose()
        }
    }

    <#
    .SYNOPSIS
        Test Jackett API key validity.

    .DESCRIPTION
        Makes an HTTP GET request to Jackett's indexer endpoint with the API key.
        Validates both connectivity and authentication. Returns structured result
        with diagnostic information.

    .PARAMETER BaseUrl
        Base URL of Jackett service (e.g., http://localhost:9117)

    .PARAMETER ApiKey
        Jackett API key

    .OUTPUTS
        [pscustomobject] with properties:
          - Ok: $true if API key is valid, $false otherwise
          - Message: Human-readable result message
          - Endpoint: Target API endpoint (with key masked as ***)
          - StatusCode: HTTP status code (-1 if exception)
          - Body: Response body excerpt or error message
    #>
    function Test-JackettApiKey {
        param(
            [string]$BaseUrl,
            [string]$ApiKey
        )

        $client = New-HttpClient
        try {
            $escapedApiKey = [uri]::EscapeDataString($ApiKey)
            $url = "$BaseUrl/api/v2.0/indexers/all/results?apikey=$escapedApiKey&Query=ubuntu"
            $response = $client.GetAsync($url).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $bodyTrim = $body.Trim()
            $safeUrl = "$BaseUrl/api/v2.0/indexers/all/results?apikey=***&Query=ubuntu"

            if ($response.IsSuccessStatusCode -and $body.Contains('"Results"')) {
                return [pscustomobject]@{
                    Ok = $true
                    Message = 'Jackett API auth check passed'
                    Endpoint = $safeUrl
                    StatusCode = [int]$response.StatusCode
                    Body = $bodyTrim
                }
            }

            return [pscustomobject]@{
                Ok = $false
                Message = "Jackett API auth check failed (status=$([int]$response.StatusCode))"
                Endpoint = $safeUrl
                StatusCode = [int]$response.StatusCode
                Body = $bodyTrim
            }
        }
        catch {
            return [pscustomobject]@{
                Ok = $false
                Message = "Jackett API auth check failed: $($_.Exception.Message)"
                Endpoint = "$BaseUrl/api/v2.0/indexers/all/results?apikey=***&Query=ubuntu"
                StatusCode = -1
                Body = ''
            }
        }
        finally {
            $client.Dispose()
        }
    }

    switch ($Command) {

        'sync' {
            Invoke-ConfigSync
        }

        'start' {
            $startTime = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-ConfigSync
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d --wait --wait-timeout 300
            $startTime.Stop()
            Write-Host "Stack startup completed in $([math]::Round($startTime.Elapsed.TotalSeconds, 2)) seconds"
        }

        'stop' {
            Write-Host '==> Stopping stack...'
            docker compose down
        }

        'restart' {
            $startTime = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host '==> Stopping stack...'
            docker compose down
            Write-Host ''
            Invoke-ConfigSync
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d --wait --wait-timeout 300
            $startTime.Stop()
            Write-Host "Stack restart completed in $([math]::Round($startTime.Elapsed.TotalSeconds, 2)) seconds"
        }

        'update' {
            $startTime = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host '==> Pulling latest images...'
            docker compose pull
            Write-Host ''
            Write-Host '==> Stopping stack...'
            docker compose down
            Write-Host ''
            Invoke-ConfigSync
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d --wait --wait-timeout 300
            $startTime.Stop()
            Write-Host "Stack update completed in $([math]::Round($startTime.Elapsed.TotalSeconds, 2)) seconds"
        }

        'status' {
            docker compose ps

            Write-Host ''
            Write-Host '==> qBittorrent Jackett plugin check...'

            $runningServices = @(docker compose ps --services --filter status=running)
            if ($runningServices -notcontains 'qbittorrent') {
                Write-Host 'qBittorrent is not running; plugin check skipped.'
            }
            else {
                $pluginCheck = docker compose exec -T qbittorrent sh -lc "if [ -s /config/qBittorrent/nova3/engines/jackett.py ] && [ -s /config/qBittorrent/nova3/engines/jackett.json ]; then echo OK; else echo MISSING; fi"
                if ($pluginCheck -contains 'OK') {
                    Write-Host 'Jackett plugin files present: /config/qBittorrent/nova3/engines/jackett.py and jackett.json'
                }
                else {
                    Write-Warning 'Jackett plugin files missing in qBittorrent container (/config/qBittorrent/nova3/engines).'
                    Write-Host 'Run: pwsh ./scripts/torrents-stack.ps1 restart'
                }
            }

            Write-Host ''
            Write-Host '==> Authentication checks...'

            $envPath = Join-Path $repoRoot '.env'
            $envMap = Get-EnvMap -Path $envPath

            if ($runningServices -contains 'qbittorrent') {
                $qbitPort = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_WEBUI_PORT' -DefaultValue '8080'
                $qbitBaseUrl = "http://localhost:$qbitPort"
                $qbitUser = 'admin'
                $qbitPassword = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT' -DefaultValue ''

                if ([string]::IsNullOrWhiteSpace($qbitPassword)) {
                    Write-Host 'qBittorrent login check skipped: QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT is not set'
                }
                else {
                    if ($VerboseAuth) {
                        Write-Host "qBittorrent auth target: $qbitBaseUrl"
                        Write-Host "qBittorrent auth username: $qbitUser"
                    }

                    $qbitResult = Test-QbittorrentLogin -BaseUrl $qbitBaseUrl -Username $qbitUser -Password $qbitPassword
                    if ($qbitResult.Ok) {
                        Write-Host $qbitResult.Message
                    }
                    else {
                        Write-Warning $qbitResult.Message
                    }

                    if ($VerboseAuth) {
                        Write-Host "qBittorrent auth endpoint: $($qbitResult.Endpoint)"
                        Write-Host "qBittorrent auth status: $($qbitResult.StatusCode)"
                        Write-Host "qBittorrent auth body: $($qbitResult.Body)"
                    }
                }
            }
            else {
                Write-Host 'qBittorrent login check skipped: service is not running'
            }

            if ($runningServices -contains 'jackett') {
                $jackettPort = Get-EnvOrDefault -EnvMap $envMap -Key 'JACKETT_PORT' -DefaultValue '9117'
                $jackettBaseUrl = "http://localhost:$jackettPort"

                $jackettApiKey = Get-EnvOrDefault -EnvMap $envMap -Key 'JACKETT_CFG_API_KEY' -DefaultValue ''
                $jackettApiKeySource = '.env (JACKETT_CFG_API_KEY)'
                if ([string]::IsNullOrWhiteSpace($jackettApiKey) -or ($jackettApiKey -eq 'null')) {
                    $jackettConfigPath = Join-Path $repoRoot 'configs/Jackett/ServerConfig.json'
                    if (Test-Path -LiteralPath $jackettConfigPath) {
                        try {
                            $jackettConfig = Get-Content -LiteralPath $jackettConfigPath -Raw | ConvertFrom-Json
                            if ($jackettConfig.APIKey) {
                                $jackettApiKey = [string]$jackettConfig.APIKey
                                $jackettApiKeySource = 'configs/Jackett/ServerConfig.json'
                            }
                        }
                        catch {
                        }
                    }
                }

                if ([string]::IsNullOrWhiteSpace($jackettApiKey) -or ($jackettApiKey -eq 'null')) {
                    Write-Host 'Jackett auth check skipped: API key not available from .env or configs/Jackett/ServerConfig.json'
                }
                else {
                    if ($VerboseAuth) {
                        Write-Host "Jackett auth target: $jackettBaseUrl"
                        Write-Host "Jackett API key source: $jackettApiKeySource"
                    }

                    $jackettResult = Test-JackettApiKey -BaseUrl $jackettBaseUrl -ApiKey $jackettApiKey
                    if ($jackettResult.Ok) {
                        Write-Host $jackettResult.Message
                    }
                    else {
                        Write-Warning $jackettResult.Message
                    }

                    if ($VerboseAuth) {
                        Write-Host "Jackett auth endpoint: $($jackettResult.Endpoint)"
                        Write-Host "Jackett auth status: $($jackettResult.StatusCode)"
                        if (-not [string]::IsNullOrWhiteSpace($jackettResult.Body)) {
                            $preview = $jackettResult.Body
                            if ($preview.Length -gt 180) {
                                $preview = $preview.Substring(0, 180) + '...'
                            }
                            Write-Host "Jackett auth body preview: $preview"
                        }
                    }
                }
            }
            else {
                Write-Host 'Jackett auth check skipped: service is not running'
            }

            Write-Host ''
            Write-Host '==> Web UIs'

            $qbittorrentUrl = "$qbitBaseUrl/"
            $jackettUrl = "http://localhost:$jackettPort/"
            $flaresolverrUrl = 'http://localhost:8191/'

            Write-Host "qBittorrent   : $qbittorrentUrl"
            Write-Host "Jackett       : $jackettUrl"
            Write-Host "Flaresolverr  : $flaresolverrUrl"

            Write-Host ''
            Write-Host '💡 Tip: Click on the URLs above in your terminal to open them in your browser'
        }

        'logs' {
            $logArgs = @('compose', 'logs')
            if ($Follow) { $logArgs += '--follow' }
            $logArgs += '--tail=100'
            if ($Service -ne '') { $logArgs += $Service }
            & docker @logArgs
        }
    }
}
finally {
    Pop-Location
}
