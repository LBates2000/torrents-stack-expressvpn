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

        $state.Exists | Should Be $false
        $state.DisplayStatus | Should Be 'not found'
    }

    It "Falls back to lifecycle status when health is unavailable" {
        function global:docker {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $global:LASTEXITCODE = 0
            'created||123456789abc'
        }

        $state = Get-ComposeServiceState -ServiceName 'qbittorrent'
        $healthMap = Get-ComposeServiceHealthMap -ServiceNames @('qbittorrent')

        $state.Exists | Should Be $true
        $state.Lifecycle | Should Be 'created'
        $state.Health | Should Be ''
        $healthMap['qbittorrent'] | Should Be 'created'
    }
}
