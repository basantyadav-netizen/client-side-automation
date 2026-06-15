---
description: Run the full new-employee macOS onboarding pipeline (machine config → Xcode CLT → Homebrew → git)
argument-hint: "[optional: \"Full Name\" email@gmail.com]"
allowed-tools: Agent, Bash, Read
model: opus
---

# /onboard — New employee onboarding

## Preflight context
- OS: !`uname -s`
- Architecture: !`uname -m`
- basic_info.json present: !`test -f basic_info.json && echo yes || echo "NO — create it first"`
- Existing machine_config.json: !`test -f machine_config.json && echo "exists (will be refreshed)" || echo none`

## Optional argument handling
Arguments passed: `$ARGUMENTS`

If `$ARGUMENTS` is non-empty, treat it as `"Full Name" email@gmail.com` and write/update
`basic_info.json` with those values **before** starting, e.g.:
```json
{ "git_username": "Full Name", "git_email": "email@gmail.com" }
```
If `$ARGUMENTS` is empty, use the existing `basic_info.json` as-is. If neither exists,
stop and ask the user to provide the identity.

## Task
Use the **onboarding-orchestrator** subagent to run the onboarding pipeline.

It must execute these specialists **sequentially**, stopping on the first failure:
1. **machine-configurer** → writes `machine_config.json`
2. **xcode-installer** → Xcode Command Line Tools
3. **homebrew-installer** → Homebrew + PATH
4. **git-configurer** → installs git, sets global identity from `basic_info.json`

When the orchestrator finishes, surface its `onboarding-report.md` summary here: which
steps passed, which failed, and any remediation needed.
