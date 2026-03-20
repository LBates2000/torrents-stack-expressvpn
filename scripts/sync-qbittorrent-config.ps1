param(
    [switch]$SkipRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EnvMap {
    param([string]$Path)

    $map = @{}
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

function Set-IniSetting {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    $sectionHeader = "[$Section]"
    $sectionStart = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -eq $sectionHeader) {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1] -ne '') {
            $Lines.Add('')
        }
        $Lines.Add($sectionHeader)
        $Lines.Add("$Key=$Value")
        return
    }

    $sectionEnd = $Lines.Count
    for ($i = $sectionStart + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\[') {
            $sectionEnd = $i
            break
        }
    }

    $pattern = '^{0}=' -f [regex]::Escape($Key)
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($Lines[$i] -match $pattern) {
            $Lines[$i] = "$Key=$Value"
            return
        }
    }

    $Lines.Insert($sectionEnd, "$Key=$Value")
}

function Get-JsonFromEnv {
    param(
        [hashtable]$EnvMap,
        [string]$Key,
        [object]$DefaultObject
    )

    if (-not $EnvMap.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($EnvMap[$Key])) {
        return $DefaultObject
    }

    $raw = $EnvMap[$Key]
    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON for $Key. Value: $raw"
    }
}

function Normalize-PathPrefix {
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

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-File {
    param(
        [string]$Path,
        [string]$DefaultContent = ''
    )

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        Ensure-Directory -Path $parentPath
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        [System.IO.File]::WriteAllText($Path, $DefaultContent)
    }
}

function Get-EnvOrDefault {
    param(
        [hashtable]$EnvMap,
        [string]$Key,
        [string]$DefaultValue
    )

    if ($EnvMap.ContainsKey($Key)) {
        return $EnvMap[$Key]
    }

    return $DefaultValue
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot '.env'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing .env file at $envPath"
}

$envMap = Get-EnvMap -Path $envPath

$configsRoot = Resolve-HostPath -RepoRoot $repoRoot -ConfiguredPath $envMap['HOST_CONFIGS_DIR'] -DefaultRelativePath './configs'
$downloadsRoot = Resolve-HostPath -RepoRoot $repoRoot -ConfiguredPath $envMap['HOST_DOWNLOADS_DIR'] -DefaultRelativePath './downloads'
$qbittorrentConfigDir = Join-Path $configsRoot 'qBittorrent'
$configPath = Join-Path $qbittorrentConfigDir 'qBittorrent.conf'
$categoriesPath = Join-Path $qbittorrentConfigDir 'categories.json'
$watchedFoldersPath = Join-Path $qbittorrentConfigDir 'watched_folders.json'

