# Usage metrics (opt-in)
$metricsFile = "$PSScriptRoot/../usage-metrics.log"
if ($env:STACK_USAGE_METRICS -eq '1') {
    $entry = "$(Get-Date -Format 'u') $($MyInvocation.MyCommand.Name) $($args -join ' ')"
    Add-Content -Path $metricsFile -Value $entry
}
