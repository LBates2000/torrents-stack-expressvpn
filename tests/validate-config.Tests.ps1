Describe "validate-config Jackett requirements" {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("torrents-stack-validate-tests-" + [guid]::NewGuid().ToString('N'))
        $tempScripts = Join-Path $tempRoot 'scripts'

        New-Item -ItemType Directory -Path $tempScripts -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempScripts 'unused') -Force | Out-Null

        Copy-Item (Join-Path $repoRoot 'scripts\validate-config.ps1') $tempScripts
        Copy-Item (Join-Path $repoRoot 'scripts\shared-functions.ps1') $tempScripts
        Copy-Item (Join-Path $repoRoot 'scripts\Write-Log.ps1') $tempScripts

        Set-Content -LiteralPath (Join-Path $tempRoot 'docker-compose.yml') -Value 'services: {}'
        Set-Content -LiteralPath (Join-Path $tempScripts 'bootstrap-qbittorrent-jackett.sh') -Value '#!/bin/sh'
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It "Fails when Jackett admin password is set without an API key" {
        @(
            'EXPRESSVPN_ACTIVATION_CODE=test-code',
            'EXPRESSVPN_REGION=smart',
            'JACKETT_CFG_ADMIN_PASSWORD=test-password'
        ) | Set-Content -LiteralPath (Join-Path $tempRoot '.env')

        $output = & pwsh -NoProfile -File (Join-Path $tempScripts 'validate-config.ps1') 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            throw 'Expected validate-config.ps1 to fail when JACKETT_CFG_API_KEY is missing.'
        }

        $message = ($output | Out-String)
        if ($message -notmatch 'requires JACKETT_CFG_API_KEY when JACKETT_CFG_ADMIN_PASSWORD is set') {
            throw "Expected Jackett API key validation error, got: $message"
        }
    }

    It "Passes when Jackett admin password and API key are both set" {
        @(
            'EXPRESSVPN_ACTIVATION_CODE=test-code',
            'EXPRESSVPN_REGION=smart',
            'JACKETT_CFG_API_KEY=test-api-key',
            'JACKETT_CFG_ADMIN_PASSWORD=test-password'
        ) | Set-Content -LiteralPath (Join-Path $tempRoot '.env')

        $output = & pwsh -NoProfile -File (Join-Path $tempScripts 'validate-config.ps1') 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "Expected validate-config.ps1 to pass when Jackett API key is provided. Output: $($output | Out-String)"
        }
    }
}