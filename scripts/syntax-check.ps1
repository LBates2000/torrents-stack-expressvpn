#!/usr/bin/env pwsh
# Quick syntax check
try {
    . (Join-Path $PSScriptRoot 'shared-functions.ps1')
    Write-Host "✓ shared-functions.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "✗ Error: $_" -ForegroundColor Red
    exit 1
}
