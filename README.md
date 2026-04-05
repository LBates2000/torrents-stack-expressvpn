# Torrents Docker Stack (ExpressVPN)

[![Compose Validate](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/compose-validate.yml/badge.svg)](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/compose-validate.yml)
[![Backup Restore Reminder](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml/badge.svg)](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml)

This stack routes only qBittorrent through ExpressVPN.

## Project Status

This repository is in maintenance mode.

- The stack is considered stable for its current scope.
- Future changes should be limited to break-fix work, security updates, dependency maintenance, or documentation corrections.
- For the latest tagged release and release notes, use the releases page: https://github.com/LBates2000/torrents-stack-expressvpn/releases


## Stack Commands (Wrapper Script)

Primary entrypoint:
```
pwsh ./scripts/torrents-stack.ps1 <command>
```

Authoritative command descriptions live in the script usage output and help:

```
pwsh ./scripts/torrents-stack.ps1
Get-Help ./scripts/torrents-stack.ps1 -Detailed
```

Supported commands: `start`, `stop`, `restart`, `update`, `status`, `logs`, `sync`, `rebuild`, `clean`, `test-all`, `preflight`, `report`.

Example:
```
pwsh ./scripts/torrents-stack.ps1 start
```

- `preflight` checks whether Docker is reachable before runtime operations.
- `report` writes a sanitized stack test report under `logs/` without expanding secret values from `.env`.
- Wrapper progress logs default to `-ExternalLogMode off`; use `-ExternalLogMode auto` to keep logs only when a wrapped command fails, or `-ExternalLogMode always` to always write them. Managed wrapper `.log` files older than `-ExternalLogRetentionDays` are pruned automatically.
- You can set repo-local defaults in `.env` with `STACK_EXTERNAL_LOG_MODE=off|auto|always` and `STACK_EXTERNAL_LOG_RETENTION_DAYS=<0-365>`. CLI flags still take precedence.

## Secrets handling
- Keep real secrets only in local `.env`; do not commit them to git.
- `.env` is intentionally ignored by `.gitignore`; `.env.example` is the safe template to commit.
- Sensitive values in this stack include `EXPRESSVPN_ACTIVATION_CODE`, `JACKETT_CFG_API_KEY`, and `JACKETT_CFG_OMDB_API_KEY`.
- Sync and runtime scripts intentionally redact sensitive values in console logs (for example API keys and auth tokens).
- Enable the local repo-managed hook path once per clone with the setup documented in `CONTRIBUTING.md`.
- The local hook and CI both block commits that stage `.env`.
- Before committing, run `git status --short` and confirm `.env` is not listed.

## How it works
- `expressvpn` is the VPN gateway.
- The ExpressVPN entrypoint retries login/connect on startup and runs a lightweight reconnect watchdog if the daemon later drops the tunnel.
- `qbittorrent` uses `network_mode: "service:expressvpn"`, so torrent traffic goes through ExpressVPN.
- `jackett` and `flaresolverr` run on `app_net` and expose their own ports.
- Host access is published by the compose port mappings.

## Access
- qBittorrent Web UI: http://localhost:8080
- Jackett UI: http://localhost:9117
- Note: Jackett may return `301`/`302` redirects to login; this is expected.
- FlareSolverr API: http://localhost:8191

## ExpressVPN prerequisites

Set `EXPRESSVPN_ACTIVATION_CODE` in `.env` before first startup.

`EXPRESSVPN_REGION`: set a valid region code supported by the ExpressVPN image. Common examples:

* smart
* netherlands-amsterdam
* netherlands-rotterdam
* netherlands-the-hague
* switzerland
* switzerland-2

To list all valid region codes, run `expressvpnctl get regions` inside the running expressvpn container:
```sh
docker exec -it expressvpn expressvpnctl get regions
```
The classic `expressvpn list all` command is not available in this image.
`EXPRESSVPN_PROTOCOL`: use `auto` (recommended) or set `lightwayudp`, `lightwaytcp`, `openvpnudp`, `openvpntcp`, or `wireguard`.

Example `.env` values:
```env
EXPRESSVPN_ACTIVATION_CODE=YOUR_CODE_HERE
EXPRESSVPN_REGION=netherlands-amsterdam
EXPRESSVPN_PROTOCOL=auto
```