$mappings = @(
    @{ Section = 'AutoRun'; Key = 'enabled'; Env = 'QBITTORRENT_CFG_AUTORUN_ENABLED'; Default = 'false' },
    @{ Section = 'AutoRun'; Key = 'program'; Env = 'QBITTORRENT_CFG_AUTORUN_PROGRAM'; Default = '' },
    @{ Section = 'BitTorrent'; Key = 'Session\AddTorrentStopped'; Env = 'QBITTORRENT_CFG_SESSION_ADD_TORRENT_STOPPED'; Default = 'false' },
    @{ Section = 'BitTorrent'; Key = 'Session\DefaultSavePath'; Env = 'QBITTORRENT_CFG_SESSION_DEFAULT_SAVE_PATH'; Default = '/downloads/' },
    @{ Section = 'BitTorrent'; Key = 'Session\Port'; Env = 'QBITTORRENT_CFG_SESSION_PORT'; Default = '6881' },
    @{ Section = 'BitTorrent'; Key = 'Session\QueueingSystemEnabled'; Env = 'QBITTORRENT_CFG_SESSION_QUEUEING_SYSTEM_ENABLED'; Default = 'true' },
    @{ Section = 'BitTorrent'; Key = 'Session\SSL\Port'; Env = 'QBITTORRENT_CFG_SESSION_SSL_PORT'; Default = '4981' },
    @{ Section = 'BitTorrent'; Key = 'Session\ShareLimitAction'; Env = 'QBITTORRENT_CFG_SESSION_SHARE_LIMIT_ACTION'; Default = 'Stop' },
    @{ Section = 'BitTorrent'; Key = 'Session\TempPath'; Env = 'QBITTORRENT_CFG_SESSION_TEMP_PATH'; Default = '/downloads/incomplete/' },
    @{ Section = 'LegalNotice'; Key = 'Accepted'; Env = 'QBITTORRENT_CFG_LEGAL_NOTICE_ACCEPTED'; Default = 'true' },
    @{ Section = 'Meta'; Key = 'MigrationVersion'; Env = 'QBITTORRENT_CFG_META_MIGRATION_VERSION'; Default = '8' },
    @{ Section = 'Network'; Key = 'Cookies'; Env = 'QBITTORRENT_CFG_NETWORK_COOKIES'; Default = '@Invalid()' },
    @{ Section = 'Network'; Key = 'PortForwardingEnabled'; Env = 'QBITTORRENT_CFG_NETWORK_PORT_FORWARDING_ENABLED'; Default = 'false' },
    @{ Section = 'Network'; Key = 'Proxy\HostnameLookupEnabled'; Env = 'QBITTORRENT_CFG_PROXY_HOSTNAME_LOOKUP_ENABLED'; Default = 'false' },
    @{ Section = 'Network'; Key = 'Proxy\Profiles\BitTorrent'; Env = 'QBITTORRENT_CFG_PROXY_PROFILE_BITTORRENT'; Default = 'true' },
    @{ Section = 'Network'; Key = 'Proxy\Profiles\Misc'; Env = 'QBITTORRENT_CFG_PROXY_PROFILE_MISC'; Default = 'true' },
    @{ Section = 'Network'; Key = 'Proxy\Profiles\RSS'; Env = 'QBITTORRENT_CFG_PROXY_PROFILE_RSS'; Default = 'true' },
    @{ Section = 'Preferences'; Key = 'Connection\PortRangeMin'; Env = 'QBITTORRENT_CFG_CONNECTION_PORT_RANGE_MIN'; Default = '6881' },
    @{ Section = 'Preferences'; Key = 'Connection\UPnP'; Env = 'QBITTORRENT_CFG_CONNECTION_UPNP'; Default = 'false' },
    @{ Section = 'Preferences'; Key = 'Downloads\SavePath'; Env = 'QBITTORRENT_CFG_DOWNLOADS_SAVE_PATH'; Default = '/downloads/' },
    @{ Section = 'Preferences'; Key = 'Downloads\TempPath'; Env = 'QBITTORRENT_CFG_DOWNLOADS_TEMP_PATH'; Default = '/downloads/incomplete/' },
    @{ Section = 'Preferences'; Key = 'WebUI\Address'; Env = 'QBITTORRENT_CFG_WEBUI_ADDRESS'; Default = '*' },
    @{ Section = 'Preferences'; Key = 'WebUI\ServerDomains'; Env = 'QBITTORRENT_CFG_WEBUI_SERVER_DOMAINS'; Default = '*' }
)

$downloadsBase = Normalize-PathPrefix -PathValue ($envMap['QBITTORRENT_CFG_DOWNLOADS_SAVE_PATH'])
$watchBase = "$downloadsBase/watch"

$defaultCategoriesObject = [ordered]@{
    movies = [ordered]@{ save_path = "$downloadsBase/movies" }
    tv = [ordered]@{ save_path = "$downloadsBase/tv" }
}

$defaultWatchedFoldersObject = [ordered]@{
    "$watchBase/movies" = [ordered]@{
        save_path = "$downloadsBase/movies"
        category = 'movies'
        recursive = $true
    }
    "$watchBase/tv" = [ordered]@{
        save_path = "$downloadsBase/tv"
        category = 'tv_shows'
        recursive = $true
    }
}

$seedLines = [System.Collections.Generic.List[string]]::new()
foreach ($mapping in $mappings) {
    $seedValue = Get-EnvOrDefault -EnvMap $envMap -Key $mapping.Env -DefaultValue $mapping.Default
    Set-IniSetting -Lines $seedLines -Section $mapping.Section -Key $mapping.Key -Value $seedValue
}

$seedConfigContent = ([string]::Join([Environment]::NewLine, $seedLines.ToArray())) + [Environment]::NewLine
$seedCategoriesContent = ($defaultCategoriesObject | ConvertTo-Json -Depth 20) + [Environment]::NewLine
$seedWatchedFoldersContent = ($defaultWatchedFoldersObject | ConvertTo-Json -Depth 20) + [Environment]::NewLine

