#!/usr/bin/env pwsh
try {
    $content = Get-Content -Path scripts/shared-functions.ps1 -Raw
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host "PARSE ERRORS FOUND: $($errors.Count)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  Line $($_.Token.StartLine): $($_.Message)" }
        exit 1
    } else {
        Write-Host "✓ shared-functions.ps1 has valid PowerShell syntax" -ForegroundColor Green
        exit 0
    }
} catch {
    Write-Host "Error checking syntax: $_" -ForegroundColor Red
    exit 1
}
