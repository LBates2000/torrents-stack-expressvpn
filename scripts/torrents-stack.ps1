param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','update','status','logs','sync','rebuild','clean','test-all','preflight','report')]
    [string]$Command = '',
    [string]$Service = '',
    [string]$OutputPath = '',
    [switch]$Follow,
    [switch]$VerboseAuth,
    [switch]$DebugOutput,
    [ValidateSet('off','auto','always')]
    [string]$ExternalLogMode = 'off',
    [ValidateRange(0, 365)]
    [int]$ExternalLogRetentionDays = 14
)

# Dot-source shared functions for dynamic table and utilities
. "$PSScriptRoot/shared-functions.ps1"

$CommandDescriptions = [ordered]@{
    start   = 'Sync configs then bring the stack up (detached).'
    stop    = 'Stop and remove containers (volumes are preserved).'
    restart = 'Stop then start.'
    update  = 'Pull latest images then restart.'
    status  = 'Show running container status, plugin check, and optional auth diagnostics.'
    logs    = 'Tail logs for all services (or a specific service).'
    sync    = 'Sync config files from .env without touching containers.'
    rebuild = 'Rebuild the stack from scratch (all containers and images are removed).'
    clean   = 'Stop and remove all containers, volumes, and prune unused Docker resources.'
    'test-all' = 'Run all stack commands in sequence and check health.'
    preflight = 'Check whether Docker is reachable before runtime commands.'
    report = 'Write a sanitized stack test report to logs/.'
}

function Show-CommandUsage {
    Write-Host "`n[Usage] pwsh ./scripts/torrents-stack.ps1 <command> [-Service <name>] [-Follow] [-VerboseAuth] [-ExternalLogMode off|auto|always] [-ExternalLogRetentionDays <days>]" -ForegroundColor Yellow
    Write-Host "`nAvailable commands:" -ForegroundColor Yellow
    foreach ($cmd in $CommandDescriptions.Keys) {
        Write-Host ("  {0,-8} {1}" -f $cmd, $CommandDescriptions[$cmd]) -ForegroundColor Yellow
    }
}

function Get-StackReport {
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
    Invoke-SafeClearHost
    Write-Host "[Health Poll] Service Statuses (updated: $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Cyan
    Write-Host ("{0,-15} {1,-14} {2,-12}" -f 'Service','Container ID','Status') -ForegroundColor Yellow
    Write-Host ("{0,-15} {1,-14} {2,-12}" -f '-------','------------','------') -ForegroundColor Yellow
    foreach ($svc in $services) {
        $status = $serviceStatus[$svc]
        $shortId = docker inspect --format='{{slice .Id 0 12}}' $svc 2>$null
        if (-not $shortId) { $shortId = '--' }
        $color = switch ($status) {
            'healthy'    { 'Green' }
            'starting'   { 'Yellow' }
            'unhealthy'  { 'Red' }
            'not found'  { 'Gray' }
            default      { 'White' }
        }
        Write-Host ("{0,-15} {1,-14} {2,-12}" -f $svc, $shortId, $status) -ForegroundColor $color
    }
}


function Write-DebugLine {
    param([string]$Message)
    if ($DebugOutput) { Write-Host "[Debug] $Message" -ForegroundColor Magenta }
}

Write-Host '========== torrents-stack.ps1 ==========' -ForegroundColor Yellow

# Show usage/help if required parameter is missing (for direct invocation)
if (-not $PSBoundParameters.ContainsKey('Command') -or [string]::IsNullOrWhiteSpace($Command)) {
    Show-CommandUsage
    exit 1
}
<#
.SYNOPSIS
    Manage the torrents-stack-expressvpn Docker Compose stack.
.DESCRIPTION
    Wrapper script for common stack operations. Syncs configuration from .env
    before starting services so containers always boot with up-to-date config.
.PARAMETER Command
    The stack command to run. Execute the script without parameters to print command descriptions.
.PARAMETER Service
    Optional. Scope 'logs' to a specific service (expressvpn, flaresolverr, jackett, qbittorrent).
.PARAMETER Follow
    When used with 'logs', keep streaming output (default: true).
.PARAMETER VerboseAuth
    When used with 'status', prints extra authentication-check diagnostics.
.PARAMETER DebugOutput
    Enables verbose debug output for troubleshooting.
.PARAMETER ExternalLogMode
    Controls wrapper progress log capture. 'off' disables external log files,
    'auto' writes them only when the wrapped command exits non-zero, and
    'always' always writes them.
.PARAMETER ExternalLogRetentionDays
    Removes managed wrapper progress logs older than this many days.
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
    pwsh ./scripts/torrents-stack.ps1 test-all
.NOTES
    Run Get-Help ./scripts/torrents-stack.ps1 -Full for details.
#>




# --- Function Definitions ---

$startupEnvPath = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
$startupEnvMap = Get-EnvMap -Path $startupEnvPath

if (-not $PSBoundParameters.ContainsKey('ExternalLogMode')) {
    $envExternalLogMode = Get-EnvOrDefault -EnvMap $startupEnvMap -Key 'STACK_EXTERNAL_LOG_MODE' -DefaultValue 'off'
    if ($envExternalLogMode -notin @('off','auto','always')) {
        throw ("Invalid STACK_EXTERNAL_LOG_MODE in .env: '{0}'. Use off, auto, or always." -f $envExternalLogMode)
    }

    $ExternalLogMode = $envExternalLogMode
}

if (-not $PSBoundParameters.ContainsKey('ExternalLogRetentionDays')) {
    $envRetentionDays = Get-EnvOrDefault -EnvMap $startupEnvMap -Key 'STACK_EXTERNAL_LOG_RETENTION_DAYS' -DefaultValue '14'
    $parsedRetentionDays = 0
    if (-not [int]::TryParse($envRetentionDays, [ref]$parsedRetentionDays)) {
        throw ("Invalid STACK_EXTERNAL_LOG_RETENTION_DAYS in .env: '{0}'. Use a whole number between 0 and 365." -f $envRetentionDays)
    }
    if ($parsedRetentionDays -lt 0 -or $parsedRetentionDays -gt 365) {
        throw ("Invalid STACK_EXTERNAL_LOG_RETENTION_DAYS in .env: '{0}'. Use a whole number between 0 and 365." -f $envRetentionDays)
    }

    $ExternalLogRetentionDays = $parsedRetentionDays
}

