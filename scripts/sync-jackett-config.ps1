param(
    [switch]$SkipRestart,
    [switch]$EmitStatus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import shared utility functions
. "$PSScriptRoot/shared-functions.ps1"

<#
.SYNOPSIS
    Convert null or empty tokens to $null.

.DESCRIPTION
    Normalizes string representations of null or empty values. Used for configuration
    values that should be unset/empty in Jackett config.

.PARAMETER Value
    Input string to convert.

.OUTPUTS
    [string] or [null]
#>
function Convert-NullToken {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -eq '' -or $Value -eq 'null') { return $null }
    return $Value
}


<#
.SYNOPSIS
    Convert and validate configuration values.

.DESCRIPTION
    Converts string values from .env to the appropriate type (string, int, bool)
    while handling null/empty tokens consistently.

.PARAMETER Value
    Raw environment variable value.

.PARAMETER Kind
    Target type: 'string', 'int', or 'bool'

.OUTPUTS
    Converted value in the requested type, or $null if value represents null.
#>
function Convert-EnvValue {
    param(
        [string]$Value,
        [ValidateSet('string', 'int', 'bool')]
        [string]$Kind
    )

    $normalizedValue = Convert-NullToken -Value $Value
    if ($null -eq $normalizedValue) {
        return $null
    }

    switch ($Kind) {
        'string' { return $normalizedValue }
        'int' { return [int]$normalizedValue }
        'bool' { return [System.Convert]::ToBoolean($normalizedValue) }
    }
}

$stackContext = Get-StackContext -ScriptRoot $PSScriptRoot

if (-not (Test-Path -LiteralPath $stackContext.EnvPath)) {
    throw "Missing .env file at $($stackContext.EnvPath)"
}

$repoRoot = $stackContext.RepoRoot
$envMap = $stackContext.EnvMap
$configsRoot = $stackContext.ConfigsRoot
$downloadsRoot = $stackContext.DownloadsRoot
$jackettConfigDir = Join-Path $configsRoot 'Jackett'
$configPath = Join-Path $jackettConfigDir 'ServerConfig.json'

New-DirectoryIfMissing -Path $jackettConfigDir
New-DirectoryIfMissing -Path (Join-Path $downloadsRoot 'watch')

$downloadsBase = Convert-PathPrefix -PathValue $envMap['CONTAINER_DOWNLOADS_DIR']
$defaultBlackholeDir = "$downloadsBase/watch"

$propertyMappings = @(
    @{ Property = 'Port'; Env = 'JACKETT_CFG_PORT'; Default = '9117'; Kind = 'int' },
    @{ Property = 'LocalBindAddress'; Env = 'JACKETT_CFG_LOCAL_BIND_ADDRESS'; Default = '127.0.0.1'; Kind = 'string' },
    @{ Property = 'AllowExternal'; Env = 'JACKETT_CFG_ALLOW_EXTERNAL'; Default = 'true'; Kind = 'bool' },
    @{ Property = 'AllowCORS'; Env = 'JACKETT_CFG_ALLOW_CORS'; Default = 'false'; Kind = 'bool' },
    @{ Property = 'APIKey'; Env = 'JACKETT_CFG_API_KEY'; Default = 'null'; Kind = 'string' },
    @{ Property = 'InstanceId'; Env = 'JACKETT_CFG_INSTANCE_ID'; Default = 'null'; Kind = 'string' },
    @{ Property = 'BlackholeDir'; Env = 'JACKETT_CFG_BLACKHOLE_DIR'; Default = $defaultBlackholeDir; Kind = 'string' },
    @{ Property = 'UpdateDisabled'; Env = 'JACKETT_CFG_UPDATE_DISABLED'; Default = 'false'; Kind = 'bool' },
    @{ Property = 'UpdatePrerelease'; Env = 'JACKETT_CFG_UPDATE_PRERELEASE'; Default = 'false'; Kind = 'bool' },
    @{ Property = 'BasePathOverride'; Env = 'JACKETT_CFG_BASE_PATH_OVERRIDE'; Default = 'null'; Kind = 'string' },
    @{ Property = 'BaseUrlOverride'; Env = 'JACKETT_CFG_BASE_URL_OVERRIDE'; Default = 'null'; Kind = 'string' },
    @{ Property = 'CacheEnabled'; Env = 'JACKETT_CFG_CACHE_ENABLED'; Default = 'true'; Kind = 'bool' },
    @{ Property = 'CacheTtl'; Env = 'JACKETT_CFG_CACHE_TTL'; Default = '2100'; Kind = 'int' },
    @{ Property = 'CacheMaxResultsPerIndexer'; Env = 'JACKETT_CFG_CACHE_MAX_RESULTS_PER_INDEXER'; Default = '1000'; Kind = 'int' },
    @{ Property = 'FlareSolverrUrl'; Env = 'JACKETT_CFG_FLARESOLVERR_URL'; Default = 'http://flaresolverr:8191'; Kind = 'string' },
    @{ Property = 'FlareSolverrMaxTimeout'; Env = 'JACKETT_CFG_FLARESOLVERR_MAX_TIMEOUT'; Default = '55000'; Kind = 'int' },
    @{ Property = 'OmdbApiKey'; Env = 'JACKETT_CFG_OMDB_API_KEY'; Default = 'null'; Kind = 'string' },
    @{ Property = 'OmdbApiUrl'; Env = 'JACKETT_CFG_OMDB_API_URL'; Default = 'https://www.omdbapi.com/'; Kind = 'string' },
    @{ Property = 'ProxyType'; Env = 'JACKETT_CFG_PROXY_TYPE'; Default = '0'; Kind = 'int' },
    @{ Property = 'ProxyUrl'; Env = 'JACKETT_CFG_PROXY_URL'; Default = 'null'; Kind = 'string' },
    @{ Property = 'ProxyPort'; Env = 'JACKETT_CFG_PROXY_PORT'; Default = 'null'; Kind = 'int' },
    @{ Property = 'ProxyUsername'; Env = 'JACKETT_CFG_PROXY_USERNAME'; Default = 'null'; Kind = 'string' },
    @{ Property = 'ProxyPassword'; Env = 'JACKETT_CFG_PROXY_PASSWORD'; Default = 'null'; Kind = 'string' },
    @{ Property = 'ProxyIsAnonymous'; Env = 'JACKETT_CFG_PROXY_IS_ANONYMOUS'; Default = 'true'; Kind = 'bool' }
)

