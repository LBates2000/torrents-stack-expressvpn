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

Describe "External log helpers" {
    BeforeAll {
        . "$PSScriptRoot/../scripts/shared-functions.ps1"
    }

    It "Defaults external log mode to off" {
        $originalModePresent = Test-Path Variable:\script:ExternalLogMode
        if ($originalModePresent) {
            $originalMode = $script:ExternalLogMode
            Remove-Variable -Scope Script -Name ExternalLogMode -Force
        }

        try {
            if ((Get-ExternalLogMode) -ne 'off') {
                throw "Expected default external log mode to be 'off'."
            }
        }
        finally {
            if ($originalModePresent) {
                $script:ExternalLogMode = $originalMode
            }
        }
    }

    It "Writes logs in auto mode only when the command fails" {
        $script:ExternalLogMode = 'auto'

        if (Test-ShouldWriteExternalLog -ExitCode 0) {
            throw "Expected auto mode to skip successful command logs."
        }

        if (-not (Test-ShouldWriteExternalLog -ExitCode 1)) {
            throw "Expected auto mode to capture failed command logs."
        }
    }

    It "Identifies managed wrapper log file names" {
        if (-not (Test-ManagedExternalLogFileName -FileName 'docker-progress-20260404-123456.log')) {
            throw "Expected docker progress log name to be managed."
        }

        if (-not (Test-ManagedExternalLogFileName -FileName 'qbittorrent-recover-20260404-123456.log')) {
            throw "Expected command progress log name to be managed."
        }

        if (Test-ManagedExternalLogFileName -FileName 'final-wrap-test-all-20260404-001548.txt') {
            throw "Did not expect report artifact names to be treated as managed logs."
        }
    }
}
