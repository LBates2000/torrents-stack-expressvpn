Describe "sync-qbittorrent-config bootstrap env" {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("torrents-stack-sync-qbit-tests-" + [guid]::NewGuid().ToString('N'))
        $tempScripts = Join-Path $tempRoot 'scripts'

        New-Item -ItemType Directory -Path $tempScripts -Force | Out-Null

        Copy-Item (Join-Path $repoRoot 'scripts\sync-qbittorrent-config.ps1') $tempScripts
        Copy-Item (Join-Path $repoRoot 'scripts\shared-functions.ps1') $tempScripts
        Copy-Item (Join-Path $repoRoot 'scripts\Write-Log.ps1') $tempScripts
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It "Writes shell-safe bootstrap values for container startup" {
        @(
            'QBITTORRENT_WEBUI_PORT=8081',
            'QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT=pa''ss word',
            'QBITTORRENT_CFG_DOWNLOADS_SAVE_PATH=/downloads/',
            'QBITTORRENT_CFG_DOWNLOADS_TEMP_PATH=/downloads/incomplete/',
            'QBITTORRENT_JACKETT_URL=http://jackett:9117'
        ) | Set-Content -LiteralPath (Join-Path $tempRoot '.env')

        $output = & pwsh -NoProfile -File (Join-Path $tempScripts 'sync-qbittorrent-config.ps1') -SkipRestart 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "Expected sync-qbittorrent-config.ps1 to succeed. Output: $($output | Out-String)"
        }

        $bootstrapEnvPath = Join-Path $tempRoot 'configs\qBittorrent\bootstrap.env'
        if (-not (Test-Path -LiteralPath $bootstrapEnvPath)) {
            throw 'Expected bootstrap.env to be created.'
        }

        $bootstrapContent = Get-Content -LiteralPath $bootstrapEnvPath -Raw
        if ($bootstrapContent -notmatch "QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT='pa'\\''ss word'") {
            throw "Expected plaintext password to be shell-escaped in bootstrap.env. Content: $bootstrapContent"
        }
        if ($bootstrapContent -notmatch "WEBUI_PORT='8081'") {
            throw "Expected WEBUI_PORT to be mirrored into bootstrap.env. Content: $bootstrapContent"
        }
        if ($bootstrapContent.Contains("`r")) {
            throw "Expected bootstrap.env to use LF line endings only. Content: $bootstrapContent"
        }
    }

    It "Treats bootstrap env changes as qBittorrent sync changes" {
        @(
            'QBITTORRENT_WEBUI_PORT=8080',
            'QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT=first-pass'
        ) | Set-Content -LiteralPath (Join-Path $tempRoot '.env')

        $null = & pwsh -NoProfile -File (Join-Path $tempScripts 'sync-qbittorrent-config.ps1') -SkipRestart -EmitStatus 2>&1

        @(
            'QBITTORRENT_WEBUI_PORT=9090',
            'QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT=first-pass'
        ) | Set-Content -LiteralPath (Join-Path $tempRoot '.env')

        $output = & pwsh -NoProfile -File (Join-Path $tempScripts 'sync-qbittorrent-config.ps1') -SkipRestart -EmitStatus 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "Expected sync-qbittorrent-config.ps1 to succeed after bootstrap env change. Output: $($output | Out-String)"
        }

        $message = $output | Out-String
        if ($message -notmatch 'SYNC_STATUS:qbittorrent:true') {
            throw "Expected bootstrap-only changes to mark qBittorrent sync as changed. Output: $message"
        }
    }
}