$stackContext = Get-StackContext -ScriptRoot $PSScriptRoot
$repoRoot = Resolve-Path $stackContext.RepoRoot
$script:ExternalLogMode = $ExternalLogMode
$script:ExternalLogRetentionDays = $ExternalLogRetentionDays
Set-Location $repoRoot


function Invoke-StackClean {
    Write-Host '[Command] Ensuring clean stack state...' -ForegroundColor Cyan
    & pwsh $PSCommandPath clean
}

function ConvertTo-BoolFromStatusLine {
    param(
        [string[]]$Lines,
        [string]$ServiceName
    )

    foreach ($line in @($Lines)) {
        if ($line -match "^SYNC_STATUS:${ServiceName}:(true|false)$") {
            return [System.Convert]::ToBoolean($matches[1])
        }
    }

    return $false
}

function Invoke-ConfigSyncScript {
    param(
        [string]$ScriptName,
        [string]$ServiceName,
        [string]$FailureMessage
    )

    $statusLines = & pwsh -NoProfile -File (Join-Path $PSScriptRoot $ScriptName) -SkipRestart -EmitStatus
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }

    return (ConvertTo-BoolFromStatusLine -Lines $statusLines -ServiceName $ServiceName)
}

function Get-ContainerEnvMap {
    param([string]$ContainerName)

    $map = @{}
    $envLines = docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $map
    }

    foreach ($line in @($envLines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $eqIndex = $line.IndexOf('=')
        if ($eqIndex -lt 1) { continue }
        $map[$line.Substring(0, $eqIndex)] = $line.Substring($eqIndex + 1)
    }

    return $map
}

function Test-ExpressvpnRefreshNeeded {
    param([hashtable]$EnvMap)

    $runningServices = @(docker compose ps --status running --services)
    if ($runningServices -notcontains 'expressvpn') {
        Write-Host '[Decision] expressvpn refresh not needed: service is not already running.' -ForegroundColor Gray
        return $false
    }

    $containerEnv = Get-ContainerEnvMap -ContainerName 'expressvpn'
    if ($containerEnv.Count -eq 0) {
        Write-Host '[Decision] expressvpn refresh not needed: running container env could not be inspected.' -ForegroundColor Gray
        return $false
    }

    $desiredEnv = @{
        'ACTIVATION_CODE' = Get-EnvOrDefault -EnvMap $EnvMap -Key 'EXPRESSVPN_ACTIVATION_CODE' -DefaultValue ''
        'REGION' = Get-EnvOrDefault -EnvMap $EnvMap -Key 'EXPRESSVPN_REGION' -DefaultValue 'uk-docklands'
        'SERVER' = Get-EnvOrDefault -EnvMap $EnvMap -Key 'EXPRESSVPN_REGION' -DefaultValue 'uk-docklands'
        'PROTOCOL' = Get-EnvOrDefault -EnvMap $EnvMap -Key 'EXPRESSVPN_PROTOCOL' -DefaultValue 'auto'
        'EXPRESSVPN_HEALTHCHECK_MODE' = Get-EnvOrDefault -EnvMap $EnvMap -Key 'EXPRESSVPN_HEALTHCHECK_MODE' -DefaultValue 'strict'
    }

    foreach ($key in $desiredEnv.Keys) {
        $currentValue = if ($containerEnv.ContainsKey($key)) { [string]$containerEnv[$key] } else { '' }
        if ($currentValue -ne [string]$desiredEnv[$key]) {
            Write-Host ("[Decision] expressvpn will be recreated: {0} changed." -f $key) -ForegroundColor Yellow
            return $true
        }
    }

    Write-Host '[Decision] expressvpn refresh not needed: running env already matches .env.' -ForegroundColor Gray
    return $false
}

function Invoke-StartRefreshPlan {
    param(
        [hashtable]$SyncStatus,
        [string[]]$RunningServicesBeforeStart,
        [bool]$ExpressvpnRefreshNeeded
    )

    if ($ExpressvpnRefreshNeeded) {
        Write-Host '[Step] Recreating expressvpn to apply env changes...' -ForegroundColor Cyan
        Show-CommandProgressTable -Command 'docker compose up -d --force-recreate --no-deps expressvpn' -LogPrefix 'expressvpn-refresh'

        $runningServicesAfterExpressvpnRefresh = @(docker compose ps --status running --services)
        if ($runningServicesAfterExpressvpnRefresh -contains 'qbittorrent') {
            Write-Host '[Decision] qbittorrent will be recreated: expressvpn was recreated.' -ForegroundColor Yellow
            Write-Host '[Step] Recreating qbittorrent to reattach it to expressvpn...' -ForegroundColor Cyan
            Show-CommandProgressTable -Command 'docker compose up -d --force-recreate --no-deps qbittorrent' -LogPrefix 'qbittorrent-refresh'
        } else {
            Write-Host '[Decision] qbittorrent recreate skipped: service is not already running after expressvpn refresh.' -ForegroundColor Gray
        }
    } else {
        Write-Host '[Decision] expressvpn recreate skipped.' -ForegroundColor Gray
    }

    if ($SyncStatus['jackett'] -and ($RunningServicesBeforeStart -contains 'jackett')) {
        Write-Host '[Decision] jackett will be restarted: synced config changed.' -ForegroundColor Yellow
        Write-Host '[Step] Restarting jackett to apply synced config...' -ForegroundColor Cyan
        Show-CommandProgressTable -Command 'docker compose restart jackett' -LogPrefix 'jackett-restart'
    } elseif ($SyncStatus['jackett']) {
        Write-Host '[Decision] jackett restart skipped: config changed but service is not already running.' -ForegroundColor Gray
    } else {
        Write-Host '[Decision] jackett restart not needed: synced config did not change.' -ForegroundColor Gray
    }

    if ($SyncStatus['qbittorrent'] -and ($RunningServicesBeforeStart -contains 'qbittorrent') -and -not $ExpressvpnRefreshNeeded) {
        Write-Host '[Decision] qbittorrent will be restarted: synced config changed.' -ForegroundColor Yellow
        Write-Host '[Step] Restarting qbittorrent to apply synced config...' -ForegroundColor Cyan
        Show-CommandProgressTable -Command 'docker compose restart qbittorrent' -LogPrefix 'qbittorrent-restart'
    } elseif ($SyncStatus['qbittorrent'] -and $ExpressvpnRefreshNeeded) {
        Write-Host '[Decision] qbittorrent standalone restart skipped: expressvpn recreate path handles it.' -ForegroundColor Gray
    } elseif ($SyncStatus['qbittorrent']) {
        Write-Host '[Decision] qbittorrent restart skipped: config changed but service is not already running.' -ForegroundColor Gray
    } else {
        Write-Host '[Decision] qbittorrent restart not needed: synced config did not change.' -ForegroundColor Gray
    }
}