## First-time setup
- Install Docker Desktop (or Docker Engine + Compose plugin).
- Set your ExpressVPN activation code using `.env` values from `.env.example`.
- Copy `.env.example` to `.env` and adjust values for your host/network.
- The sync/start scripts resolve runtime paths from `.env` once and auto-create missing directories and seed config files under `HOST_CONFIGS_DIR` and `HOST_DOWNLOADS_DIR`.
- Start the stack with `pwsh ./scripts/torrents-stack.ps1 start`.

### Quick start
#### Bash
```bash
cp .env.example .env
pwsh ./scripts/torrents-stack.ps1 start
```

#### PowerShell
```powershell
Copy-Item .env.example .env -Force
pwsh ./scripts/torrents-stack.ps1 start
```

## Commands
- Use the wrapper script section above for the primary lifecycle commands.
- Use the `docker compose` flows below only for lower-level rebuild/reset work.

## Rebuild options
Full rebuild with fresh images:
```bash
docker compose down
docker compose pull
docker compose build --no-cache
docker compose up -d --remove-orphans
```

Force recreate containers:
```bash
docker compose down
docker compose build --no-cache
docker compose up --force-recreate -d
```

Full reset (remove volumes):
```bash
docker compose down -v
docker compose build --no-cache
docker compose up --force-recreate -d
```

## Config directories
- Local data is mounted from `HOST_CONFIGS_DIR` to `CONTAINER_CONFIGS_DIR` (defaults: `./configs` -> `/config`).
- Torrent downloads are stored from `HOST_DOWNLOADS_DIR` to `CONTAINER_DOWNLOADS_DIR` (defaults: `./downloads` -> `/downloads`).
- The PowerShell scripts use the same shared path resolution logic as the compose file, so backups, validation, and config sync all follow those overrides consistently.

## Image pinning
- Images default to `latest` in `docker-compose.yml` via environment-backed tags.
- Override image tags in `.env` using `EXPRESSVPN_IMAGE_TAG`, `FLARESOLVERR_IMAGE_TAG`, `JACKETT_IMAGE_TAG`, and `QBITTORRENT_IMAGE_TAG`.

## Advanced env overrides
- Network driver: `APP_NET_DRIVER` (default: `bridge`)
- Host bind mount directories: `HOST_CONFIGS_DIR`, `HOST_DOWNLOADS_DIR`
- Container bind mount targets: `CONTAINER_CONFIGS_DIR`, `CONTAINER_DOWNLOADS_DIR`
- ExpressVPN entrypoint script mount: `HOST_EXPRESSVPN_ENTRYPOINT_SCRIPT`
- Container names: `EXPRESSVPN_CONTAINER_NAME`, `FLARESOLVERR_CONTAINER_NAME`, `JACKETT_CONTAINER_NAME`, `QBITTORRENT_CONTAINER_NAME`
- Shared healthcheck overrides: `HEALTHCHECK_INTERVAL`, `HEALTHCHECK_TIMEOUT`, `HEALTHCHECK_RETRIES`, `HEALTHCHECK_START_PERIOD`
- If you customize container names, update any external scripts/automation that reference those container names directly.

### Jackett config via env
- `jackett` now bootstraps `ServerConfig.json` from `.env` values (`JACKETT_CFG_*`) at container startup.
- Defaults match the existing `ServerConfig.json` values.
- `JACKETT_CFG_API_KEY` and `JACKETT_CFG_INSTANCE_ID` default to `null` (auto-generated), but can be set to static values for persistence.
- `JACKETT_CFG_BLACKHOLE_DIR` defaults to `CONTAINER_DOWNLOADS_DIR/watch`.
- `JACKETT_CFG_OMDB_API_URL` defaults to `https://www.omdbapi.com/`.
- `JACKETT_CFG_FLARESOLVERR_URL` defaults to `http://flaresolverr:8191` (service-name routing on the compose network).
- Proxy type UI hint: `JACKETT_CFG_PROXY_TYPE` uses `0=None`, `1=Http`, `2=Socks5`.
- Run `pwsh ./scripts/sync-jackett-config.ps1` to sync `configs/Jackett/ServerConfig.json` from `.env` (`APIKey`, `InstanceId`, `BlackholeDir`, `OmdbApiKey`, `OmdbApiUrl`, `FlareSolverrUrl`).
- The script restarts `jackett` only when values changed and the service is running.
- Use `pwsh ./scripts/sync-jackett-config.ps1 -SkipRestart` to sync without restart.

