#!/usr/bin/env pwsh

# Test lines from actual docker output
$testLines = @(
    ' 11c392bc4fb7 Pulling fs layer 0B',
    ' 75ad9a0f5ec5 Downloading 1.049MB',
    ' 75ad9a0f5ec5 Downloading 1.049MB',
    ' 11c392bc4fb7 Downloading 405B',
    ' 75ad9a0f5ec5 Download complete',
    ' 11c392bc4fb7 Pull complete'
)

$regex = '^\s*(?<id>[a-f0-9]{12,})\s*(?::\s*|\s+)(?<status>Downloading|Extracting|Verifying Checksum|Pull complete|Waiting|Download complete|Already exists|Preparing|Pushing|Pushed|Layer already exists|Mounted(?: from .+)?|Pulling fs layer|Digest:|Status:|Error:|.+?)\s*(?:\[(?<bar>[^\]]+)\])?\s*(?<current>[0-9\.]+[kMGT]?B)?(?:\/(?<total>[0-9\.]+[kMGT]?B))?'

Write-Host "Testing regex pattern:"
Write-Host "Pattern: $regex`n"

foreach ($line in $testLines) {
    if ($line -match $regex) {
        Write-Host "✓ MATCH - ID: $($matches['id']), Status: $($matches['status']), Current: $($matches['current'])" -ForegroundColor Green
    } else {
        Write-Host "✗ NO MATCH - Line: $line" -ForegroundColor Red
    }
}