# --- Shared Orchestration Functions ---
function Sync-Configs {
    Write-Host '[Step] Syncing configs...' -ForegroundColor Cyan
    return @{
        jackett = Invoke-ConfigSyncScript -ScriptName 'sync-jackett-config.ps1' -ServiceName 'jackett' -FailureMessage 'Jackett config sync failed.'
        qbittorrent = Invoke-ConfigSyncScript -ScriptName 'sync-qbittorrent-config.ps1' -ServiceName 'qbittorrent' -FailureMessage 'qBittorrent config sync failed.'
    }
}

function Show-Stack-Status {
    Write-Host "`n[Status] Stack status:" -ForegroundColor Green
    docker compose ps
}

function Show-Recent-Logs {
    param(
        [int]$Tail = 30,
        [datetime]$Since
    )
    $services = @('jackett','qbittorrent','flaresolverr','expressvpn')
    foreach ($svc in $services) {
        Write-Host "`n[Logs] Recent $svc logs:" -ForegroundColor Yellow
        $logArgs = @('compose', 'logs', "--tail=$Tail")
        if ($PSBoundParameters.ContainsKey('Since')) {
            $logArgs += '--since'
            $logArgs += $Since.ToString('o')
        }
        $logArgs += $svc
        & docker @logArgs
    }
}

function Get-ServiceEndpoints {
    return @(
        [pscustomobject]@{ Service = 'qBittorrent'; Url = "http://localhost:$($stackContext.QbittorrentWebUiPort)/" },
        [pscustomobject]@{ Service = 'Jackett'; Url = "http://localhost:$($stackContext.JackettPort)/" },
        [pscustomobject]@{ Service = 'FlareSolverr'; Url = "http://localhost:$($stackContext.FlareSolverrPort)/" }
    )
}

function Show-ServiceEndpoints {
    Write-Host "`n[Links] Service endpoints:" -ForegroundColor Cyan
    foreach ($endpoint in (Get-ServiceEndpoints)) {
        $link = Get-TerminalHyperlink -Text $endpoint.Url -Url $endpoint.Url
        Write-Host ("{0,-15} {1}" -f $endpoint.Service, $link) -ForegroundColor Green
    }
}

function ConvertTo-ServiceStatusMap {
    param([hashtable]$StateMap)

    $statusMap = @{}
    foreach ($serviceName in $StateMap.Keys) {
        $statusMap[$serviceName] = $StateMap[$serviceName].DisplayStatus
    }

    return $statusMap
}

function Test-AllServicesHealthy {
    param(
        [hashtable]$StateMap,
        [string[]]$ServiceNames
    )

    return (@($ServiceNames | Where-Object { $StateMap[$_].DisplayStatus -ne 'healthy' }).Count -eq 0)
}

function Show-ServiceDiagnostics {
    param(
        [hashtable]$StateMap,
        [string[]]$ServiceNames
    )

    foreach ($serviceName in $ServiceNames) {
        $state = $StateMap[$serviceName]
        Write-Host ("[Diagnosis] {0}: lifecycle={1}; health={2}; container={3}" -f $serviceName, $state.Lifecycle, $(if ([string]::IsNullOrWhiteSpace($state.Health)) { 'n/a' } else { $state.Health }), $(if ([string]::IsNullOrWhiteSpace($state.ContainerId)) { 'n/a' } else { $state.ContainerId })) -ForegroundColor Magenta
        if (-not $state.Exists) {
            Write-Host '  Container not found.' -ForegroundColor Yellow
            continue
        }

        $healthLog = Get-ComposeServiceLatestHealthLog -ServiceName $serviceName
        if ($null -ne $healthLog) {
            Write-Host ("  Last healthcheck exit code: {0}" -f $healthLog.ExitCode)
            Write-Host ("  Last healthcheck output: {0}" -f $healthLog.Output.Trim())
            continue
        }

        Write-Host '  No healthcheck log available for the current container state.' -ForegroundColor Yellow
    }
}

function Invoke-QbittorrentBootstrapRepair {
    $runningServices = @(docker compose ps --status running --services)
    if ($runningServices -notcontains 'qbittorrent') {
        Write-Host '[Recovery] qBittorrent bootstrap repair skipped: service is not running.' -ForegroundColor Yellow
        return
    }

    Write-Host '[Recovery] Reapplying qBittorrent runtime bootstrap...' -ForegroundColor Cyan
    & docker compose exec -T qbittorrent bash /tmp/bootstrap-qbittorrent-jackett.sh
    if ($LASTEXITCODE -ne 0) {
        throw 'qBittorrent bootstrap repair failed.'
    }
}


