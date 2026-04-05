# --- Console Progress Line Utility ---
# Writes a message to the same console line, overwriting previous content.
function Write-ProgressLine {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    # Use single-line redraw when RawUI is available; otherwise fall back to plain writes.
    try {
        if ($Host.UI -and $Host.UI.RawUI) {
            $null = $Host.UI.RawUI.CursorPosition
            $esc = [char]27
            Write-Host ("${esc}[2K" + $Message) -ForegroundColor $Color -NoNewline
            Write-Host "`r" -NoNewline
            return
        }
    } catch {
        Write-Debug ("Progress redraw fallback: {0}" -f $_.Exception.Message)
    }
    if ($true) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Invoke-SafeClearHost {
    try {
        Clear-Host
    }
    catch {
        Write-Debug ("Clear-Host skipped: {0}" -f $_.Exception.Message)
    }
}
<#
.SYNOPSIS
    Shared utility functions used across all stack management scripts.

.DESCRIPTION
    This module provides common functions for environment parsing, HTTP operations,
    and INI file manipulation. Used by torrents-stack.ps1, sync-qbittorrent-config.ps1,
    and sync-jackett-config.ps1 to reduce code duplication.
#>

Set-StrictMode -Version Latest

# Import standardized logging function
. "$PSScriptRoot/Write-Log.ps1"

# Utility: Redact secrets in strings (for logs)
function Protect-Secret {
    param([string]$InputString)
        $patterns = @(
            'EXPRESSVPN_ACTIVATION_CODE=\w+',
            'JACKETT_CFG_API_KEY=\w+',
            'JACKETT_CFG_OMDB_API_KEY=\w+',
            '[A-Za-z0-9]{32,}' # generic API key/token
        )
    $out = $InputString
    foreach ($pat in $patterns) {
        $out = $out -replace $pat, '[REDACTED]'
    }
    return $out
}

# Enhanced error handler
function Write-ErrorRecord {
    param([string]$Context, [object]$ErrorObj)
    Write-StackLog -Message "[$Context] $($ErrorObj.Exception.Message)" -Level ERROR
    exit 1
}

<#
.SYNOPSIS
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

function Get-StackContext {
    param(
        [string]$ScriptRoot = $PSScriptRoot
    )

    $repoRoot = Split-Path -Parent $ScriptRoot
    $envPath = Join-Path $repoRoot '.env'
    $envMap = Get-EnvMap -Path $envPath
    $configsRoot = Resolve-HostPath -RepoRoot $repoRoot -ConfiguredPath $envMap['HOST_CONFIGS_DIR'] -DefaultRelativePath './configs'
    $downloadsRoot = Resolve-HostPath -RepoRoot $repoRoot -ConfiguredPath $envMap['HOST_DOWNLOADS_DIR'] -DefaultRelativePath './downloads'

    return [pscustomobject]@{
        RepoRoot = $repoRoot
        EnvPath = $envPath
        EnvMap = $envMap
        ConfigsRoot = $configsRoot
        DownloadsRoot = $downloadsRoot
        ContainerConfigsDir = Get-EnvOrDefault -EnvMap $envMap -Key 'CONTAINER_CONFIGS_DIR' -DefaultValue '/config'
        ContainerDownloadsDir = Get-EnvOrDefault -EnvMap $envMap -Key 'CONTAINER_DOWNLOADS_DIR' -DefaultValue '/downloads'
        QbittorrentWebUiPort = Get-EnvOrDefault -EnvMap $envMap -Key 'QBITTORRENT_WEBUI_PORT' -DefaultValue '8080'
        JackettPort = Get-EnvOrDefault -EnvMap $envMap -Key 'JACKETT_PORT' -DefaultValue '9117'
        FlareSolverrPort = Get-EnvOrDefault -EnvMap $envMap -Key 'FLARESOLVERR_PORT' -DefaultValue '8191'
    }
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

function Get-ComposeRunningServices {
    param([string]$RepoRoot)

    Push-Location $RepoRoot
    try {
        return @(docker compose ps --status running --services)
    }
    finally {
        Pop-Location
    }
}

function Get-ComposeServiceState {
    param([string]$ServiceName)

    $inspect = @(docker inspect --format='{{if .State}}{{.State.Status}}{{end}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{slice .Id 0 12}}' $ServiceName 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{
            ServiceName   = $ServiceName
            Exists        = $false
            Lifecycle     = 'not found'
            Health        = ''
            DisplayStatus = 'not found'
            ContainerId   = ''
        }
    }

    $parts = ((@($inspect) -join '').Trim() -split '\|', 3)
    $lifecycle = if ($parts.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($parts[0])) { $parts[0].Trim() } else { 'unknown' }
    $health = if ($parts.Count -ge 2) { $parts[1].Trim() } else { '' }
    $containerId = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
    $displayStatus = if (-not [string]::IsNullOrWhiteSpace($health)) { $health } else { $lifecycle }

    return [pscustomobject]@{
        ServiceName   = $ServiceName
        Exists        = $true
        Lifecycle     = $lifecycle
        Health        = $health
        DisplayStatus = $displayStatus
        ContainerId   = $containerId
    }
}

function Get-ComposeServiceStateMap {
    param([string[]]$ServiceNames)

    $stateMap = @{}
    foreach ($serviceName in $ServiceNames) {
        $stateMap[$serviceName] = Get-ComposeServiceState -ServiceName $serviceName
    }

    return $stateMap
}

function Stop-ComposeService {
    param(
        [string]$RepoRoot,
        [string]$ServiceName
    )

    Push-Location $RepoRoot
    try {
        Write-ProgressLine ("Stopping {0}..." -f $ServiceName) -Color Yellow
        docker compose stop $ServiceName | Out-Null
        Write-ProgressLine ("Stopped {0}.  " -f $ServiceName) -Color Yellow
    }
    finally {
        Pop-Location
    }
}

function Start-ComposeService {
    param(
        [string]$RepoRoot,
        [string]$ServiceName
    )

    Push-Location $RepoRoot
    try {
        Write-ProgressLine ("Starting {0}..." -f $ServiceName) -Color Yellow
        docker compose start $ServiceName | Out-Null
        Write-ProgressLine ("Started {0}.   " -f $ServiceName) -Color Yellow
    }
    finally {
        Pop-Location
    }
}

function Restart-ComposeServiceIfRunning {
    param(
        [string]$RepoRoot,
        [string]$ServiceName,
        [string]$RestartMessage,
        [string]$NotRunningMessage
    )

    $runningServices = Get-ComposeRunningServices -RepoRoot $RepoRoot
    if ($runningServices -contains $ServiceName) {
        Stop-ComposeService -RepoRoot $RepoRoot -ServiceName $ServiceName
        Start-ComposeService -RepoRoot $RepoRoot -ServiceName $ServiceName
        Write-Host $RestartMessage
        return $true
    }

    Write-Host $NotRunningMessage
    return $false
}

function Get-ComposeServiceHealthMap {
    param([string[]]$ServiceNames)

    $serviceStatus = @{}
    $stateMap = Get-ComposeServiceStateMap -ServiceNames $ServiceNames
    foreach ($serviceName in $ServiceNames) {
        $serviceStatus[$serviceName] = $stateMap[$serviceName].DisplayStatus
    }

    return $serviceStatus
}

function Get-ComposeServiceLatestHealthLog {
    param([string]$ServiceName)

    $healthLogJson = @(docker inspect --format='{{if .State.Health}}{{json .State.Health.Log}}{{end}}' $ServiceName 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $rawJson = (@($healthLogJson) -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($rawJson)) {
        return $null
    }

    try {
        $healthLogs = $rawJson | ConvertFrom-Json
        return @($healthLogs) | Select-Object -Last 1
    }
    catch {
        return $null
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
    $passwordBstr = [IntPtr]::Zero
    try {
        $plainPassword = $null
        if ($Auth -is [System.Management.Automation.PSCredential]) {
            $plainPassword = $Auth.GetNetworkCredential().Password
        } elseif ($Auth -is [System.Security.SecureString]) {
            $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Auth)
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
        } elseif ($Auth -is [string]) {
            $plainPassword = $Auth
        } else {
            throw "Auth parameter must be a String, SecureString, or PSCredential."
        }
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
        if ($passwordBstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
        }
        $client.Dispose()
    }
}

# --- Jackett API key check (shared) ---
function Test-JackettApiKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,
        [Parameter(Mandatory=$true)]
        [string]$ApiKey
    )

    $client = New-HttpClient
    try {
        $endpoint = "$BaseUrl/api/v2.0/indexers/all/results?apikey=$ApiKey&Query=test&Tracker[]=all"
        $response = $client.GetAsync($endpoint).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if ($response.IsSuccessStatusCode) {
            return [pscustomobject]@{
                Ok         = $true
                Message    = 'Jackett API key check passed'
                Endpoint   = $endpoint
                StatusCode = [int]$response.StatusCode
                Body       = $body
            }
        }

        return [pscustomobject]@{
            Ok         = $false
            Message    = "Jackett API key check failed (status=$([int]$response.StatusCode))"
            Endpoint   = $endpoint
            StatusCode = [int]$response.StatusCode
            Body       = $body
        }
    }
    catch {
        return [pscustomobject]@{
            Ok         = $false
            Message    = "Jackett API key check failed: $($_.Exception.Message)"
            Endpoint   = "$BaseUrl/api/v2.0/indexers/all/results"
            StatusCode = -1
            Body       = ''
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
    $runningServices = @(docker compose ps --services --filter status=running 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Docker daemon unavailable; plugin check skipped.' -ForegroundColor Gray
        return $null
    }

    if ($runningServices -notcontains 'qbittorrent') {
        Write-Host 'qBittorrent is not running; plugin check skipped.'
        return $null
    }
    $pluginCheck = docker compose exec -T qbittorrent sh -lc "if [ -s /config/qBittorrent/nova3/engines/jackett.py ] && [ -s /config/qBittorrent/nova3/engines/jackett.json ]; then echo OK; else echo MISSING; fi" 2>$null
    if ($pluginCheck -contains 'OK') {
        Write-Host 'Jackett plugin files present: /config/qBittorrent/nova3/engines/jackett.py and jackett.json'
        return $true
    } else {
        Write-Warning 'Jackett plugin files missing in qBittorrent container (/config/qBittorrent/nova3/engines).'
        Write-Host 'Run: pwsh ./scripts/torrents-stack.ps1 restart'
        return $false
    }
}

function Get-TerminalHyperlink {
    param(
        [string]$Text,
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Url)) {
        return $Text
    }

    $esc = [char]27
    return "${esc}]8;;$Url${esc}\$Text${esc}]8;;${esc}\"
}

function ConvertTo-ProgressRow {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $trimmed = $Line.Trim()
    if ($trimmed -match '^(?<kind>Image|Layer|Container|Network|Volume)\s+(?<id>\S+)\s+(?<status>.+?)\s*$') {
        return [pscustomobject]@{
            Kind   = $matches.kind
            Id     = $matches.id
            Status = $matches.status.Trim()
            Detail = ''
        }
    }

    if ($trimmed -match '^(?<id>[A-Za-z0-9][A-Za-z0-9._:/-]*)\s+(?<status>Pulling fs layer|Waiting|Downloading|Download complete|Extracting|Pull complete|Already exists|Mounted from|Verifying Checksum|Pushed|Layer already exists|Complete)(?<detail>.*)$') {
        return [pscustomobject]@{
            Kind   = 'Layer'
            Id     = $matches.id
            Status = $matches.status.Trim()
            Detail = $matches.detail.Trim()
        }
    }

    return $null
}

function Show-ProgressSnapshotTable {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Rows,
        [string]$Title,
        [TimeSpan]$Elapsed
    )

    Invoke-SafeClearHost
    Write-Host ("[{0}] Elapsed: {1}" -f $Title, $Elapsed.ToString('hh\:mm\:ss')) -ForegroundColor Cyan
    Write-Host ("{0,-10} {1,-28} {2,-20} {3}" -f 'Kind', 'Identifier', 'Status', 'Detail') -ForegroundColor Yellow
    Write-Host ("{0,-10} {1,-28} {2,-20} {3}" -f '----', '----------', '------', '------') -ForegroundColor Yellow

    foreach ($row in $Rows.Values) {
        $color = switch -Regex ($row.Status) {
            'healthy|started|created|complete|already exists|mounted from|pushed' { 'Green' }
            'starting|creating|pulling|extracting|downloading|waiting|verifying' { 'Yellow' }
            'unhealthy|error|failed|fatal' { 'Red' }
            default { 'White' }
        }
        Write-Host ("{0,-10} {1,-28} {2,-20} {3}" -f $row.Kind, $row.Id, $row.Status, $row.Detail) -ForegroundColor $color
    }

    Write-Host ("`nTracked items: {0}" -f $Rows.Count) -ForegroundColor Gray
}

<#+
.SYNOPSIS
    Show Docker image pull progress as a dynamic table.
.DESCRIPTION
    Runs a docker pull or docker compose pull command, parses layer status, and displays a refreshing table.
.PARAMETER Command
    The docker command to run (default: 'docker compose pull').
.EXAMPLE
    Show-DockerPullProgress -Command 'docker compose pull'
#>
function Show-DockerProgressTable {
    param(
        [string]$Command = "docker compose pull"
    )
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $tmpErrFile = [System.IO.Path]::GetTempFileName()
    $logDir = Join-Path $PSScriptRoot '..' 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir ("docker-progress-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
    $allProgressLines = @()
    $progressRows = [ordered]@{}
    try {
        $proc = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", $Command -RedirectStandardOutput $tmpFile -RedirectStandardError $tmpErrFile -NoNewWindow -PassThru
        $startTime = Get-Date
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500
            if ((Test-Path $tmpFile) -or (Test-Path $tmpErrFile)) {
                $stdoutLines = if (Test-Path $tmpFile) { @(Get-Content $tmpFile) } else { @() }
                $stderrLines = if (Test-Path $tmpErrFile) { @(Get-Content $tmpErrFile) } else { @() }
                $lines = @($stdoutLines + $stderrLines)
                $allProgressLines += $lines
                foreach ($line in $lines) {
                    $progressRow = ConvertTo-ProgressRow -Line $line
                    if ($null -ne $progressRow) {
                        $key = "{0}:{1}" -f $progressRow.Kind, $progressRow.Id
                        $progressRows[$key] = $progressRow
                    }
                }
                $elapsed = (Get-Date) - $startTime
                if ($progressRows.Count -gt 0) {
                    Show-ProgressSnapshotTable -Rows $progressRows -Title ("Docker Progress: {0}" -f $Command) -Elapsed $elapsed
                }
                else {
                    Invoke-SafeClearHost
                    Write-Host ("[Docker Progress] $Command | Elapsed: {0}" -f $elapsed.ToString("hh\:mm\:ss")) -ForegroundColor Cyan
                    Write-Host 'Waiting for structured progress output...' -ForegroundColor Gray
                }
            }
        }
        # Print any remaining output
        $stdoutLines = if (Test-Path $tmpFile) { @(Get-Content $tmpFile) } else { @() }
        $stderrLines = if (Test-Path $tmpErrFile) { @(Get-Content $tmpErrFile) } else { @() }
        $lines = @($stdoutLines + $stderrLines)
        $allProgressLines += $lines
        foreach ($line in $lines) {
            $progressRow = ConvertTo-ProgressRow -Line $line
            if ($null -ne $progressRow) {
                $key = "{0}:{1}" -f $progressRow.Kind, $progressRow.Id
                $progressRows[$key] = $progressRow
            }
        }
        $proc.WaitForExit()
        # Write all progress lines to log file
        $allProgressLines | Set-Content $logFile
        # Final summary
        $elapsed = (Get-Date) - $startTime
        if ($progressRows.Count -gt 0) {
            Show-ProgressSnapshotTable -Rows $progressRows -Title ("Docker Progress: {0}" -f $Command) -Elapsed $elapsed
        }
        Write-Host ("`n[Docker Progress Complete] {0}" -f $Command) -ForegroundColor Cyan
        Write-Host ("Elapsed time: {0}" -f $elapsed.ToString("hh\:mm\:ss")) -ForegroundColor Yellow
        Write-Host ("Progress log saved to: {0}" -f $logFile) -ForegroundColor Gray
    } finally {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
        if (Test-Path $tmpErrFile) { Remove-Item $tmpErrFile -Force }
    }
}

# Alias for backward compatibility
function Show-DockerPullProgress {
    param([string]$Command = "docker compose pull")
    Show-DockerProgressTable -Command $Command
}

# Show-CommandProgressTable: Generic live progress for any long-running command
function Show-CommandProgressTable {
    param(
        [string]$Command,
        [string]$LogPrefix = "command-progress"
    )
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $tmpErrFile = [System.IO.Path]::GetTempFileName()
    $logDir = Join-Path $PSScriptRoot '..' 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir ("${LogPrefix}-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
    $allLines = @()
    $progressRows = [ordered]@{}
    $startTime = Get-Date
    try {
        $proc = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-Command", $Command -RedirectStandardOutput $tmpFile -RedirectStandardError $tmpErrFile -NoNewWindow -PassThru
        $lastLine = 0
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500
            if ((Test-Path $tmpFile) -or (Test-Path $tmpErrFile)) {
                $stdoutLines = if (Test-Path $tmpFile) { @(Get-Content $tmpFile) } else { @() }
                $stderrLines = if (Test-Path $tmpErrFile) { @(Get-Content $tmpErrFile) } else { @() }
                $lines = @($stdoutLines + $stderrLines)
                $allLines += $lines
                foreach ($line in $lines) {
                    $progressRow = ConvertTo-ProgressRow -Line $line
                    if ($null -ne $progressRow) {
                        $key = "{0}:{1}" -f $progressRow.Kind, $progressRow.Id
                        $progressRows[$key] = $progressRow
                    }
                }
                $elapsed = (Get-Date) - $startTime
                if ($progressRows.Count -gt 0) {
                    Show-ProgressSnapshotTable -Rows $progressRows -Title ("Command Progress: {0}" -f $Command) -Elapsed $elapsed
                }
                else {
                    Invoke-SafeClearHost
                    Write-Host ("[Command Progress] $Command | Elapsed: {0}" -f $elapsed.ToString("hh\:mm\:ss")) -ForegroundColor Cyan
                    ($lines | Select-Object -Last 20) | ForEach-Object { Write-Host $_ }
                }
                $lastLine = ($lines | Measure-Object).Count
            }
        }
        # Print any remaining output
        $stdoutLines = if (Test-Path $tmpFile) { @(Get-Content $tmpFile) } else { @() }
        $stderrLines = if (Test-Path $tmpErrFile) { @(Get-Content $tmpErrFile) } else { @() }
        $lines = @($stdoutLines + $stderrLines)
        if ($lines.Count -gt 0) {
            $left = $lines | Select-Object -Skip $lastLine
            foreach ($line in $left) { Write-Host $line }
            $allLines += $lines
            foreach ($line in $lines) {
                $progressRow = ConvertTo-ProgressRow -Line $line
                if ($null -ne $progressRow) {
                    $key = "{0}:{1}" -f $progressRow.Kind, $progressRow.Id
                    $progressRows[$key] = $progressRow
                }
            }
        }
        $proc.WaitForExit()
        # Write all lines to log file
        $allLines | Set-Content $logFile
        $elapsed = (Get-Date) - $startTime
        if ($progressRows.Count -gt 0) {
            Show-ProgressSnapshotTable -Rows $progressRows -Title ("Command Progress: {0}" -f $Command) -Elapsed $elapsed
        }
        Write-Host ("`n[Command Complete] {0}" -f $Command) -ForegroundColor Cyan
        Write-Host ("Elapsed time: {0}" -f $elapsed.ToString("hh\:mm\:ss")) -ForegroundColor Yellow
        Write-Host ("Progress log saved to: {0}" -f $logFile) -ForegroundColor Gray
    } finally {
        if (Test-Path $tmpFile) {
            try {
                Remove-Item $tmpFile -Force -ErrorAction Stop
            } catch {
                Write-Host ("[Warning] Could not remove temp file: {0}" -f $tmpFile) -ForegroundColor Yellow
            }
        }
        if (Test-Path $tmpErrFile) {
            try {
                Remove-Item $tmpErrFile -Force -ErrorAction Stop
            } catch {
                Write-Host ("[Warning] Could not remove temp file: {0}" -f $tmpErrFile) -ForegroundColor Yellow
            }
        }
    }
}
