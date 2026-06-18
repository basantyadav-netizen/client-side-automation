# The sudo bridge — how `setup-sudo-bridge.sh` lets agents install without a password

This doc explains, end to end, how `setup-sudo-bridge.sh` lets the onboarding agents
install the AWS VPN Client **with no password prompt and no terminal**, why it's needed,
and why it's safe.

---

## 1. The problem

The onboarding agents run inside **Claude Code**, which executes every shell command in a
**non-interactive, no-TTY shell**:

```text
$ tty
not a tty
```

`sudo` normally reads your password from the terminal (TTY). With no TTY, it can't prompt,
so any command that needs root fails immediately with:

```text
sudo: a terminal is required to read the password; either use the -S option
to read from standard input or configure an askpass helper
```

The AWS VPN Client is a Homebrew **pkg-cask**. Installing it runs, under the hood:

```text
sudo /usr/sbin/installer -pkg .../AWS_VPN_Client_ARM64.pkg -target /
```

That `sudo` hits the no-TTY wall — so `brew install --cask aws-vpn-client` fails when an
agent runs it, even though it works fine when *you* run it in a normal terminal.

---

## 2. Approaches that do NOT work (and why)

| Attempt | Why it fails |
|---|---|
| Run `sudo -v` first to cache a credential | The cached credential is tied to the terminal's session (`tty_tickets`). The agent's no-TTY shell is a *different* session, so it can't see the cached credential. |
| Background keepalive (`while true; do sudo -n true; sleep 60; done`) | Same reason — it refreshes a credential the agent's shell can't reach. Also requires you to type your password to start it. |
| `Defaults !tty_tickets` (share credential across TTYs) | Tested — still didn't bridge into the no-TTY agent shell. |
| Run Claude from a "normal terminal" | The Bash tool still spawns commands detached with no controlling TTY, regardless of how Claude was launched. |

The common thread: they all try to give `sudo` a *credential to validate*, but the agent
shell has **no TTY to prompt on and no way to inherit the credential**.

---

## 3. The actual fix: don't make sudo prompt at all

The "a terminal is required" error **only happens when sudo needs to authenticate**. If a
**`NOPASSWD` sudoers rule** matches the command, sudo skips authentication entirely — so it
never needs a password, and therefore **never needs a TTY**. This is exactly how cron jobs
and scripts run privileged commands unattended.

So instead of bridging a credential into the no-TTY shell, we remove the *need* for one —
for **one specific command only**.

`setup-sudo-bridge.sh` installs this rule into `/etc/sudoers.d/aws-vpn-installer`:

```text
basant.kumar ALL=(root) NOPASSWD: SETENV: /usr/sbin/installer -pkg /opt/homebrew/Caskroom/aws-vpn-client/*/AWS_VPN_Client_ARM64.pkg -target /
```

### Anatomy of the rule

```text
basant.kumar      ALL = (root)   NOPASSWD: SETENV:   /usr/sbin/installer -pkg .../*/AWS_VPN_Client_ARM64.pkg -target /
└── who           └── on any     └── tags            └── the EXACT command (binary + args) this applies to
    (your user)       host, run
                      as root
```

- **`basant.kumar`** — the rule applies only to your user.
- **`(root)`** — the command may be run as root. Homebrew calls `sudo -u root …`, which matches.
- **`NOPASSWD:`** — **no password required.** This is what removes the TTY requirement.
- **`SETENV:`** — allows the caller to preserve/set environment variables. Homebrew runs
  the installer as `sudo -E …` (preserve environment); without `SETENV`, sudo rejects it with
  `sorry, you are not allowed to preserve the environment`. (See troubleshooting below — this
  was the final missing piece.)
- **The command** — pinned to the binary `/usr/sbin/installer`, the AWS VPN pkg path, and
  target `/`. The `*` matches the version directory only (a single path segment — sudo's
  wildcards do not cross `/`). The pkg filename is pinned exactly.

### Why no TTY is needed once the rule exists

There is no `requiretty` directive in this machine's sudoers (verified), so a `NOPASSWD`
command runs fine from a no-TTY shell. With nothing to prompt for and no TTY requirement,
the agent's `sudo /usr/sbin/installer …` just runs.

---

## 4. How the script installs the rule safely

A malformed `/etc/sudoers.d` file can lock you out of `sudo` entirely, so the script is
careful:

1. **Build the rule** with your real username (`$(whoami)`).
2. **Write to a temp file** first — never edit a live sudoers file in place.
3. **Validate** with `sudo visudo -cf <tmp>` — refuses to install if the syntax is bad.
4. **Atomic install** with `sudo install -m 0440 -o root -g wheel` — correct ownership
   (`root:wheel`) and permissions (`0440`, the only mode sudo accepts for drop-ins).
5. **Re-validate** the installed file as a final sanity check.

You run it **once**, in a normal terminal (so you can type your password that one time):

```bash
cd /Users/basant.kumar/client-side-automation
bash setup-sudo-bridge.sh
```

After that, the rule persists across reboots and runs — the agents never prompt again.

---

## 5. Security model

This is **not** blanket passwordless sudo. The grant is a single keyhole:

- ✅ Only your user.
- ✅ Only the binary `/usr/sbin/installer`.
- ✅ Only a pkg under `…/Caskroom/aws-vpn-client/<version>/AWS_VPN_Client_ARM64.pkg`.
- ✅ Only target `/`.
- ❌ Everything else (`sudo rm`, `sudo installer` on a different pkg, general `sudo`)
  still requires your password as normal.

Trade-off worth knowing: because Homebrew's Caskroom is user-writable, a process already
running as your user could, in principle, place a pkg at that path and have it installed as
root. If your user account is already compromised that's not your biggest problem — but it's
why the rule is scoped to one cask path rather than to `/usr/sbin/installer` generally.

---

## 6. Verify / inspect / remove

**Verify the rule is active** (lists your sudo privileges; the bridge line should appear):

```bash
sudo -l | grep aws-vpn-client
```

**Prove it end to end** (installs the VPN; idempotent — safe to re-run):

```bash
brew install --cask aws-vpn-client
```

A successful run prints `installer: The install was successful.` with **no password prompt**.

**Remove the bridge** at any time:

```bash
sudo rm /etc/sudoers.d/aws-vpn-installer
```

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `a terminal is required to read the password` | The bridge isn't installed (or the command didn't match the rule). | Run `bash setup-sudo-bridge.sh` once in a normal terminal. |
| `sorry, you are not allowed to preserve the environment` | The rule is missing the `SETENV:` tag, but Homebrew runs `sudo -E`. | Ensure the rule includes `SETENV:` (current script does). Re-run the setup script. |
| Works in your terminal but not from an agent | Expected — the agent shell has no TTY; that's the whole reason the bridge exists. | Confirm the bridge rule is installed (section 6). |
| Cask bumped to a different pkg filename | The pinned filename no longer matches. | Re-run `setup-sudo-bridge.sh` (update the filename in `RULE` if the name changed). |

---

## 8. One-line summary

> The agent shell has no TTY, so `sudo` can't ask for a password. Instead of trying to feed
> it one, `setup-sudo-bridge.sh` installs a tightly-scoped `NOPASSWD: SETENV:` sudoers rule
> for the single AWS VPN install command — so sudo never asks, never needs a TTY, and the
> install just runs.