function Start-Stack {
    param([hashtable]$SyncStatus)

    Write-Host '[Step] Bringing stack up...' -ForegroundColor Cyan
    $logsSince = Get-Date
    $envMap = $stackContext.EnvMap
    $runningServicesBeforeStart = @(docker compose ps --status running --services)
    $expressvpnRefreshNeeded = Test-ExpressvpnRefreshNeeded -EnvMap $envMap
    # Show dynamic image pull progress
    Show-DockerPullProgress -Command 'docker compose pull'
    Show-CommandProgressTable -Command 'docker compose up -d' -LogPrefix 'docker-up'
    Invoke-StartRefreshPlan -SyncStatus $SyncStatus -RunningServicesBeforeStart $runningServicesBeforeStart -ExpressvpnRefreshNeeded:$expressvpnRefreshNeeded
    $services = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $dependencyServices = @('expressvpn','flaresolverr','jackett')
    $maxWait = 600 # seconds (10 minutes)
    $interval = 5  # seconds
    $startTime = Get-Date
    $qbittorrentRecoveryAttempted = $false
    while ($true) {
        $serviceStateMap = Get-ComposeServiceStateMap -ServiceNames $services
        $serviceStatus = ConvertTo-ServiceStatusMap -StateMap $serviceStateMap
        $allHealthy = Test-AllServicesHealthy -StateMap $serviceStateMap -ServiceNames $services
        $dependenciesHealthy = Test-AllServicesHealthy -StateMap $serviceStateMap -ServiceNames $dependencyServices

        if (-not $qbittorrentRecoveryAttempted -and $dependenciesHealthy) {
            $qbittorrentStatus = $serviceStateMap['qbittorrent'].DisplayStatus
            if ($qbittorrentStatus -in @('created','exited','not found')) {
                Write-Host ("[Recovery] qBittorrent is '{0}' after dependency services became healthy; retrying startup..." -f $qbittorrentStatus) -ForegroundColor Yellow
                Show-CommandProgressTable -Command 'docker compose up -d qbittorrent' -LogPrefix 'qbittorrent-recover'
                $qbittorrentRecoveryAttempted = $true
                continue
            }
        }

        Show-ServiceStatusTable -serviceStatus $serviceStatus -services $services
        if ($allHealthy) { break }
        if ((Get-Date) - $startTime -gt ([TimeSpan]::FromSeconds($maxWait))) {
            Write-Host "[Health] Timeout waiting for all services to become healthy." -ForegroundColor Red
            $unhealthy = $services | Where-Object { $serviceStateMap[$_].DisplayStatus -ne 'healthy' }
            if ($null -eq $unhealthy -or $unhealthy -eq '') { $unhealthy = @() } else { $unhealthy = @($unhealthy) }
            if (@($unhealthy).Count -gt 0) {
                Write-Host ("[Diagnosis] The following service(s) are not healthy: {0}" -f ($unhealthy -join ", ")) -ForegroundColor Yellow
                Show-ServiceDiagnostics -StateMap $serviceStateMap -ServiceNames $unhealthy
                Write-Host "[Diagnosis] To debug further, run: docker logs <container> or manually run the healthcheck script inside the container." -ForegroundColor Cyan
            }
            throw 'Timed out waiting for the stack to become healthy.'
        }
        Start-Sleep -Seconds $interval
    }

    Invoke-QbittorrentBootstrapRepair
    Show-Stack-Status
    Show-Recent-Logs -Since $logsSince

    # After stack start, check if all expected containers are running
    $expected = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $running = docker ps --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Names}}"
    $missing = $expected | Where-Object { $running -notcontains $_ }
    if ($null -eq $missing -or $missing -eq '') { $missing = @() } else { $missing = @($missing) }
    if (@($missing).Count -gt 0) {
        Write-Host ("[Diagnosis] Warning: Not all expected containers are running: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow
        Get-StackReport
        throw ("Not all expected containers are running: {0}" -f ($missing -join ', '))
    }
}



