## Summary
- What changed?
- Why was this change needed?

## Validation
- [ ] `git hook run pre-commit` passes
- [ ] `docker compose config` passes
- [ ] `docker compose ps` shows expected service state
- [ ] Related docs updated (`README.md`, `.env.example`, etc.)

## Risk / impact
- Services impacted:
- Rollback plan:

## Checklist
- [ ] No secrets or private keys committed
- [ ] Runtime/state files were not added (`configs/`, `downloads/`, `.env`)
- [ ] Healthchecks/dependencies reviewed if service behavior changed
