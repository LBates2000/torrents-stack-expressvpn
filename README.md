# Torrents Docker Stack (ExpressVPN)

[![Compose Validate](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/compose-validate.yml/badge.svg)](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/compose-validate.yml)
[![Backup Restore Reminder](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml/badge.svg)](https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml)

This stack routes only qBittorrent through WireGuard.

## How it works
- `wireguard` is the VPN gateway.
- `qbittorrent` uses `network_mode: "service:wireguard"`, so torrent traffic goes through WireGuard.
- `jackett` and `flaresolverr` run on `app_net` and expose their own ports.
- Host access is published by the compose port mappings.

## Access
- qBittorrent Web UI: http://localhost:8090
- Jackett UI: http://localhost:9117
- Note: Jackett may return `301`/`302` redirects to login; this is expected.
- FlareSolverr API: http://localhost:8191

## First-time setup
- Install Docker Desktop (or Docker Engine + Compose plugin).
- Configure WireGuard using `.env` values (server mode defaults are provided in `.env.example`).
- Optional: if you are running in client mode, place your WireGuard client config in `./configs/wireguard/` (for example `wg0.conf`).
- Copy `.env.example` to `.env` and adjust values for your host/network.
- Start the stack with `docker compose up -d`.

### Quick start
#### Bash
```bash
cp .env.example .env
docker compose up -d
```

#### PowerShell
```powershell
Copy-Item .env.example .env -Force
docker compose up -d
```

## Commands
- Start: `docker compose up -d`
- Stop: `docker compose down`
- Check: `docker compose ps`

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
- Local data is mounted from `./configs`.
- Torrent downloads are stored in `./downloads`.

## Image pinning
- Images are pinned by default in `docker-compose.yml` via environment-backed tags.
- Override image versions in `.env` using `WIREGUARD_IMAGE_TAG`, `FLARESOLVERR_IMAGE_TAG`, `JACKETT_IMAGE_TAG`, and `QBITTORRENT_IMAGE_TAG`.

## Startup order
- `wireguard` and `flaresolverr` start independently (no dependencies).
- `jackett` depends on `flaresolverr`.
- `qbittorrent` depends on `wireguard`, `jackett`, and `flaresolverr`.

## Healthchecks (service-specific)
- `wireguard`: checks that `wg0` exists, the interface is up, and a public IP is returned from `${WIREGUARD_IP_CHECK_URL:-https://api.ipify.org}`
- `flaresolverr`: checks `http://localhost:8191`
- `jackett`: checks `http://localhost:9117/` and accepts `200`, `301`, or `302`
- `qbittorrent`: checks `http://localhost:8090/` and accepts `200` or `302`

## Startup timing (observed)
- Typical clean startup on this host: ~70-80 seconds.
- Recent 3-run sample on current config:

| Metric | Seconds |
| --- | ---: |
| Min | 71.29 |
| Avg | 73.74 |
| Max | 77.90 |

- Shared healthcheck cadence: `interval=20s`, `timeout=10s`, `retries=8`, `start_period=30s`.
- If startup exceeds 2-3 minutes, check logs.

### Quick diagnostics
- Overall status: `docker compose ps`
- Health-focused status: `docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}\t{{.Status}}"`
- Timed startup (PowerShell): `$t = Measure-Command { docker compose up -d }; $t.TotalSeconds`
- Tail all logs: `docker compose logs -f`
- Tail one service: `docker compose logs -f wireguard` (or `flaresolverr`, `jackett`, `qbittorrent`)

## Incident runbook
- Symptom: stack did not start
	- Command: `docker compose ps`
	- Expected: all services `running` and `healthy`
- Symptom: qBittorrent UI unavailable
	- Command: `docker compose logs --tail=100 qbittorrent wireguard`
	- Expected: `wireguard` healthy and `qbittorrent` serving on `http://localhost:8090/`
- Symptom: Jackett API/UI failing
	- Command: `docker compose logs --tail=100 jackett flaresolverr`
	- Expected: `jackett` healthcheck returns `200|301|302` and `flaresolverr` is ready
- Symptom: VPN routing suspected down
	- Command: `docker compose exec wireguard wg show`
	- Expected: active `wg0` interface and peer/session data present
- Emergency rollback
	- Command: `git checkout v1.0.0; docker compose down; docker compose up -d`
	- Expected: stack returns to last tagged baseline

## Backup and restore
The repository includes a monthly reminder workflow that opens a backup/restore verification issue:
- `Backup Restore Reminder` workflow: https://github.com/LBates2000/torrents-stack-expressvpn/actions/workflows/backup-restore-reminder.yml

Backup runtime config (PowerShell):
```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Path .\backups -Force | Out-Null
Compress-Archive -Path .\configs\* -DestinationPath (".\\backups\\configs-" + $stamp + ".zip") -Force
```

Restore runtime config (PowerShell):
```powershell
docker compose down
Expand-Archive -Path .\backups\configs-<timestamp>.zip -DestinationPath .\configs -Force
docker compose up -d
```

After restore, verify health:
```powershell
docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}\t{{.Status}}"
```

## Notes
- If you change WireGuard peer config, restart the `wireguard` container.
- Keep `wireguard` service healthy before app services start.
- Redirect-based healthchecks are intentional: `301`/`302` can still mean the web UI is up before login.

## Changelog
- `v1.0.3` (ci: bump actions/checkout to v6): https://github.com/LBates2000/torrents-stack-expressvpn/releases/tag/v1.0.3
- `v1.0.2` (docs: onboarding and Jackett redirect clarifications): https://github.com/LBates2000/torrents-stack-expressvpn/releases/tag/v1.0.2
- `v1.0.1` (operationally verified checkpoint): https://github.com/LBates2000/torrents-stack-expressvpn/releases/tag/v1.0.1
- `v1.0.0` (hardened baseline): https://github.com/LBates2000/torrents-stack-expressvpn/releases/tag/v1.0.0
- All releases: https://github.com/LBates2000/torrents-stack-expressvpn/releases

## Project governance
- Security policy: see `SECURITY.md`.
- Use GitHub issue templates for monthly maintenance and backup restore drills.
- License: MIT (`LICENSE`).
- Contribution guide: see `CONTRIBUTING.md`.
- Scheduled image tag drift check: `.github/workflows/image-tag-drift.yml`.

## Author
- Lawrence Bates (<Lawrence.Bates@gmail.com>)
