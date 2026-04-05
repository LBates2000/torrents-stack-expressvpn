# Pester tests for shared-functions.ps1

Describe "Write-ProgressLine" {
    BeforeAll {
        . "$PSScriptRoot/../scripts/shared-functions.ps1"
    }

    It "Should write output without error in non-interactive session" {
        Write-ProgressLine "Test message" -Color Yellow
    }
}

Describe "Compose service state helpers" {
    BeforeAll {
        . "$PSScriptRoot/../scripts/shared-functions.ps1"
    }

    AfterEach {
        if (Test-Path Function:\global:docker) {
            Remove-Item Function:\global:docker -Force
        }
    }

    It "Returns not found when docker inspect fails" {
        function global:docker {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $global:LASTEXITCODE = 1
        }

        $state = Get-ComposeServiceState -ServiceName 'qbittorrent'

        if ($state.Exists -ne $false) {
            throw "Exists flag mismatch. Expected 'False', got '$($state.Exists)'."
        }
        if ($state.DisplayStatus -ne 'not found') {
            throw "DisplayStatus mismatch. Expected 'not found', got '$($state.DisplayStatus)'."
        }
    }

    It "Falls back to lifecycle status when health is unavailable" {
        function global:docker {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $global:LASTEXITCODE = 0
            'created||123456789abc'
        }

        $state = Get-ComposeServiceState -ServiceName 'qbittorrent'
        $healthMap = Get-ComposeServiceHealthMap -ServiceNames @('qbittorrent')

        if ($state.Exists -ne $true) {
            throw "Exists flag mismatch. Expected 'True', got '$($state.Exists)'."
        }
        if ($state.Lifecycle -ne 'created') {
            throw "Lifecycle mismatch. Expected 'created', got '$($state.Lifecycle)'."
        }
        if ($state.Health -ne '') {
            throw "Health mismatch. Expected empty string, got '$($state.Health)'."
        }
        if ($healthMap['qbittorrent'] -ne 'created') {
            throw "Health map mismatch. Expected 'created', got '$($healthMap['qbittorrent'])'."
        }
    }
}