### qBittorrent config via env
- Use `.env` values (`QBITTORRENT_CFG_*`) to manage `configs/qBittorrent/qBittorrent.conf`.
- Optional: set `QBITTORRENT_CFG_WEBUI_PASSWORD_PBKDF2` to enforce the WebUI admin password hash via `.env`.
- Optional: set `QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT` to generate `WebUI\Password_PBKDF2` automatically during sync (PBKDF2 value wins if both are set).
- Use `QBITTORRENT_CFG_CATEGORIES_JSON` to populate `configs/qBittorrent/categories.json`.
- Use `QBITTORRENT_CFG_WATCHED_FOLDERS_JSON` to populate `configs/qBittorrent/watched_folders.json`.
- On startup, `qbittorrent` also reapplies `save_path` and `temp_path` through the Web API so completed and incomplete downloads stay under `CONTAINER_DOWNLOADS_DIR` instead of drifting back to `/config/Downloads`.
- On startup, `qbittorrent` bootstraps the Jackett search plugin under `configs/qBittorrent/nova3/engines`:
	- Installs `jackett.py` automatically (if missing) from `QBITTORRENT_JACKETT_PLUGIN_URL`.
	- Writes `jackett.json` using `QBITTORRENT_JACKETT_API_KEY` (or auto-reads `configs/Jackett/ServerConfig.json` `APIKey` when empty).
	- Defaults plugin URL target to `QBITTORRENT_JACKETT_URL=http://jackett:9117`.
- If either JSON env var is empty, the script auto-generates defaults from `QBITTORRENT_CFG_DOWNLOADS_SAVE_PATH`:
  - Categories: `movies -> <SavePath>/movies`, `tv -> <SavePath>/tv`
  - Watched folders: `<SavePath>/watch/movies` and `<SavePath>/watch/tv`
- Run `pwsh ./scripts/sync-qbittorrent-config.ps1` to sync config from `.env`.
- The script restarts `qbittorrent` only when `qBittorrent.conf`, `categories.json`, or `watched_folders.json` changed and the service is running.
- Use `pwsh ./scripts/sync-qbittorrent-config.ps1 -SkipRestart` to sync without restart.
- Use `pwsh ./scripts/sync-qbittorrent-config.ps1 -Verbose` to show password generation and config update details.
- If `QBITTORRENT_CFG_WEBUI_PASSWORD_PBKDF2` is empty or missing, the script leaves any existing `WebUI\Password_PBKDF2` value unchanged.
- If `QBITTORRENT_CFG_WEBUI_PASSWORD_PLAINTEXT` is set, the script generates a PBKDF2-SHA512 (100000 iterations) hash in qBittorrent format.

Example custom overrides:
```env
APP_NET_DRIVER=bridge
EXPRESSVPN_CONTAINER_NAME=vpn-gateway
FLARESOLVERR_CONTAINER_NAME=flaresolverr-app
JACKETT_CONTAINER_NAME=jackett-app
QBITTORRENT_CONTAINER_NAME=qbittorrent-app
HEALTHCHECK_INTERVAL=30s
HEALTHCHECK_TIMEOUT=30s
HEALTHCHECK_RETRIES=10
HEALTHCHECK_START_PERIOD=45s
```

## Startup order
- `expressvpn` and `flaresolverr` start independently (no dependencies).
- `jackett` depends on `flaresolverr`.
- `qbittorrent` waits for `expressvpn`, `jackett`, and `flaresolverr` to be healthy.

## Healthchecks (service-specific)
- `expressvpn`: default `strict` mode requires `expressvpnctl` to report `Connected` and then verifies DNS plus outbound web access; set `EXPRESSVPN_HEALTHCHECK_MODE=relaxed` to only require the daemon to respond in CI/dev.
- `flaresolverr`: checks `http://localhost:8191`
- `jackett`: checks `http://localhost:9117/` and accepts `200`, `301`, or `302`
- `qbittorrent`: checks `http://localhost:8080/` and accepts `200` or `302`

## Compose Validate smoke-test input
- The `Compose Validate` workflow includes an optional manual input named `expressvpn_activation_code`.
- On `push` and `pull_request`, smoke-test steps are skipped unless that input is provided (non-empty).
- To run the smoke-test manually in GitHub Actions: open `Compose Validate` -> `Run workflow` -> set `expressvpn_activation_code`.

