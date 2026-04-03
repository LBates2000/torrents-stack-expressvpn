<#
.SYNOPSIS
    Remove orphaned Docker resources and old log files.
.DESCRIPTION
    Cleans up unused Docker containers, volumes, networks, and log files older than 14 days.
.PARAMETER WhatIf
    If specified, shows what would be removed but does not actually delete anything.
.EXAMPLE
    pwsh ./scripts/cleanup-orphans.ps1 -WhatIf
#>
param([switch]$WhatIf)

Write-Host '[Cleanup] Removing orphaned Docker containers, volumes, and networks...' -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host '[Cleanup] Would run: docker container prune -f' -ForegroundColor Yellow
    Write-Host '[Cleanup] Would run: docker volume prune -f' -ForegroundColor Yellow
    Write-Host '[Cleanup] Would run: docker network prune -f' -ForegroundColor Yellow
} else {
    docker container prune -f
    docker volume prune -f
    docker network prune -f
}

Write-Host '[Cleanup] Removing log files older than 14 days in downloads/logs and configs/qBittorrent/logs...'
$logDirs = @(
    "$PSScriptRoot/../downloads/logs",
    "$PSScriptRoot/../configs/qBittorrent/logs"
)
foreach ($dir in $logDirs) {
    if (Test-Path $dir) {
        $oldLogs = Get-ChildItem $dir -File -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) }
        if ($WhatIf) {
            Write-Host "[Cleanup] Would remove: $($oldLogs.FullName -join ', ')" -ForegroundColor Yellow
        } else {
            $oldLogs | Remove-Item -Force
        }
    }
}
Write-Host '[Cleanup] Done.' -ForegroundColor Green
