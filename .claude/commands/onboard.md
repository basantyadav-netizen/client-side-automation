---
description: Run the full new-employee macOS onboarding pipeline (machine config → Xcode CLT → Homebrew → git → GitHub SSH → editors: VS Code + Cursor → postgres → AWS VPN → rbenv → clone repos → setup repos → frontend → AWS CLI); resumable
argument-hint: "[optional: \"Full Name\" email@gmail.com]"
allowed-tools: Agent, Bash, Read
model: opus
---

# /onboard — New employee onboarding

## Preflight context
- OS: !`uname -s`
- Architecture: !`uname -m`
- .env present: !`test -f .env && echo yes || echo "NO — create it with GIT_USERNAME, GIT_EMAIL, GITHUB_PAT, GITHUB_EMAIL, PREFERRED_REPOSITORIES_LOCATION"`
- git identity set in .env: !`grep -qE '^GIT_USERNAME=.+' .env 2>/dev/null && grep -qE '^GIT_EMAIL=.+' .env 2>/dev/null && echo yes || echo "NO — add GIT_USERNAME / GIT_EMAIL"`
- repos location set in .env: !`grep -qE '^PREFERRED_REPOSITORIES_LOCATION=.+' .env 2>/dev/null && echo yes || echo "NO — add PREFERRED_REPOSITORIES_LOCATION (e.g. /Users/you/Repositories)"`
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
6. **editor-installer** → installs VS Code + Cursor via Homebrew casks (non-interactive) + their `code`/`cursor` CLIs
7. **postgres-installer** → installs PostgreSQL via Homebrew
8. **aws-vpn-installer** → installs the AWS VPN Client, adds the **Pattern** profile, opens the app for the user to click **Connect** + complete SSO/MFA (sudo handled by the one-time NOPASSWD bridge from `setup-sudo-bridge.sh`)
9. **rbenv-installer** → installs rbenv + ruby-build, initializes in `~/.zshrc`
10. **git-cloner** → reads repo list from `config.yaml`, clones each into the directory specified by `PREFERRED_REPOSITORIES_LOCATION` in `.env`
11. **repo-setup** → for every cloned Rails repo: installs correct Ruby, bundles gems (private gems via tokens in `.env`), creates/migrates DB, verifies server boots
12. **frontend-setup** → installs nvm + Node + pnpm, runs `pnpm install`, installs VS Code extensions for the pattern-exp frontend monorepo
13. **aws-cli-configurer** → installs AWS CLI + session-manager-plugin, writes `dev` + `prod` SSO profiles (shared `pattern` session), adds the `ssm()` helper, runs one `aws sso login` (opens browser, blocks until M365/MFA done), verifies both profiles

Each specialist records its own result (`done`/`failed`) in `onboarding-session.json`;
the orchestrator owns the file and the resume logic.

When the orchestrator finishes, surface its `onboarding-report.md` summary here: which
steps passed, which failed/remain, and any remediation needed. If the run stopped early,
remind the user that re-running `/onboard` resumes from where it left off.
