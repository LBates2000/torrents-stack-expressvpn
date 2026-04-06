# Pester tests for shared-functions.ps1

Describe "Write-ProgressLine" {
    BeforeAll {
        . "$PSScriptRoot/../scripts/shared-functions.ps1"
    }

    It "Should write output without error in non-interactive session" {
        Write-ProgressLine "Test message" -Color Yellow
    }
}

Describe "Jackett password hashing" {
    BeforeAll {
        . "$PSScriptRoot/../scripts/shared-functions.ps1"
    }

    It "Matches Jackett's salted SHA512 format" {
        $hash = Get-JackettAdminPasswordHash -Password 'temp03202026' -ApiKey 'cwgfqc90uk7fu634md5k8eoqgmp7ycor'

        if ($hash -ne 'f7132d32188a9aabda4e402717e116fd4082369e192e992062c466aa008b52605038b821d92306c042ad414532d8dcfb0710ccb0d7ad4b8a4ac66afef2c36ab1') {
            throw 'Jackett admin password hash did not match the expected salted SHA512 value.'
        }
    }

    It "Rejects hashing without an API key" {
        $threw = $false

        try {
            Get-JackettAdminPasswordHash -Password 'password' -ApiKey $null
        }
        catch {
            $threw = $true
        }

        if (-not $threw) {
            throw 'Expected Jackett admin password hashing without an API key to throw.'
        }
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
