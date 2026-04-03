function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO',
        [string]$LogFile = ''
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        'ERROR' { $color = 'Red' }
        'WARN'  { $color = 'Yellow' }
        'DEBUG' { $color = 'Magenta' }
        default { $color = 'White' }
    }
    Write-Host $line -ForegroundColor $color
    if ($LogFile) { Add-Content -Path $LogFile -Value $line }
}