$originalJson = '{}'
if (Test-Path -LiteralPath $configPath) {
    $originalJson = Get-Content -LiteralPath $configPath -Raw
}

$config = [ordered]@{}
if (-not [string]::IsNullOrWhiteSpace($originalJson)) {
    $config = $originalJson | ConvertFrom-Json -AsHashtable
}

foreach ($mapping in $propertyMappings) {
    $rawValue = Get-EnvOrDefault -EnvMap $envMap -Key $mapping.Env -DefaultValue $mapping.Default
    $config[$mapping.Property] = Convert-EnvValue -Value $rawValue -Kind $mapping.Kind
}

$rawAdminPassword = Get-EnvOrDefault -EnvMap $envMap -Key 'JACKETT_CFG_ADMIN_PASSWORD' -DefaultValue 'null'
$adminPassword = Convert-EnvValue -Value $rawAdminPassword -Kind 'string'

if ($null -eq $adminPassword) {
    $config['AdminPassword'] = $null
}
else {
    $apiKey = $config['APIKey']
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'JACKETT_CFG_ADMIN_PASSWORD requires JACKETT_CFG_API_KEY to be set to a stable non-empty value in .env so the Jackett config hash can be generated.'
    }

    $config['AdminPassword'] = Get-JackettAdminPasswordHash -Password $adminPassword -ApiKey $apiKey
}

$json = $config | ConvertTo-Json -Depth 10
$updatedJson = $json + [Environment]::NewLine
$hasChanges = $originalJson -ne $updatedJson

if ($hasChanges) {
    [System.IO.File]::WriteAllText($configPath, $updatedJson)
}

if ($hasChanges -and -not $SkipRestart) {
    Restart-ComposeServiceIfRunning -RepoRoot $repoRoot -ServiceName 'jackett' -RestartMessage 'Restarted jackett to apply config changes' -NotRunningMessage 'Config updated; jackett not running, so restart was not needed' | Out-Null
}

if (-not $hasChanges) {
    Write-Host 'No Jackett config changes were needed'
}
elseif ($SkipRestart) {
    Write-Host 'Updated Jackett ServerConfig from .env (restart skipped)'
}
elseif ($hasChanges) {
    Write-Host 'Updated Jackett ServerConfig from .env'
}
Write-Host 'APIKey=<redacted>'
Write-Host 'InstanceId=<redacted>'
Write-Host "BlackholeDir=$($config['BlackholeDir'])"
Write-Host 'OmdbApiKey=<redacted>'
Write-Host "OmdbApiUrl=$($config['OmdbApiUrl'])"
Write-Host "FlareSolverrUrl=$($config['FlareSolverrUrl'])"

if ($EmitStatus) {
    Write-Output ("SYNC_STATUS:jackett:{0}" -f $hasChanges.ToString().ToLowerInvariant())
}