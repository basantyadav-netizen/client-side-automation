---
description: Run the full new-employee macOS onboarding pipeline (machine config → Xcode CLT → Homebrew → git → GitHub SSH → VS Code); resumable
argument-hint: "[optional: \"Full Name\" email@gmail.com]"
allowed-tools: Agent, Bash, Read
model: opus
---

# /onboard — New employee onboarding

## Preflight context
- OS: !`uname -s`
- Architecture: !`uname -m`
- .env present: !`test -f .env && echo yes || echo "NO — create it with GIT_USERNAME, GIT_EMAIL, GITHUB_PAT, GITHUB_EMAIL"`
- git identity set in .env: !`grep -qE '^GIT_USERNAME=.+' .env 2>/dev/null && grep -qE '^GIT_EMAIL=.+' .env 2>/dev/null && echo yes || echo "NO — add GIT_USERNAME / GIT_EMAIL"`
- Existing machine_config.json: !`test -f machine_config.json && echo "exists (will be refreshed)" || echo none`
- Existing session: !`test -f onboarding-session.json && echo "found — run will RESUME from the first unfinished step" || echo "none — fresh run"`

## Optional argument handling
Arguments passed: `$ARGUMENTS`

If `$ARGUMENTS` is non-empty, treat it as `"Full Name" email@gmail.com` and update the
`GIT_USERNAME` and `GIT_EMAIL` lines in `.env` with those values **before** starting
(edit only those two keys; never touch `GITHUB_PAT` or print it).
If `$ARGUMENTS` is empty, use the existing `.env` values as-is. If `.env` is missing or
those keys are placeholders, stop and ask the user to provide the identity.

## Task
Use the **onboarding-orchestrator** subagent to run the onboarding pipeline.

It must first load/create `onboarding-session.json` and **resume from the first
unfinished step** (skipping any already `done`), then execute these specialists
**sequentially**, stopping on the first failure:
1. **machine-configurer** → writes `machine_config.json`
2. **xcode-installer** → Xcode Command Line Tools
3. **homebrew-installer** → Homebrew + PATH
4. **git-configurer** → installs git, sets global identity from `.env` (`GIT_USERNAME` / `GIT_EMAIL`)
5. **github-ssh-configurer** → generates/uploads the SSH key to GitHub using the PAT +
   email from `.env`, then verifies with `ssh -T git@github.com`
6. **vscode-installer** → installs VS Code via Homebrew cask (non-interactive) + the `code` CLI

Each specialist records its own result (`done`/`failed`) in `onboarding-session.json`;
the orchestrator owns the file and the resume logic.

When the orchestrator finishes, surface its `onboarding-report.md` summary here: which
steps passed, which failed/remain, and any remediation needed. If the run stopped early,
remind the user that re-running `/onboard` resumes from where it left off.
