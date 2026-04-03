# Generate Markdown dashboard of service health and recent logs

$services = @('expressvpn','flaresolverr','jackett','qbittorrent')
$statuses = @{}
$logs = @{}

foreach ($svc in $services) {
    $inspect = docker inspect --format='{{.State.Health.Status}}' $svc 2>$null
    $statuses[$svc] = if ($LASTEXITCODE -eq 0) { $inspect } else { 'not found' }
    $logs[$svc] = docker logs --tail 10 $svc 2>&1
}

$md = "# Service Health Dashboard

| Service      | Status      |
|--------------|-------------|
"
foreach ($svc in $services) {
    $md += "| $svc | $($statuses[$svc]) |
"
}
$md += "\n## Recent Logs\n"
foreach ($svc in $services) {
    $md += "### $svc\n```
$($logs[$svc])
```
"
}
$md | Set-Content "$PSScriptRoot/../service-health-dashboard.md"
Write-Host "[Dashboard] service-health-dashboard.md generated." -ForegroundColor Green