## Startup timing (observed)
- Typical clean startup on this host: ~70-80 seconds.
- Recent 3-run sample on current config:

| Metric | Seconds |
| --- | ---: |
| Min | 71.29 |
| Avg | 73.74 |
| Max | 77.90 |

- Shared healthcheck cadence defaults: `interval=30s`, `timeout=30s`, `retries=10`, `start_period=180s` (override via `HEALTHCHECK_*` in `.env`).
- If startup exceeds 2-3 minutes, check logs.

### Quick diagnostics
- Overall status: `pwsh ./scripts/torrents-stack.ps1 status`
  - Shows container status and clickable web UI links for qBittorrent, Jackett, and Flaresolverr
- Auth diagnostics (verbose): `pwsh ./scripts/torrents-stack.ps1 status -VerboseAuth`
  - Includes authentication check details and endpoint information
- `status` now also reports whether qBittorrent has Jackett plugin files at `configs/qBittorrent/nova3/engines/jackett.py` and `jackett.json`.
- Health-focused status: `docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}\t{{.Status}}"`
- Timed startup (PowerShell): `$t = Measure-Command { docker compose up -d }; $t.TotalSeconds`
- Tail all logs: `pwsh ./scripts/torrents-stack.ps1 logs`
- Tail one service: `pwsh ./scripts/torrents-stack.ps1 logs -Service expressvpn` (or `flaresolverr`, `jackett`, `qbittorrent`)

## Incident runbook
- Symptom: stack did not start
	- Command: `docker compose ps`
	- Expected: all services `running` and `healthy`
- Symptom: qBittorrent UI unavailable
	- Command: `docker compose logs --tail=100 qbittorrent expressvpn`
	- Expected: `expressvpn` is running and `qbittorrent` serving on `http://localhost:8080/`
- Symptom: Jackett API/UI failing
	- Command: `docker compose logs --tail=100 jackett flaresolverr`
	- Expected: `jackett` healthcheck returns `200|301|302` and `flaresolverr` is ready
- Symptom: VPN routing suspected down
	- Command: `docker compose logs --tail=100 expressvpn`
	- Expected: active ExpressVPN connection for the configured server/protocol
- Emergency rollback
	- Command: `git checkout v1.0.4; docker compose down; docker compose up -d`
	- Expected: stack returns to last tagged baseline

## Backup and restore
The repository includes a monthly reminder workflow that opens a backup/restore verification issue:
- `Backup Restore Reminder` workflow: https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml

The bundled PowerShell helpers also respect `HOST_CONFIGS_DIR` and `HOST_DOWNLOADS_DIR`, so backup and restore follow the same directories used by the sync scripts and compose mounts:

```powershell
pwsh ./scripts/backup-configs.ps1
pwsh ./scripts/restore-configs.ps1 -Archive .\backups\stack-backup-<timestamp>.zip
```
- After restore, verify health with `docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}\t{{.Status}}"`.

## Notes
- If you change ExpressVPN activation/region/protocol values, restart the `expressvpn` container.
- To troubleshoot region issues, use `docker exec -it expressvpn expressvpnctl get regions` to see all valid region codes.
- Keep `expressvpn` service running before app services start.
- Redirect-based healthchecks are intentional: `301`/`302` can still mean the web UI is up before login.

## Changelog
- Latest release and full history: https://github.com/LBates2000/torrents-stack-expressvpn/releases

## Project governance
- Security policy: see `SECURITY.md`.
- Use GitHub issue templates for monthly maintenance and backup restore drills.
- License: MIT (`LICENSE`).
- Contribution guide: see `CONTRIBUTING.md`.
- Scheduled image tag drift check: `.github/workflows/image-tag-drift.yml`.

## Author
- Lawrence Bates (<Lawrence.Bates@gmail.com>)

## Cross-Platform Support
- All scripts are tested with PowerShell Core (pwsh) on Windows and Linux.
- Bash healthcheck scripts require bash and standard Unix tools.
- If you encounter OS-specific issues, please open an issue or PR.

## Environment Variable Overrides
- Primary runtime overrides live in `.env.example`; keep that file aligned with any new variables.
- Most scripts read the same `.env` values as the compose stack, which keeps sync, validation, backup, and lifecycle commands aligned for CI and local automation.
