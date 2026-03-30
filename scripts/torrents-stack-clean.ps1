<#!
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
    Optional. Scope 'logs' to a specific service (expressvpn, flaresolverr, etc.)
#>


# --- Main script logic ---
try {
    switch ($Command) {
        'sync' {
            Invoke-ConfigSync
        }
        'start' {
            Sync-Configs
            Get-StackImages
            Start-Stack -Action 'startup'
        }
        'stop' {
            Write-Host '==> Stopping stack...'
            docker compose down
        }
        'restart' {
            Stop-Stack
            Sync-Configs
            Get-StackImages
            Start-Stack -Action 'restart'
        }
        'update' {
            Get-StackImages
            Stop-Stack
            Sync-Configs
            Start-Stack -Action 'update'
        }
        'status' {
            docker compose ps
            Write-Host ''
            Write-Host ''
            Write-Host '==> qBittorrent Jackett plugin check...'
            . "$PSScriptRoot/shared-functions.ps1"
            Test-QbittorrentJackettPlugin | Out-Null
            Write-Host ''
            Write-Host ''
            Write-Host '==> Authentication checks...'
            $envPath = Join-Path $repoRoot '.env'
            $envMap = Get-EnvMap -Path $envPath
            $flaresolverrPort = Get-EnvOrDefault -EnvMap $envMap -Key 'FLARESOLVERR_PORT' -DefaultValue '8191'
            $jackettPort = Get-EnvOrDefault -EnvMap $envMap -Key 'JACKETT_PORT' -DefaultValue '9117'
            $qbitPort = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_WEBUI_PORT' -DefaultValue '8080'
            $flaresolverrUrl = "http://localhost:$flaresolverrPort/"
            $jackettUrl = "http://localhost:$jackettPort/"
            $qbittorrentUrl = "http://localhost:$qbitPort/"
            $qbitBaseUrl = "http://localhost:$qbitPort"
            $jackettBaseUrl = "http://localhost:$jackettPort"
            if ($runningServices -contains 'qbittorrent') {
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
                    $secureQbitPassword = $qbitPassword | ConvertTo-SecureString -AsPlainText -Force
                    $qbitResult = Test-QbittorrentLogin -BaseUrl $qbitBaseUrl -Username $qbitUser -Auth $secureQbitPassword
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
            Write-Host ''
            Write-Host '==> Web UIs'
            Write-Host "Flaresolverr  : $flaresolverrUrl"
            Write-Host "Jackett       : $jackettUrl"
            Write-Host "qBittorrent   : $qbittorrentUrl"
            Write-Host ''
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