function Stop-Stack {
    Write-Host '[Step] Stopping stack (containers only)...' -ForegroundColor Cyan
    # Show progress for each container as it stops and is removed
    $containers = docker ps -a --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Names}}"
    if ($containers) {
        foreach ($c in $containers) {
            Write-ProgressLine "Container $c Stopping " -Color Yellow
            docker stop $c | Out-Null
            Write-ProgressLine "Container $c Stopped  " -Color Yellow
            docker rm $c | Out-Null
            Write-ProgressLine "Container $c Removed  " -Color Yellow
        }
    }
    # Remove networks
    $networks = docker network ls --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Name}}"
    foreach ($n in $networks) {
        Write-ProgressLine "Network $n Removing " -Color Yellow
        docker network rm $n | Out-Null
        Write-ProgressLine "Network $n Removed  " -Color Yellow
    }
    Write-Host ''
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
    if ($null -eq $containers -or $containers -eq '') { $containers = @() } else { $containers = @($containers) }
    $removed = @()
    if (@($containers).Count -gt 0) {
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
    $removed = @($removed) | Where-Object { $_ -and $_ -ne '' }
    if (@($removed).Count -gt 0) {
        Write-Host ("[Clean] Removed containers: {0}" -f ($removed -join ", ")) -ForegroundColor Green
    } else {
        Write-Host '[Clean] No project containers found.' -ForegroundColor Yellow
    }
    # Remove volumes (force, even if dangling)
    $volumes = docker volume ls --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.Name}}"
    if ($null -eq $volumes -or $volumes -eq '') { $volumes = @() } else { $volumes = @($volumes) }
    $namedVolume = "torrents-stack-expressvpn_shared-volume"
    $removedVolumes = @()
    if (@($volumes).Count -gt 0) {
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
    $removedVolumes = @($removedVolumes) | Where-Object { $_ -and $_ -ne '' }
    if (@($removedVolumes).Count -gt 0) {
        Write-Host ("[Clean] Removed volumes: {0}" -f ($removedVolumes -join ", ")) -ForegroundColor Green
    } else {
        Write-Host '[Clean] No project volumes found.' -ForegroundColor Yellow
    }
    # Remove networks (force, even if in use)
    $networks = docker network ls --filter "label=com.torrents-stack.project=expressvpn-stack" --format "{{.ID}}"
    if ($null -eq $networks -or $networks -eq '') { $networks = @() } else { $networks = @($networks) }
    if (@($networks).Count -gt 0) {
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
    Show-CommandProgressTable -Command 'docker system prune -af --volumes' -LogPrefix 'docker-prune'
}

function Build-Stack {
    Write-Host '[Step] Building all images from scratch (no cache)...' -ForegroundColor Cyan
    Show-DockerProgressTable -Command 'docker compose build --no-cache'
}

function Update-Images {
    Write-Host '[Step] Pulling latest images...' -ForegroundColor Cyan
    Show-DockerPullProgress -Command 'docker compose pull'
}

function Show-Logs {
    param($Service, $Follow)
    $logArgs = @('compose', 'logs')
    if ($Follow) { $logArgs += '--follow' }
    $logArgs += '--tail=100'
    if ($Service -ne '') { $logArgs += $Service }
    & docker @logArgs
}

function Get-JackettApiKey {
    param([hashtable]$EnvMap)

    $apiKey = Get-EnvOrDefault -EnvMap $EnvMap -Key 'JACKETT_CFG_API_KEY' -DefaultValue ''
    $source = '.env (JACKETT_CFG_API_KEY)'

    if ([string]::IsNullOrWhiteSpace($apiKey) -or ($apiKey -eq 'null')) {
        $jackettConfigPath = Join-Path $stackContext.ConfigsRoot 'Jackett/ServerConfig.json'
        if (Test-Path -LiteralPath $jackettConfigPath) {
            try {
                $jackettConfig = Get-Content -LiteralPath $jackettConfigPath -Raw | ConvertFrom-Json
                if ($jackettConfig.APIKey) {
                    $apiKey = [string]$jackettConfig.APIKey
                    $source = $jackettConfigPath
                }
            }
            catch {
                Write-Verbose ("Unable to parse Jackett config at {0}: {1}" -f $jackettConfigPath, $_.Exception.Message)
            }
        }
    }

    return [pscustomobject]@{
        ApiKey = $apiKey
        Source = $source
    }
}

function Show-AuthChecks {
    param(
        [string[]]$RunningServices,
        [switch]$VerboseAuth
    )

    Write-Host "`n[Auth] Authentication checks:" -ForegroundColor Cyan

    $envMap = $stackContext.EnvMap
    $qbitBaseUrl = "http://localhost:$($stackContext.QbittorrentWebUiPort)"
    $jackettBaseUrl = "http://localhost:$($stackContext.JackettPort)"

    if ($RunningServices -contains 'qbittorrent') {
        $qbitPassword = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT' -DefaultValue ''
        if ([string]::IsNullOrWhiteSpace($qbitPassword)) {
            Write-Host 'qBittorrent login check skipped: QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT is not set' -ForegroundColor Gray
        }
        else {
            if ($VerboseAuth) {
                Write-Host "qBittorrent auth target: $qbitBaseUrl"
                Write-Host 'qBittorrent auth username: admin'
            }
            $qbitResult = Test-QbittorrentLogin -BaseUrl $qbitBaseUrl -Username 'admin' -Auth $qbitPassword
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
        Write-Host 'qBittorrent login check skipped: service is not running' -ForegroundColor Gray
    }

    if ($RunningServices -contains 'jackett') {
        $jackettApi = Get-JackettApiKey -EnvMap $envMap
        if ([string]::IsNullOrWhiteSpace($jackettApi.ApiKey) -or ($jackettApi.ApiKey -eq 'null')) {
            Write-Host 'Jackett auth check skipped: API key not available from .env or configs/Jackett/ServerConfig.json' -ForegroundColor Gray
        }
        else {
            if ($VerboseAuth) {
                Write-Host "Jackett auth target: $jackettBaseUrl"
                Write-Host "Jackett API key source: $($jackettApi.Source)"
            }
            $jackettResult = Test-JackettApiKey -BaseUrl $jackettBaseUrl -ApiKey $jackettApi.ApiKey
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
        Write-Host 'Jackett auth check skipped: service is not running' -ForegroundColor Gray
    }
}

function Test-DockerDaemonAvailable {
    $null = docker info --format '{{.ServerVersion}}' 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-DockerContextName {
    $contextName = @(docker context show 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    return (@($contextName) -join '').Trim()
}

function Show-DockerPreflight {
    param([string]$CommandName = 'docker')

    $contextName = Get-DockerContextName
    if (Test-DockerDaemonAvailable) {
        $serverVersion = (@(docker info --format '{{.ServerVersion}}' 2>$null) -join '').Trim()
        $contextSuffix = if ([string]::IsNullOrWhiteSpace($contextName)) { '' } else { " (context: $contextName)" }
        Write-Host ("[Preflight] Docker daemon is available{0}. Server version: {1}" -f $contextSuffix, $serverVersion) -ForegroundColor Green
        return $true
    }

    Write-Host ("[Preflight] Docker daemon is unavailable for '{0}'." -f $CommandName) -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($contextName)) {
        Write-Host ("[Preflight] Current Docker context: {0}" -f $contextName) -ForegroundColor Yellow
    }

    if ($IsWindows) {
        Write-Host '[Preflight] Start Docker Desktop and wait for the Linux engine to report Running, then rerun the command.' -ForegroundColor Yellow
    }
    else {
        Write-Host '[Preflight] Start the Docker daemon for the current context and rerun the command.' -ForegroundColor Yellow
    }

    return $false
}

function Assert-DockerDaemonAvailable {
    param([string]$CommandName)

    if (-not (Show-DockerPreflight -CommandName $CommandName)) {
        throw ("Docker daemon is unavailable for '{0}'." -f $CommandName)
    }
}

function New-StackReportPath {
    param([string]$ProvidedPath)

    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        $candidatePath = if ([System.IO.Path]::IsPathRooted($ProvidedPath)) {
            $ProvidedPath
        } else {
            Join-Path $repoRoot $ProvidedPath
        }

        $parentPath = Split-Path -Parent $candidatePath
        if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
            New-DirectoryIfMissing -Path $parentPath
        }

        return [System.IO.Path]::GetFullPath($candidatePath)
    }

    $logDir = Join-Path $repoRoot 'logs'
    New-DirectoryIfMissing -Path $logDir
    return Join-Path $logDir ("stack-test-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-summary.md')
}

function Get-ComposeRenderText {
    $composeOutput = @(docker compose config --no-interpolate 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ("docker compose config --no-interpolate failed.`n{0}" -f (@($composeOutput) -join [Environment]::NewLine))
    }

    return (@($composeOutput) -join [Environment]::NewLine)
}

function Invoke-RepoPesterTests {
    $testPath = Join-Path $repoRoot 'tests'
    $testFiles = @()
    if (Test-Path -LiteralPath $testPath) {
        $testFiles = @(Get-ChildItem -LiteralPath $testPath -Filter '*.Tests.ps1' -File | Sort-Object -Property Name | ForEach-Object { $_.Name })
    }
    $output = @(pwsh -NoProfile -Command "Invoke-Pester -Path './tests'" 2>&1)

    return [pscustomobject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
        TestPath = $testPath
        TestFiles = $testFiles
    }
}

function Test-ComposeGoalAlignment {
    param([string]$ComposeRenderText)

    return [pscustomobject]@{
        QbittorrentViaVpn = [regex]::IsMatch($ComposeRenderText, '(?s)qbittorrent:\s*.*?network_mode:\s*service:expressvpn')
        JackettOnAppNet = [regex]::IsMatch($ComposeRenderText, '(?s)jackett:\s*.*?networks:\s*\r?\n\s+app_net:')
        FlareSolverrOnAppNet = [regex]::IsMatch($ComposeRenderText, '(?s)flaresolverr:\s*.*?networks:\s*\r?\n\s+app_net:')
        ExpressvpnHealthcheck = [regex]::IsMatch($ComposeRenderText, '(?s)expressvpn:\s*.*?healthcheck:')
        JackettHealthcheck = [regex]::IsMatch($ComposeRenderText, '(?s)jackett:\s*.*?healthcheck:')
        QbittorrentHealthcheck = [regex]::IsMatch($ComposeRenderText, '(?s)qbittorrent:\s*.*?healthcheck:')
    }
}

function Test-HttpEndpointStatus {
    param(
        [string]$Service,
        [string]$Url
    )

    if ($Service -eq 'Jackett') {
        try {
            $response = Invoke-WebRequest -Uri $Url -MaximumRedirection 0 -SkipHttpErrorCheck -TimeoutSec 15 -ErrorAction Stop
            return [pscustomobject]@{
                Service = $Service
                Url = $Url
                StatusCode = [int]$response.StatusCode
                Reachable = $true
            }
        }
        catch {
            $statusCode = -1
            if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode.value__
            }

            return [pscustomobject]@{
                Service = $Service
                Url = $Url
                StatusCode = $statusCode
                Reachable = ($statusCode -ge 200)
            }
        }
    }

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)

    try {
        $response = $client.GetAsync($Url).GetAwaiter().GetResult()
        return [pscustomobject]@{
            Service = $Service
            Url = $Url
            StatusCode = [int]$response.StatusCode
            Reachable = $true
        }
    }
    catch {
        return [pscustomobject]@{
            Service = $Service
            Url = $Url
            StatusCode = -1
            Reachable = $false
        }
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Export-StackTestReport {
    param([string]$ReportPath)

    $resolvedReportPath = New-StackReportPath -ProvidedPath $ReportPath
    $composeRenderText = Get-ComposeRenderText
    $goalAlignment = Test-ComposeGoalAlignment -ComposeRenderText $composeRenderText

    $validateOutput = @(pwsh -NoProfile -File (Join-Path $PSScriptRoot 'validate-config.ps1') 2>&1)
    $validateExitCode = $LASTEXITCODE
    $pesterResult = Invoke-RepoPesterTests
    $pesterOutput = $pesterResult.Output
    $pesterExitCode = $pesterResult.ExitCode
    $pesterTestFiles = @($pesterResult.TestFiles)

    $dockerAvailable = Test-DockerDaemonAvailable
    $composePsOutput = @()
    $endpointChecks = @()
    $qbittorrentNetworkMode = ''
    $expressvpnContainerId = ''
    $qbittorrentSharesExpressvpn = $false
    if ($dockerAvailable) {
        $composePsOutput = @(docker compose ps 2>&1)
        $expressvpnContainerId = (@(docker inspect --format '{{.Id}}' expressvpn 2>$null) -join '').Trim()
        $qbittorrentNetworkMode = (@(docker inspect --format '{{.HostConfig.NetworkMode}}' qbittorrent 2>$null) -join '').Trim()
        if (-not [string]::IsNullOrWhiteSpace($expressvpnContainerId)) {
            $qbittorrentSharesExpressvpn = ($qbittorrentNetworkMode -eq ("container:{0}" -f $expressvpnContainerId))
        }
        $endpointChecks = @(Get-ServiceEndpoints | ForEach-Object {
            Test-HttpEndpointStatus -Service $_.Service -Url $_.Url
        })
    }

    $lines = @(
        '# Stack Test Report',
        '',
        ('Timestamp: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
        '',
        '## Goal Check',
        '',
        'Project goal under test: only qBittorrent should route through ExpressVPN, while Jackett and FlareSolverr stay on the app network with their own ports.',
        '',
        '## Commands Run',
        '',
        '1. `pwsh ./scripts/torrents-stack.ps1 preflight`',
        '2. `pwsh ./scripts/validate-config.ps1`',
        '3. `docker compose config --no-interpolate`',
        '4. `docker compose ps`',
        '5. `Invoke-Pester -Path ./tests`',
        '',
        '## Results',
        '',
        '### Docker preflight',
        '',
        ('- Docker daemon available: `{0}`' -f $dockerAvailable.ToString().ToLowerInvariant())
    )

    if ($dockerAvailable) {
        $lines += '- Live Docker commands can run in the current environment.'
    }
    else {
        $lines += '- Runtime stack commands will not complete until Docker is started.'
    }

    $lines += @(
        '',
        '### Offline validation',
        '',
        ('- `validate-config.ps1` exit code: `{0}`' -f $validateExitCode),
        ('- `validate-config.ps1` summary: `{0}`' -f ((@($validateOutput) | Select-Object -Last 1) -join '').Trim()),
        ('- Pester exit code: `{0}`' -f $pesterExitCode)
    )

    if ($pesterTestFiles.Count -gt 0) {
        $lines += ('- Pester test files: `{0}`' -f ($pesterTestFiles -join ', '))
    }

    $lines += @(
        ('- Pester summary: `{0}`' -f ((@($pesterOutput) | Select-Object -Last 2 | Select-Object -First 1) -join '').Trim()),
        '',
        '### Goal alignment confirmed from compose render',
        '',
        ('- qBittorrent uses ExpressVPN network namespace: `{0}`' -f $goalAlignment.QbittorrentViaVpn.ToString().ToLowerInvariant()),
        ('- Jackett remains on `app_net`: `{0}`' -f $goalAlignment.JackettOnAppNet.ToString().ToLowerInvariant()),
        ('- FlareSolverr remains on `app_net`: `{0}`' -f $goalAlignment.FlareSolverrOnAppNet.ToString().ToLowerInvariant()),
        ('- ExpressVPN healthcheck defined: `{0}`' -f $goalAlignment.ExpressvpnHealthcheck.ToString().ToLowerInvariant()),
        ('- Jackett healthcheck defined: `{0}`' -f $goalAlignment.JackettHealthcheck.ToString().ToLowerInvariant()),
        ('- qBittorrent healthcheck defined: `{0}`' -f $goalAlignment.QbittorrentHealthcheck.ToString().ToLowerInvariant()),
        ''
    )

    if ($composePsOutput.Count -gt 0) {
        $lines += @(
            '### Current compose state',
            '',
            '```text'
        )
        $lines += @($composePsOutput)
        $lines += @(
            '```',
            ''
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($qbittorrentNetworkMode)) {
        $lines += @(
            '### Live runtime checks',
            '',
            ('- Live qBittorrent network mode: `{0}`' -f $qbittorrentNetworkMode),
            ('- qBittorrent is sharing ExpressVPN network namespace: `{0}`' -f $qbittorrentSharesExpressvpn.ToString().ToLowerInvariant())
        )

        foreach ($endpointCheck in $endpointChecks) {
            $lines += ('- {0} endpoint `{1}` returned status `{2}`' -f $endpointCheck.Service, $endpointCheck.Url, $endpointCheck.StatusCode)
        }

        $lines += ''
    }

    $lines += @(
        '## Recommendations',
        '',
        '1. Use `preflight` before runtime commands when testing from a fresh shell or after Docker Desktop restarts.',
        '2. Use `report` when you need a test artifact; it avoids writing expanded secret values from `.env`.',
        '3. If the stack is not already running, run `pwsh ./scripts/torrents-stack.ps1 start` and then `status -VerboseAuth` for live endpoint verification.'
    )

    $lines | Set-Content -LiteralPath $resolvedReportPath
    Write-Host ("[Report] Sanitized stack test report written to: {0}" -f $resolvedReportPath) -ForegroundColor Green
    return $resolvedReportPath
}

function Show-Status {
    param([switch]$VerboseAuth)

    if (-not (Show-DockerPreflight -CommandName 'status')) {
        Show-ServiceEndpoints
        return
    }

    $services = @('expressvpn','flaresolverr','jackett','qbittorrent')
    $serviceStatus = Get-ComposeServiceHealthMap -ServiceNames $services
    Show-ServiceStatusTable -serviceStatus $serviceStatus -services $services
    Write-Host '[Status] Stack status (docker compose ps):' -ForegroundColor Green
    docker compose ps

    Write-Host "`n[Status] qBittorrent Jackett plugin check:" -ForegroundColor Cyan
    Test-QbittorrentJackettPlugin | Out-Null

    $runningServices = @(docker compose ps --status running --services)
    Show-AuthChecks -RunningServices $runningServices -VerboseAuth:$VerboseAuth

    Show-ServiceEndpoints
}

function Invoke-TimedCommand {
    param(
        [string]$CommandName,
        [string]$StartMessage,
        [scriptblock]$Action,
        [string]$DoneMessage,
        [scriptblock]$BeforeTimingAction
    )

    $cmdStart = Get-Date
    Write-Host $StartMessage -ForegroundColor Cyan
    & $Action
    Write-Host $DoneMessage -ForegroundColor Green
    if ($null -ne $BeforeTimingAction) {
        & $BeforeTimingAction
    }
    $cmdEnd = Get-Date
    Write-Host ("[Timing] Elapsed time for '{0}': {1}" -f $CommandName, ($cmdEnd - $cmdStart)) -ForegroundColor Yellow
}


function Reset-Stack {
    Remove-StackWithVolumes
    Clear-DockerUnused
    Build-Stack
    Start-Stack -SyncStatus @{ jackett = $false; qbittorrent = $false }
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
    $allPassed = $true
    $stepResults = @{}
    # Define steps and their dependencies (by name)
    $steps = @(
        @{ Name = 'Validate config'; Action = { & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'validate-config.ps1'); if ($LASTEXITCODE -ne 0) { throw 'validate-config.ps1 failed.' } }; DependsOn = @() },
        @{ Name = 'Pester';        Action = { $pesterResult = Invoke-RepoPesterTests; @($pesterResult.Output) | ForEach-Object { Write-Host $_ }; if ($pesterResult.ExitCode -ne 0) { throw 'Invoke-Pester failed.' } }; DependsOn = @('Validate config') },
        @{ Name = 'Clean (start)'; Action = { Remove-StackWithVolumes; Clear-DockerUnused }; DependsOn = @() },
        @{ Name = 'Start';         Action = { $syncStatus = Sync-Configs; Start-Stack -SyncStatus $syncStatus }; DependsOn = @('Clean (start)') },
        @{ Name = 'Status';        Action = { Show-Status }; DependsOn = @('Start') },
        @{ Name = 'Logs';          Action = { Show-Logs -Service $null -Follow:$false }; DependsOn = @('Start') },
        @{ Name = 'Sync';          Action = { $null = Sync-Configs }; DependsOn = @() },
        @{ Name = 'Update';        Action = { Update-Images; $syncStatus = Sync-Configs; Start-Stack -SyncStatus $syncStatus }; DependsOn = @('Start') },
        @{ Name = 'Restart';       Action = { Stop-Stack; $syncStatus = Sync-Configs; Start-Stack -SyncStatus $syncStatus }; DependsOn = @('Start') },
        @{ Name = 'Rebuild';       Action = { Invoke-StackClean; Reset-Stack }; DependsOn = @('Clean (start)') },
        @{ Name = 'Stop';          Action = { Stop-Stack }; DependsOn = @('Start') },
        @{ Name = 'Clean (end)';   Action = { Remove-StackWithVolumes; Clear-DockerUnused }; DependsOn = @() }
    )
    Write-Host '========== TEST SEQUENCE ==========' -ForegroundColor Cyan
    Write-DebugLine "Test-Stack-All running in-process with dependency checks"
    $stepStatus = @{}
    foreach ($step in $steps) {
        $name = $step.Name
        $deps = $step.DependsOn
        $canRun = $true
        $failedDeps = @()
        foreach ($dep in $deps) {
            if ($stepStatus.ContainsKey($dep) -and -not $stepStatus[$dep]) {
                $canRun = $false
                $failedDeps += $dep
            }
        }
        Write-Host ("-- $name --") -ForegroundColor Yellow
        if (@($deps).Count -gt 0) {
            Write-Host ("[Info] Dependencies: {0}" -f ($deps -join ', ')) -ForegroundColor Gray
        } else {
            Write-Host "[Info] No dependencies." -ForegroundColor Gray
        }
        if ($canRun) {
            $ok = Test-Step -StepName $name -Action $step.Action
            $stepStatus[$name] = $ok
            $stepResults[$name] = $ok
            if (-not $ok) {
                $allPassed = $false
                Write-Host "[Test] $name FAILED." -ForegroundColor Red
            }
            if ($name -in @('Start','Update','Restart','Rebuild')) {
                Write-Host "[Test] Checking stack status after $name..." -ForegroundColor Yellow
                Show-Status
            }
        } else {
            $stepStatus[$name] = $false
            $stepResults[$name] = $false
            Write-Host ("[Test] Skipping $name due to failed dependencies: {0}" -f ($failedDeps -join ', ')) -ForegroundColor Red
        }
    }
    Write-Host '========== TEST SUMMARY ==========' -ForegroundColor Cyan
    foreach ($step in $steps) {
        $name = $step.Name
        $ok = $stepResults[$name]
        $color = if ($ok) { 'Green' } else { 'Red' }
        Write-Host ("{0,-15} {1}" -f $name, ($(if ($ok) { 'PASS' } else { 'FAIL' }))) -ForegroundColor $color
        if (@($step.DependsOn).Count -gt 0) {
            Write-Host ("    Dependencies: {0}" -f ($step.DependsOn -join ', ')) -ForegroundColor Gray
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
        Invoke-TimedCommand -CommandName 'start' -StartMessage '[Command] Starting stack...' -DoneMessage '[Command] Stack start complete.' -BeforeTimingAction {
            Show-ServiceEndpoints
        } -Action {
            Assert-DockerDaemonAvailable -CommandName 'start'
            $syncStatus = Sync-Configs
            Start-Stack -SyncStatus $syncStatus
        }
    }
    'stop' {
        Invoke-TimedCommand -CommandName 'stop' -StartMessage '[Command] Stopping stack...' -DoneMessage '[Command] Stack stop complete.' -Action {
            Assert-DockerDaemonAvailable -CommandName 'stop'
            Stop-Stack
        }
    }
    'restart' {
        Invoke-TimedCommand -CommandName 'restart' -StartMessage '[Command] Restarting stack...' -DoneMessage '[Command] Stack restart complete.' -BeforeTimingAction {
            Show-ServiceEndpoints
        } -Action {
            Assert-DockerDaemonAvailable -CommandName 'restart'
            Stop-Stack
            $syncStatus = Sync-Configs
            Start-Stack -SyncStatus $syncStatus
        }
    }
    'rebuild' {
        Invoke-TimedCommand -CommandName 'rebuild' -StartMessage '[Command] Rebuilding stack (full reset)...' -DoneMessage '[Command] Stack rebuild complete.' -BeforeTimingAction {
            Show-ServiceEndpoints
        } -Action {
            Assert-DockerDaemonAvailable -CommandName 'rebuild'
            Invoke-StackClean
            Reset-Stack
        }
    }
    'update' {
        Invoke-TimedCommand -CommandName 'update' -StartMessage '[Command] Updating stack images and services...' -DoneMessage '[Command] Stack update complete.' -BeforeTimingAction {
            Show-ServiceEndpoints
        } -Action {
            Assert-DockerDaemonAvailable -CommandName 'update'
            Update-Images
            $syncStatus = Sync-Configs
            Start-Stack -SyncStatus $syncStatus
        }
    }
    'status' {
        Invoke-TimedCommand -CommandName 'status' -StartMessage '[Command] Showing stack status...' -DoneMessage '[Command] Stack status shown.' -Action {
            Show-Status -VerboseAuth:$VerboseAuth
        }
    }
    'logs' {
        Invoke-TimedCommand -CommandName 'logs' -StartMessage '[Command] Showing recent logs...' -DoneMessage '[Command] Logs shown.' -Action {
            Assert-DockerDaemonAvailable -CommandName 'logs'
            Show-Logs -Service $Service -Follow:$Follow
        }
    }
    'sync' {
        Invoke-TimedCommand -CommandName 'sync' -StartMessage '[Command] Syncing configs...' -DoneMessage '[Command] Config sync complete.' -Action {
            $null = Sync-Configs
        }
    }
    'clean' {
        Invoke-TimedCommand -CommandName 'clean' -StartMessage '[Command] Cleaning stack and unused Docker resources...' -DoneMessage '[Command] Stack and Docker resources fully cleaned.' -Action {
            Assert-DockerDaemonAvailable -CommandName 'clean'
            Remove-StackWithVolumes
            Clear-DockerUnused
        }
    }
    'test-all' {
        Invoke-TimedCommand -CommandName 'test-all' -StartMessage '[Command] Running full stack command test sequence...' -DoneMessage '[Command] Stack command test sequence complete.' -Action {
            Assert-DockerDaemonAvailable -CommandName 'test-all'
            Test-Stack-All
        }
    }
    'preflight' {
        Invoke-TimedCommand -CommandName 'preflight' -StartMessage '[Command] Checking Docker preflight...' -DoneMessage '[Command] Docker preflight complete.' -Action {
            $null = Show-DockerPreflight -CommandName 'preflight'
        }
    }
    'report' {
        Invoke-TimedCommand -CommandName 'report' -StartMessage '[Command] Writing sanitized stack test report...' -DoneMessage '[Command] Stack test report complete.' -Action {
            $null = Export-StackTestReport -ReportPath $OutputPath
        }
    }
    default {
        Write-Host "[Error] Unknown command: $Command" -ForegroundColor Red
        exit 1
    }
}
