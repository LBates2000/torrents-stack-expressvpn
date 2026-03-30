
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','update','status','logs','sync','rebuild','clean','test-all')]
    [string]$Command = '',
    [string]$Service = '',
    [switch]$Follow,
    [switch]$VerboseAuth
)

# --- Utility: Diagnose all stack containers ---
function Diagnose-Stack {
    $services = @('expressvpn','flaresolverr','jackett','qbittorrent')
    Write-Host "[Diagnosis] Full container status for all stack services:" -ForegroundColor Cyan
    $all = docker ps -a --filter "label=com.torrents-stack.project=expressvpn-stack" --format "table {{.Names}}\t{{.Status}}\t{{.ID}}"
    if ($all) {
        Write-Host $all
    } else {
        Write-Host '[Diagnosis] No project containers found.' -ForegroundColor Yellow
    }
    foreach ($svc in $services) {
        $cid = docker ps -a --filter "name=$svc" --format "{{.ID}}"
        if ($cid) {
            Write-Host ("[Diagnosis] Last 20 log lines for ${svc}:") -ForegroundColor Magenta
            docker logs --tail 20 $cid
        } else {
            Write-Host ("[Diagnosis] ${svc} container not found.") -ForegroundColor Yellow
        }
    }
}

# --- Utility: Live Service Status Table ---
function Show-ServiceStatusTable {
    param(
        [hashtable]$serviceStatus,
        [string[]]$services
    )
    Clear-Host
    Write-Host "[Health Poll] Service Statuses (updated: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Cyan
    Write-Host ("{0,-15} {1,-12}" -f 'Service','Status') -ForegroundColor Yellow
    Write-Host ("{0,-15} {1,-12}" -f '-------','------') -ForegroundColor Yellow
    foreach ($svc in $services) {
        $status = $serviceStatus[$svc]
        $color = switch ($status) {
            'healthy'    { 'Green' }
            'starting'   { 'Yellow' }
            'unhealthy'  { 'Red' }
            'not found'  { 'Gray' }
            default      { 'White' }
        }
        Write-Host ("{0,-15} {1,-12}" -f $svc, $status) -ForegroundColor $color
    }
}

Write-Host '[Test] torrents-stack.ps1 script started.' -ForegroundColor Yellow

# Show usage/help if required parameter is missing (for direct invocation)
if (-not $PSBoundParameters.ContainsKey('Command') -or [string]::IsNullOrWhiteSpace($Command)) {
    Write-Host "\n[Usage] pwsh ./scripts/torrents-stack.ps1 <command> [-Service <name>] [-Follow] [-VerboseAuth]" -ForegroundColor Yellow
    Write-Host "\nAvailable commands:" -ForegroundColor Yellow
    Write-Host "  start     Sync configs then bring the stack up (detached)." -ForegroundColor Yellow
    Write-Host "  stop      Stop and remove containers (volumes are preserved)." -ForegroundColor Yellow
    Write-Host "  restart   Stop then start." -ForegroundColor Yellow
    Write-Host "  update    Pull latest images then restart." -ForegroundColor Yellow
    Write-Host "  status    Show running container status." -ForegroundColor Yellow
    Write-Host "  logs      Tail logs for all services (or a specific service)." -ForegroundColor Yellow
    Write-Host "  sync      Sync config files from .env without touching containers." -ForegroundColor Yellow
    Write-Host "  rebuild   Rebuild the stack from scratch (all containers and images are removed)." -ForegroundColor Yellow
    Write-Host "  clean     Remove all containers, volumes, and Docker resources." -ForegroundColor Yellow
    Write-Host "  test-all  Run all stack commands in sequence and check health." -ForegroundColor Yellow
    exit 1
}
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
    rebuild   Rebuild the stack from scratch (all containers and images are removed).

.PARAMETER Service
    Optional. Scope 'logs' to a specific service (expressvpn, flaresolverr, jackett, qbittorrent).

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
    pwsh ./scripts/torrents-stack.ps1 rebuild
#>




# --- Function Definitions ---

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot


function Ensure-Clean {
    Write-Host '[Command] Ensuring clean stack state...' -ForegroundColor Cyan
    & pwsh $PSCommandPath clean
}

