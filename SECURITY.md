# Security Policy

## Supported Versions

This project is maintained on the `main` branch.

## Reporting a Vulnerability

Please do **not** open public GitHub issues for security vulnerabilities.

Use one of the following private channels:
- GitHub private vulnerability reporting (Security tab)
- Email: Lawrence.Bates@gmail.com

Include as much detail as possible:
- Affected component/file
- Steps to reproduce
- Impact assessment
- Suggested mitigation (if known)

## Response Expectations

- Initial acknowledgment target: within 72 hours
- Triage/update target: within 7 days
- Remediation timeline depends on severity and complexity

## Security Notes for This Repo

- Never commit real credentials, API keys, or VPN private keys.
- Keep `.env` local and out of version control.
- Enable the local repo-managed hook path using the setup documented in `CONTRIBUTING.md`.
- The repo-managed hook and CI workflow prevent `.env` from being tracked.
- Runtime data in `configs/` and `downloads/` should stay untracked.
