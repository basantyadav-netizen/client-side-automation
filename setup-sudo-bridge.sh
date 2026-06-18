#!/usr/bin/env bash
# One-time setup so the onboarding agents can install the AWS VPN Client without a
# password prompt.
#
# WHY THIS EXISTS
#   Claude Code runs each agent command in a NO-TTY shell (`tty` -> "not a tty").
#   `sudo` can't prompt for a password without a terminal, so the AWS VPN cask's
#   internal `installer` step fails with "a terminal is required to read the password".
#
#   This installs a TIGHTLY SCOPED sudoers rule that lets `installer` run as root
#   WITHOUT a password -- but ONLY for the AWS VPN Client pkg, nothing else. Because
#   no password is needed, no terminal is needed, so the no-tty agent shell works.
#
# SECURITY NOTE
#   This grants silent root for exactly one action: installing the aws-vpn-client pkg
#   from Homebrew's Caskroom to "/". It does NOT grant general passwordless sudo.
#   Review the rule below before running. Remove anytime with:
#     sudo rm /etc/sudoers.d/aws-vpn-installer
#
# PORTABILITY
#   Nothing here is tied to a specific machine: the username comes from `whoami`, the
#   sudoers host field is `ALL`, and the Caskroom prefix is auto-detected from the CPU
#   arch (Apple Silicon -> /opt/homebrew, Intel -> /usr/local). The pkg filename differs
#   by arch (AWS_VPN_Client_ARM64.pkg vs the Intel build), so the rule globs `*.pkg`
#   within the aws-vpn-client Caskroom dir -- still scoped to that one cask, but portable.
#
# USAGE
#   Run this ONCE, in a normal terminal (you'll type your password once):
#     bash setup-sudo-bridge.sh
set -euo pipefail

U="$(whoami)"
DROPIN="/etc/sudoers.d/aws-vpn-installer"

# Auto-detect the Homebrew prefix for THIS machine (portable across Apple Silicon/Intel).
case "$(uname -m)" in
  arm64) PREFIX="/opt/homebrew" ;;   # Apple Silicon
  *)     PREFIX="/usr/local"    ;;   # Intel
esac

# NOPASSWD -> no password needed (works in the agent's no-tty shell).
# SETENV   -> Homebrew runs `sudo -E ...` (preserve environment); without SETENV sudo
#             rejects it with "sorry, you are not allowed to preserve the environment".
# `*/*.pkg` matches the version dir + any pkg name inside the aws-vpn-client cask dir
# (arch-portable). `*` never crosses `/`, so it stays within that one cask's directory.
RULE="${U} ALL=(root) NOPASSWD: SETENV: /usr/sbin/installer -pkg ${PREFIX}/Caskroom/aws-vpn-client/*/*.pkg -target /"

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
echo "The aws-vpn-installer agent can now install the VPN client with no password prompt."
