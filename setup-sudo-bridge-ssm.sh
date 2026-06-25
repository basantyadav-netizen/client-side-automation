#!/usr/bin/env bash
# One-time setup so the onboarding agents can install the AWS Session Manager plugin
# without a password prompt. (Separate from setup-sudo-bridge.sh for the AWS VPN pkg and
# setup-sudo-bridge-homebrew.sh for the Homebrew prefix.)
#
# WHY THIS EXISTS
#   Claude Code runs each agent command in a NO-TTY shell (`tty` -> "not a tty").
#   `sudo` can't prompt for a password without a terminal, so the session-manager-plugin
#   cask's internal `installer` step fails with "a terminal is required to read the
#   password".
#
#   This installs a TIGHTLY SCOPED sudoers rule that lets `installer` run as root
#   WITHOUT a password -- but ONLY for the session-manager-plugin pkg, nothing else.
#   Because no password is needed, no terminal is needed, so the no-tty agent shell works.
#
# SECURITY NOTE
#   This grants silent root for exactly one action: installing the session-manager-plugin
#   pkg from Homebrew's Caskroom to "/". It does NOT grant general passwordless sudo.
#   Review the rule below before running. Remove anytime with:
#     sudo rm /etc/sudoers.d/aws-cli-configurer
#
# PORTABILITY
#   Nothing here is tied to a specific machine: the username comes from `whoami`, the
#   sudoers host field is `ALL`, and the Caskroom prefix is auto-detected from the CPU
#   arch (Apple Silicon -> /opt/homebrew, Intel -> /usr/local). The rule globs `*/*.pkg`
#   within the session-manager-plugin Caskroom dir -- scoped to that one cask, but portable
#   across versions.
#
# USAGE
#   Run this ONCE, in a normal terminal (you'll type your password once):
#     bash setup-sudo-bridge-ssm.sh
set -euo pipefail

U="$(whoami)"
DROPIN="/etc/sudoers.d/aws-cli-configurer"

# Auto-detect the Homebrew prefix for THIS machine (portable across Apple Silicon/Intel).
case "$(uname -m)" in
  arm64) PREFIX="/opt/homebrew" ;;   # Apple Silicon
  *)     PREFIX="/usr/local"    ;;   # Intel
esac

# NOPASSWD -> no password needed (works in the agent's no-tty shell).
# SETENV   -> Homebrew runs `sudo -E ...` (preserve environment); without SETENV sudo
#             rejects it with "sorry, you are not allowed to preserve the environment".
# `*/*.pkg` matches the version dir + the pkg name inside the session-manager-plugin cask
# dir (version-portable). `*` never crosses `/`, so it stays within that one cask's dir.
RULE="${U} ALL=(root) NOPASSWD: SETENV: /usr/sbin/installer -pkg ${PREFIX}/Caskroom/session-manager-plugin/*/*.pkg -target /"

echo "About to install this sudoers rule to ${DROPIN}:"
echo "  ${RULE}"
echo

# Write to a temp file, validate it, then install atomically. Never edit sudoers in
# place without validating -- a syntax error can lock you out of sudo.
TMP="$(mktemp)"
printf '%s\n' "$RULE" > "$TMP"

if ! sudo visudo -cf "$TMP"; then
  echo "ERROR: rule failed validation; not installing." >&2
  rm -f "$TMP"
  exit 1
fi

sudo install -m 0440 -o root -g wheel "$TMP" "$DROPIN"
rm -f "$TMP"

# Final sanity check on the installed file.
sudo visudo -cf "$DROPIN" && echo "OK -- sudo bridge installed at ${DROPIN}"
echo "The aws-cli-configurer agent can now install the session-manager-plugin with no password prompt."
