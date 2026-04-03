#!/usr/bin/env pwsh

try {
    . (Join-Path $PSScriptRoot 'shared-functions.ps1')
    Write-Host "✓ shared-functions.ps1 loaded successfully" -ForegroundColor Green
    Write-Host "Functions defined:"
    Get-Command -CommandType Function | Where-Object { $_.Source -like '*shared-functions*' } | Select-Object -ExpandProperty Name
} catch {
    Write-Host "✗ Error loading shared-functions.ps1: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