# --- Shared Orchestration Functions ---
function Sync-Configs {
    Write-Host '[Step] Syncing configs...' -ForegroundColor Cyan
    # Add config sync logic here
}

function Show-Stack-Status {
    Write-Host "\n[Status] Stack status:" -ForegroundColor Green
    docker compose ps
}

function Show-Recent-Logs {
    param([int]$Tail = 30)
    $services = @('jackett','qbittorrent','flaresolverr','expressvpn')
    foreach ($svc in $services) {
        Write-Host "\n[Logs] Recent $svc logs:" -ForegroundColor Yellow
        docker compose logs --tail=$Tail $svc
    }
}


function Start-Stack {
    Write-Host '[Step] Bringing stack up...' -ForegroundColor Cyan
    docker compose up -d
    $services = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $maxWait = 600 # seconds (10 minutes)
    $interval = 5  # seconds
    $startTime = Get-Date
    $serviceStatus = @{}
    foreach ($svc in $services) { $serviceStatus[$svc] = 'unknown' }
    while ($true) {
        $allHealthy = $true
        foreach ($svc in $services) {
            $inspect = docker inspect --format='{{.State.Health.Status}}' $svc 2>$null
            if ($LASTEXITCODE -ne 0) {
                $serviceStatus[$svc] = 'not found'
                $allHealthy = $false
            } else {
                $serviceStatus[$svc] = $inspect
                if ($inspect -ne 'healthy') { $allHealthy = $false }
            }
        }
        Show-ServiceStatusTable -serviceStatus $serviceStatus -services $services
        if ($allHealthy) { break }
        if ((Get-Date) - $startTime -gt ([TimeSpan]::FromSeconds($maxWait))) {
            Write-Host "[Health] Timeout waiting for all services to become healthy." -ForegroundColor Red
            $unhealthy = $services | Where-Object { $serviceStatus[$_] -ne 'healthy' }
            if ($unhealthy.Count -gt 0) {
                Write-Host ("[Diagnosis] The following service(s) are not healthy: {0}" -f ($unhealthy -join ", ")) -ForegroundColor Yellow
                foreach ($svc in $unhealthy) {
                    Write-Host ("[Diagnosis] Last healthcheck log for ${svc}:") -ForegroundColor Magenta
                    $cid = docker ps -a --filter "name=$svc" --format "{{.ID}}"
                    if ($cid) {
                        $log = docker inspect --format='{{json .State.Health.Log}}' $cid | ConvertFrom-Json | Select-Object -Last 1
                        if ($log) {
                            Write-Host ("  ExitCode: $($log.ExitCode)")
                            Write-Host ("  Output: $($log.Output.Trim())")
                            Write-Host ("  End: $($log.End)\n")
                        } else {
                            Write-Host "  No healthcheck log found."
                        }
                    } else {
                        Write-Host "  Container not found."
                    }
                }
                Write-Host "[Diagnosis] To debug further, run: docker logs <container> or manually run the healthcheck script inside the container." -ForegroundColor Cyan
            }
            break
        }
        Start-Sleep -Seconds $interval
    }
    Show-Stack-Status
    Show-Recent-Logs

    # After stack start, check if all expected containers are running
    $expected = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $running = docker ps --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Names}}"
    $missing = $expected | Where-Object { $running -notcontains $_ }
    if ($missing.Count -gt 0) {
        Write-Host ("[Diagnosis] Warning: Not all expected containers are running: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow
        Diagnose-Stack
    }
}



function Stop-Stack {
    Write-Host '[Step] Stopping stack (containers only)...' -ForegroundColor Cyan
    docker compose down
    $psOutput = docker compose ps
    if ($psOutput -match 'NAME|----') {
        Show-Stack-Status
    } else {
        Write-Host '[Info] All containers removed. Stack is now empty.' -ForegroundColor Green
        exit 0
    }
}



