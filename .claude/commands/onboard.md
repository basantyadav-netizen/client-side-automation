---
description: Run the full new-employee macOS onboarding pipeline — 10 common steps then a numbered team track (Track 11 frontend / Track 12 backend / Track 13 data-engineering / Track 14 sre). Resumable; team set via TEAM in .env.
argument-hint: "[optional: \"Full Name\" email@gmail.com [team]]"
allowed-tools: Agent, Bash, Read
model: opus
---

# /onboard — New employee onboarding

## Preflight context
- OS: !`uname -s`
- Architecture: !`uname -m`
- .env present: !`test -f .env && echo yes || echo "NO — create it with GIT_USERNAME, GIT_EMAIL, GITHUB_PAT, GITHUB_EMAIL, PREFERRED_REPOSITORIES_LOCATION, TEAM"`
- git identity set in .env: !`grep -qE '^GIT_USERNAME=.+' .env 2>/dev/null && grep -qE '^GIT_EMAIL=.+' .env 2>/dev/null && echo yes || echo "NO — add GIT_USERNAME / GIT_EMAIL"`
- repos location set in .env: !`grep -qE '^PREFERRED_REPOSITORIES_LOCATION=.+' .env 2>/dev/null && echo yes || echo "NO — add PREFERRED_REPOSITORIES_LOCATION (e.g. /Users/you/Repositories)"`
- team set in .env: !`grep -qE '^TEAM=(frontend|backend|data-engineering|sre)' .env 2>/dev/null && echo yes || echo "NO — add TEAM=<frontend|backend|data-engineering|sre>"`
- Existing machine_config.json: !`test -f machine_config.json && echo "exists (will be refreshed)" || echo none`
- Existing session: !`test -f onboarding-session.json && echo "found — run will RESUME from the first unfinished step" || echo "none — fresh run"`

## Optional argument handling
Arguments passed: `$ARGUMENTS`

`$ARGUMENTS` may contain up to three space-separated tokens: `"Full Name" email@gmail.com [team]`.

- If `"Full Name"` and `email@gmail.com` are provided, update `GIT_USERNAME` and `GIT_EMAIL` in `.env` before starting (never touch `GITHUB_PAT` or print it).
- If `team` is provided as the third token (one of `frontend`, `backend`, `data-engineering`, `sre`), write or overwrite `TEAM=<team>` in `.env`.
- If `$ARGUMENTS` is empty, use the existing `.env` values as-is. If `.env` is missing or required keys are placeholders, stop and ask the user to provide them.

## Task
Use the **onboarding-orchestrator** subagent to run the onboarding pipeline.

It must first load/create `onboarding-session.json`, determine the team from `TEAM` in
`.env`, and **resume from the first unfinished step** (skipping any already `done`), then
execute these specialists **sequentially**, stopping on the first failure:

### Common steps (all teams, 1–10)
1. **machine-configurer** → writes `machine_config.json`
2. **xcode-installer** → Xcode Command Line Tools
3. **homebrew-installer** → Homebrew + PATH
4. **git-configurer** → installs git, sets global identity from `.env` (`GIT_USERNAME` / `GIT_EMAIL`)
5. **github-ssh-configurer** → generates/uploads the SSH key to GitHub using the PAT + email from `.env`, then verifies with `ssh -T git@github.com`
6. **editor-installer** → installs VS Code + Cursor via Homebrew casks (non-interactive) + their `code`/`cursor` CLIs
7. **postgres-installer** → installs PostgreSQL via Homebrew
8. **aws-vpn-installer** → installs the AWS VPN Client, adds the **Pattern** profile, opens the app for the user to click **Connect** + complete SSO/MFA
9. **aws-cli-configurer** → installs AWS CLI + session-manager-plugin, writes `dev` + `prod` SSO profiles (shared `pattern` session), adds the `ssm()` helper, runs one `aws sso login` (opens browser, blocks until M365/MFA done), verifies both profiles
10. **ticket-raiser** → raises onboarding tickets in the project management system *(TBD)*

### Track 11 — Frontend (`TEAM=frontend`)
11.1. **repo-cloner** → reads repo list from `config.yaml`, clones each into `PREFERRED_REPOSITORIES_LOCATION`
11.2. **repo-setup-frontend** → installs nvm + Node + pnpm, runs `pnpm install`, installs VS Code extensions for the pattern-exp frontend monorepo

### Track 12 — Backend (`TEAM=backend`)
12.1. **rbenv-installer** → installs rbenv + ruby-build, initializes in `~/.zshrc`
12.2. **repo-cloner** → reads repo list from `config.yaml`, clones each into `PREFERRED_REPOSITORIES_LOCATION`
12.3. **repo-setup-backend** → for every cloned Rails repo: installs correct Ruby, bundles gems (private gems via tokens in `.env`), creates/migrates DB, verifies server boots

### Track 13 — Data Engineering (`TEAM=data-engineering`)
13.1. **podman-installer** → installs and configures Podman *(TBD)*
13.2. **repo-cloner** → reads repo list from `config.yaml`, clones each into `PREFERRED_REPOSITORIES_LOCATION`
13.3. **repo-setup-data-engineering** → sets up data engineering repos *(TBD)*

### Track 14 — SRE (`TEAM=sre`)
14.1. **repo-cloner** → reads repo list from `config.yaml`, clones each into `PREFERRED_REPOSITORIES_LOCATION` (for SRE, ensure `github.repos` includes `sre-utils`)
14.2. **repo-setup-sre-backend** → ensures Python (Homebrew), ensures the AWS CLI (delegates to **aws-cli-configurer** if missing), runs `sre-utils/ssologin.py` to create the AWS SSO profiles, installs the tools pinned in `config.yaml` (`sre.tools`: terraform, node, ruby, golang — latest when unpinned), and ensures Podman (delegates to **podman-installer** if missing). Falls back to self-cloning `sre-utils` if 14.1 didn't.

Each specialist records its own result (`done`/`failed`) in `onboarding-session.json`;
the orchestrator owns the file and the resume logic.

When the orchestrator finishes, surface its `onboarding-report.md` summary here: which
steps passed, which failed/remain, and any remediation needed. If the run stopped early,
remind the user that re-running `/onboard` resumes from where it left off.
