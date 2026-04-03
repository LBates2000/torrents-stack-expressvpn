# Contributing

Thanks for contributing to this project.

## Workflow
- Create a branch from `main`.
- Do not push directly to `main`; all changes must go through a pull request.
- Keep changes focused and small.
- Run local checks before opening a PR:
  - `docker compose config`
  - `docker compose ps`
- Open a pull request and complete the template.

## PR approval bot
- Workflow file: `.github/workflows/pr-approval-bot.yml`.
- Create a repository secret named `PR_APPROVAL_BOT_TOKEN`.
- Recommended token: Fine-grained PAT from a dedicated bot account with repository `Pull requests: Read and write`.
- Current trusted PR authors are `dependabot[bot]` and `LBates2000`.
- To change trusted authors, edit the JSON list in the workflow `contains(fromJSON(...), github.event.pull_request.user.login)` condition.
- Important: this bot adds an approval review, but branch protection still requires a code-owner review from `.github/CODEOWNERS`.

## Configuration changes
- Do not commit runtime data from `configs/` or `downloads/`.
- Do not commit real credentials, API keys, or VPN private keys.
- Keep `.env` local; update `.env.example` when adding new variables.
- Enable the local commit guardrail once per clone: `git config core.hooksPath .githooks`.
- The repo pre-commit hook blocks commits that stage `.env`.
- CI also fails if `.env` is ever tracked by git.

## Documentation updates
- Keep command behavior descriptions in `scripts/torrents-stack.ps1` usage/help output.
- In `README.md`, reference script usage/help instead of duplicating per-command behavior text.
- Update `README.md` for any behavior, healthcheck, or command changes.
- Keep operational instructions concise and copy/paste ready.

## Commit guidance
- Use clear commit messages in imperative form, for example:
  - `Update jackett healthcheck redirects`
  - `Add compose smoke test workflow`
