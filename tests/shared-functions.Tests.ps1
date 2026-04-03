# Pester tests for shared-functions.ps1

Import-Module "$PSScriptRoot/../scripts/shared-functions.ps1"

Describe "Write-ProgressLine" {
    It "Should write output without error in non-interactive session" {
        Write-ProgressLine "Test message" -Color Yellow
    }
}