Ensure-Directory -Path $qbittorrentConfigDir
Ensure-Directory -Path (Join-Path $qbittorrentConfigDir 'logs')
Ensure-Directory -Path (Join-Path $qbittorrentConfigDir 'BT_backup')
Ensure-Directory -Path (Join-Path $qbittorrentConfigDir 'rss')
Ensure-Directory -Path (Join-Path $qbittorrentConfigDir 'rss/articles')
Ensure-Directory -Path (Join-Path $qbittorrentConfigDir 'GeoDB')
Ensure-Directory -Path $downloadsRoot
Ensure-Directory -Path (Join-Path $downloadsRoot 'watch')
Ensure-Directory -Path (Join-Path $downloadsRoot 'watch/movies')
Ensure-Directory -Path (Join-Path $downloadsRoot 'watch/tv')
Ensure-Directory -Path (Join-Path $downloadsRoot 'incomplete')
Ensure-File -Path $configPath -DefaultContent $seedConfigContent
Ensure-File -Path $categoriesPath -DefaultContent $seedCategoriesContent
Ensure-File -Path $watchedFoldersPath -DefaultContent $seedWatchedFoldersContent

$originalLines = @(Get-Content -LiteralPath $configPath)
$lineList = [System.Collections.Generic.List[string]]::new()
foreach ($line in $originalLines) {
    $lineList.Add([string]$line)
}

foreach ($m in $mappings) {
    $value = Get-EnvOrDefault -EnvMap $envMap -Key $m.Env -DefaultValue $m.Default
    Set-IniSetting -Lines $lineList -Section $m.Section -Key $m.Key -Value $value
}

$updatedLines = $lineList.ToArray()
$hasChanges = $false
if ($originalLines.Count -ne $updatedLines.Count) {
    $hasChanges = $true
}
else {
    for ($i = 0; $i -lt $originalLines.Count; $i++) {
        if ($originalLines[$i] -ne $updatedLines[$i]) {
            $hasChanges = $true
            break
        }
    }
}

if ($hasChanges) {
    [System.IO.File]::WriteAllLines($configPath, $updatedLines)
}

$categoriesObject = Get-JsonFromEnv -EnvMap $envMap -Key 'QBITTORRENT_CFG_CATEGORIES_JSON' -DefaultObject $defaultCategoriesObject
$categoriesUpdatedJson = ($categoriesObject | ConvertTo-Json -Depth 20) + [Environment]::NewLine
$categoriesOriginalJson = Get-Content -LiteralPath $categoriesPath -Raw
$categoriesChanged = $categoriesOriginalJson -ne $categoriesUpdatedJson
if ($categoriesChanged) {
    [System.IO.File]::WriteAllText($categoriesPath, $categoriesUpdatedJson)
}

$watchedFoldersObject = Get-JsonFromEnv -EnvMap $envMap -Key 'QBITTORRENT_CFG_WATCHED_FOLDERS_JSON' -DefaultObject $defaultWatchedFoldersObject
$watchedFoldersUpdatedJson = ($watchedFoldersObject | ConvertTo-Json -Depth 20) + [Environment]::NewLine
$watchedFoldersOriginalJson = Get-Content -LiteralPath $watchedFoldersPath -Raw
$watchedFoldersChanged = $watchedFoldersOriginalJson -ne $watchedFoldersUpdatedJson
if ($watchedFoldersChanged) {
    [System.IO.File]::WriteAllText($watchedFoldersPath, $watchedFoldersUpdatedJson)
}

$anyChanges = $hasChanges -or $categoriesChanged -or $watchedFoldersChanged

if ($anyChanges -and -not $SkipRestart) {
    Push-Location $repoRoot
    try {
        $runningServices = @(docker compose ps --status running --services)
        if ($runningServices -contains 'qbittorrent') {
            docker compose stop qbittorrent | Out-Host
            docker compose start qbittorrent | Out-Host
            Write-Host 'Restarted qbittorrent to apply config changes'
        }
        else {
            Write-Host 'Config updated; qbittorrent not running, so restart was not needed'
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $anyChanges) {
    Write-Host 'No qBittorrent config changes were needed'
}
elseif ($SkipRestart) {
    Write-Host 'Updated qBittorrent config from .env (restart skipped)'
}
elseif ($anyChanges) {
    Write-Host 'Updated qBittorrent config from .env'
}

Write-Host "qBittorrent.conf changed: $hasChanges"
Write-Host "categories.json changed: $categoriesChanged"
Write-Host "watched_folders.json changed: $watchedFoldersChanged"