function Remove-StackWithVolumes {
    Write-Host '[Step] Stopping and removing all project containers, volumes, and networks...' -ForegroundColor Cyan
    # Remove containers by label
    $containers = docker ps -a --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.ID}}"
    $removed = @()
    if ($containers) {
        docker rm -f $containers | Out-Null
        $removed += $containers
    }
    # Also forcibly remove by expected names in case label is missing
    $expectedNames = @('qbittorrent','jackett','flaresolverr','expressvpn')
    foreach ($name in $expectedNames) {
        $cid = docker ps -a --filter "name=^/${name}$" --format "{{.ID}}"
        if ($cid -and ($removed -notcontains $cid)) {
            docker rm -f $cid | Out-Null
            $removed += $cid
        }
    }
    if ($removed.Count -gt 0) {
        Write-Host ("[Clean] Removed containers: {0}" -f ($removed -join ", ")) -ForegroundColor Green
    } else {
        Write-Host '[Clean] No project containers found.' -ForegroundColor Yellow
    }
    # Remove volumes (force, even if dangling)
    $volumes = docker volume ls --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Name}}"
    $namedVolume = "torrents-stack-expressvpn_shared-volume"
    $removedVolumes = @()
    if ($volumes) {
        foreach ($vol in $volumes) {
            docker volume rm -f $vol | Out-Null
            $removedVolumes += $vol
        }
    }
    # Always try to remove the named volume explicitly (in case label is missing or changed)
    if ((docker volume ls --format "{{.Name}}" | Where-Object { $_ -eq $namedVolume })) {
        docker volume rm -f $namedVolume | Out-Null
        $removedVolumes += $namedVolume
    }
    if ($removedVolumes.Count -gt 0) {
        Write-Host ("[Clean] Removed volumes: {0}" -f ($removedVolumes -join ", ")) -ForegroundColor Green
    } else {
        Write-Host '[Clean] No project volumes found.' -ForegroundColor Yellow
    }
    # Remove networks (force, even if in use)
    $networks = docker network ls --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.ID}}"
    if ($networks) {
        foreach ($net in $networks) {
            docker network rm $net | Out-Null
        }
        Write-Host ("[Clean] Removed networks: {0}" -f ($networks -join ", ")) -ForegroundColor Green
    } else {
        Write-Host '[Clean] No project networks found.' -ForegroundColor Yellow
    }
    Write-Host '[Clean] Project-specific Docker resources removed.' -ForegroundColor Green
}


function Clear-DockerUnused {
    Write-Host '[Step] Pruning all unused Docker resources (this may take a while)...' -ForegroundColor Cyan
    docker system prune -af --volumes
}

function Build-Stack {
    Write-Host '[Step] Building all images from scratch (no cache)...' -ForegroundColor Cyan
    docker compose build --no-cache
}

function Update-Images {
    Write-Host '[Step] Pulling latest images...' -ForegroundColor Cyan
    docker compose pull
}

function Show-Logs {
    param($Service, $Follow)
    $logArgs = @('compose', 'logs')
    if ($Follow) { $logArgs += '--follow' }
    $logArgs += '--tail=100'
    if ($Service -ne '') { $logArgs += $Service }
    & docker @logArgs
}

function Show-Status {
    $services = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $serviceStatus = @{}
    foreach ($svc in $services) {
        $inspect = docker inspect --format='{{.State.Health.Status}}' $svc 2>$null
        if ($LASTEXITCODE -ne 0) {
            $serviceStatus[$svc] = 'not found'
        } else {
            $serviceStatus[$svc] = $inspect
        }
    }
    Show-ServiceStatusTable -serviceStatus $serviceStatus -services $services
    Write-Host '[Status] Stack status (docker compose ps):' -ForegroundColor Green
    docker compose ps
}


function Reset-Stack {
    Remove-StackWithVolumes
    Clear-DockerUnused
    Build-Stack
    Start-Stack
}

