# Pester tests for shared-functions.ps1

Import-Module "$PSScriptRoot/../scripts/shared-functions.ps1"

$pesterModule = Get-Module -Name Pester
$useModernShouldSyntax = $pesterModule -and $pesterModule.Version.Major -ge 5

Describe "Write-ProgressLine" {
    It "Should write output without error in non-interactive session" {
        $action = { Write-ProgressLine "Test message" -Color Yellow }
        if ($useModernShouldSyntax) {
            $action | Should -Not -Throw
        } else {
            $action | Should Not Throw
        }
    }
}
