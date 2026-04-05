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

    function Assert-Equal {
        param(
            $Actual,
            $Expected,
            [string]$Message
        )

        if ($Actual -ne $Expected) {
            throw ("{0} Expected '{1}', got '{2}'." -f $Message, $Expected, $Actual)
        }
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

        Assert-Equal -Actual $state.Exists -Expected $false -Message 'Exists flag mismatch.'
        Assert-Equal -Actual $state.DisplayStatus -Expected 'not found' -Message 'DisplayStatus mismatch.'
    }

    It "Falls back to lifecycle status when health is unavailable" {
        function global:docker {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $global:LASTEXITCODE = 0
            'created||123456789abc'
        }

        $state = Get-ComposeServiceState -ServiceName 'qbittorrent'
        $healthMap = Get-ComposeServiceHealthMap -ServiceNames @('qbittorrent')

        Assert-Equal -Actual $state.Exists -Expected $true -Message 'Exists flag mismatch.'
        Assert-Equal -Actual $state.Lifecycle -Expected 'created' -Message 'Lifecycle mismatch.'
        Assert-Equal -Actual $state.Health -Expected '' -Message 'Health mismatch.'
        Assert-Equal -Actual $healthMap['qbittorrent'] -Expected 'created' -Message 'Health map mismatch.'
    }
}