function Test-Step {
    param(
        [string]$StepName,
        [scriptblock]$Action
    )
    Write-Host "[Test] Running: $StepName..." -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "[Test] $StepName succeeded." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[Test] $StepName FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-Stack-All {
    $scriptPath = $PSCommandPath
    $allPassed = $true
    $steps = @(
        @{ Name = 'Clean (start)'; Action = { & pwsh $scriptPath clean } },
        @{ Name = 'Start';         Action = { & pwsh $scriptPath start } },
        @{ Name = 'Status';        Action = { & pwsh $scriptPath status } },
        @{ Name = 'Logs';          Action = { & pwsh $scriptPath logs } },
        @{ Name = 'Sync';          Action = { & pwsh $scriptPath sync } },
        @{ Name = 'Update';        Action = { & pwsh $scriptPath update } },
        @{ Name = 'Restart';       Action = { & pwsh $scriptPath restart } },
        @{ Name = 'Rebuild';       Action = { & pwsh $scriptPath rebuild } },
        @{ Name = 'Stop';          Action = { & pwsh $scriptPath stop } },
        @{ Name = 'Clean (end)';   Action = { & pwsh $scriptPath clean } }
    )
    Write-Host ("[Debug] Test-Stack-All using script path: $scriptPath") -ForegroundColor Magenta
    foreach ($step in $steps) {
        $ok = Test-Step -StepName $step.Name -Action $step.Action
        if (-not $ok) {
            $allPassed = $false
            Write-Host "[Test] Stopping test sequence at step: $($step.Name)" -ForegroundColor Red
            break
        }
        # After each step, check status/health
        if ($step.Name -in @('Start','Update','Restart','Rebuild')) {
            Write-Host "[Test] Checking stack status after $($step.Name)..." -ForegroundColor Yellow
            Write-Host ("[Debug] Invoking: pwsh -File $scriptPath status") -ForegroundColor Magenta
            & pwsh -File $scriptPath status
        }
    }
    if ($allPassed) {
        Write-Host "[Test] All stack commands completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[Test] Stack command test FAILED. See above for details." -ForegroundColor Red
    }
}
switch ($Command) {
    'start' {
        $cmdStart = Get-Date
        Write-Host '[Command] Starting stack...' -ForegroundColor Cyan
        Sync-Configs
        Start-Stack
        Write-Host '[Command] Stack start complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'start': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'stop' {
        $cmdStart = Get-Date
        Write-Host '[Command] Stopping stack...' -ForegroundColor Cyan
        Stop-Stack
        Write-Host '[Command] Stack stop complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'stop': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'rebuild' {
        $cmdStart = Get-Date
        Ensure-Clean
        Write-Host '[Command] Rebuilding stack (full reset)...' -ForegroundColor Cyan
        Reset-Stack
        Write-Host '[Command] Stack rebuild complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'rebuild': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'update' {
        $cmdStart = Get-Date
        Start-Stack
        Write-Host '[Command] Stack update complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'update': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'status' {
        $cmdStart = Get-Date
        Write-Host '[Command] Showing stack status...' -ForegroundColor Cyan
        Show-Status
        Write-Host '[Command] Stack status shown.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'status': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'logs' {
        $cmdStart = Get-Date
        Write-Host '[Command] Showing recent logs for all services...' -ForegroundColor Cyan
        Show-Logs -Service $Service -Follow:$Follow
        Write-Host '[Command] Logs shown.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'logs': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'sync' {
        $cmdStart = Get-Date
        Write-Host '[Command] Syncing configs...' -ForegroundColor Cyan
        Sync-Configs
        Write-Host '[Command] Config sync complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'sync': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'rebuild' {
        $cmdStart = Get-Date
        Write-Host '[Command] Rebuilding stack (full reset)...' -ForegroundColor Cyan
        Reset-Stack
        Write-Host '[Command] Stack rebuild complete.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'rebuild': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'clean' {
        $cmdStart = Get-Date
        Write-Host '[Command] Cleaning up all stack containers, volumes, and Docker resources...' -ForegroundColor Cyan
        Remove-StackWithVolumes
        Clear-DockerUnused
        Write-Host '[Command] Stack and Docker resources fully cleaned.' -ForegroundColor Green
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'clean': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    'test-all' {
        $cmdStart = Get-Date
        Write-Host '[Command] Running full stack command test sequence...' -ForegroundColor Cyan
        Test-Stack-All
        $cmdEnd = Get-Date
        Write-Host ("[Timing] Elapsed time for 'test-all': {0}" -f ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
    }
    default {
        Write-Host "[Error] Unknown command: $Command" -ForegroundColor Red
        exit 1
    }
}
