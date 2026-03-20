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

.EXAMPLE
    pwsh ./scripts/torrents-stack.ps1 start
    pwsh ./scripts/torrents-stack.ps1 stop
    pwsh ./scripts/torrents-stack.ps1 restart
    pwsh ./scripts/torrents-stack.ps1 update
    pwsh ./scripts/torrents-stack.ps1 status
    pwsh ./scripts/torrents-stack.ps1 logs
    pwsh ./scripts/torrents-stack.ps1 logs -Service jackett
    pwsh ./scripts/torrents-stack.ps1 sync
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('start', 'stop', 'restart', 'update', 'status', 'logs', 'sync')]
    [string]$Command,

    [string]$Service = '',

    [bool]$Follow = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    switch ($Command) {

        'sync' {
            Write-Host '==> Syncing Jackett config...'
            pwsh -NoProfile -File "$PSScriptRoot/sync-jackett-config.ps1" -SkipRestart
            Write-Host ''
            Write-Host '==> Syncing qBittorrent config...'
            pwsh -NoProfile -File "$PSScriptRoot/sync-qbittorrent-config.ps1" -SkipRestart
        }

        'start' {
            Write-Host '==> Syncing configs from .env...'
            pwsh -NoProfile -File "$PSScriptRoot/sync-jackett-config.ps1" -SkipRestart
            Write-Host ''
            pwsh -NoProfile -File "$PSScriptRoot/sync-qbittorrent-config.ps1" -SkipRestart
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d
        }

        'stop' {
            Write-Host '==> Stopping stack...'
            docker compose down
        }

        'restart' {
            Write-Host '==> Stopping stack...'
            docker compose down
            Write-Host ''
            Write-Host '==> Syncing configs from .env...'
            pwsh -NoProfile -File "$PSScriptRoot/sync-jackett-config.ps1" -SkipRestart
            Write-Host ''
            pwsh -NoProfile -File "$PSScriptRoot/sync-qbittorrent-config.ps1" -SkipRestart
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d
        }

        'update' {
            Write-Host '==> Pulling latest images...'
            docker compose pull
            Write-Host ''
            Write-Host '==> Stopping stack...'
            docker compose down
            Write-Host ''
            Write-Host '==> Syncing configs from .env...'
            pwsh -NoProfile -File "$PSScriptRoot/sync-jackett-config.ps1" -SkipRestart
            Write-Host ''
            pwsh -NoProfile -File "$PSScriptRoot/sync-qbittorrent-config.ps1" -SkipRestart
            Write-Host ''
            Write-Host '==> Starting stack...'
            docker compose up -d
        }

        'status' {
            docker compose ps
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
