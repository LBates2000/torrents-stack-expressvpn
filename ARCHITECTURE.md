# Stack Architecture Diagram (Mermaid)

```mermaid
graph TD
    subgraph VPN Network
        expressvpn((ExpressVPN))
        qbittorrent((qBittorrent))
    end
    subgraph App Network
        jackett((Jackett))
        flaresolverr((FlareSolverr))
    end
    expressvpn -- network_mode:service:expressvpn --> qbittorrent
    jackett -- API --> qbittorrent
    flaresolverr -- API --> jackett
    jackett -- Web UI --> User
    qbittorrent -- Web UI --> User
    flaresolverr -- API --> User
```

# Usage Examples

- See main README for command usage and setup.
- Run `pwsh ./scripts/validate-config.ps1` before starting the stack to check for missing/invalid configs.
- Use `pwsh ./scripts/cleanup-orphans.ps1` to remove old logs and orphaned Docker resources.
- Shared PowerShell path and `.env` resolution lives in `scripts/shared-functions.ps1`, so operational scripts follow the same host directory overrides.
- Missing runtime configs under `configs/` are bootstrapped by the sync/startup flow, so validation focuses on env/template inputs rather than committed machine state.
- All scripts support robust logging and error handling.

# Troubleshooting

- If a service is unhealthy, run the corresponding healthcheck script in `scripts/` for details.
- For CI failures, inspect the failing GitHub Actions step for config validation or Pester output.

# Security

- Never commit `.env` or secrets to git.
- All scripts redact sensitive values in logs.
- Pre-commit and CI guardrails block secrets from being committed.
