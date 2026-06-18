#!/usr/bin/env bash
# One-time setup so the onboarding agents can BOOTSTRAP Homebrew on a fresh Mac without
# a password prompt. (Separate from setup-sudo-bridge.sh, which covers the AWS VPN pkg.)
#
# WHY THIS EXISTS
#   Claude Code runs agent commands in a NO-TTY shell (`tty` -> "not a tty"), so `sudo`
#   can't prompt for a password. On a brand-new Mac (no Homebrew yet), installing
#   Homebrew needs root for exactly ONE thing: creating and owning its prefix
#   /opt/homebrew (which lives under root-owned /opt). Once that directory is user-owned,
#   the official install.sh runs with NO further sudo.
#
#   So this grants passwordless root for TWO commands, PINNED to /opt/homebrew only:
#     - /bin/mkdir -p /opt/homebrew
#     - /usr/sbin/chown -R <you>:admin /opt/homebrew
#   ...and nothing else.
#
# HOW IT'S USED (pairs with a step in the homebrew-installer agent)
#   Before running install.sh, the agent detects the same prefix and pre-creates + owns it:
#     case "$(uname -m)" in arm64) P=/opt/homebrew;; *) P=/usr/local;; esac
#     [ -d "$P" ] || sudo /bin/mkdir -p "$P"
#     sudo /usr/sbin/chown -R "$(whoami):admin" "$P"
#   Then `NONINTERACTIVE=1 .../install.sh` needs no sudo. Without that agent step, this
#   bridge sits unused -- the stock install.sh runs its OWN sudo sequence, which this
#   bridge deliberately does NOT cover (pinning those varying commands would be unsafe).
#
# PORTABILITY
#   Nothing here is tied to a specific machine: the username comes from `whoami`, the
#   sudoers host field is `ALL` (any host), and the Homebrew prefix is auto-detected from
#   the CPU architecture (Apple Silicon -> /opt/homebrew, Intel -> /usr/local). So this
#   script can be copied to and run on any Mac as-is.
#
# SECURITY
#   NOT blanket sudo. Both rules are pinned to the Homebrew prefix only; they cannot
#   create or chown any other path. Remove anytime with:
#     sudo rm /etc/sudoers.d/homebrew-bootstrap
#
# USAGE (run once, in a normal terminal -- you'll type your password that one time):
#   bash setup-sudo-bridge-homebrew.sh
set -euo pipefail

U="$(whoami)"
DROPIN="/etc/sudoers.d/homebrew-bootstrap"

# Auto-detect the Homebrew prefix for THIS machine (portable across Apple Silicon/Intel).
case "$(uname -m)" in
  arm64) PREFIX="/opt/homebrew" ;;   # Apple Silicon
  *)     PREFIX="/usr/local"    ;;   # Intel
esac

# Pinned to the prefix only. No SETENV needed: the agent runs these as plain `sudo mkdir`
# / `sudo chown` (no `-E`), unlike Homebrew's cask installer which needs SETENV.
# NOTE: the ':' in user:admin MUST be backslash-escaped in sudoers (':' is a special
# char there). `${U}\:admin` parses correctly and still matches the agent's literal
# `chown -R user:admin` command.
RULES=(
  "${U} ALL=(root) NOPASSWD: /bin/mkdir -p ${PREFIX}"
  "${U} ALL=(root) NOPASSWD: /usr/sbin/chown -R ${U}\\:admin ${PREFIX}"
)

# Render to a temp file with a header, validate, then install atomically. NEVER edit
# sudoers in place without validating -- a syntax error can lock you out of sudo.
TMP="$(mktemp)"
{
  echo "# Managed by setup-sudo-bridge-homebrew.sh -- do not edit by hand."
  echo "# Lets onboarding agents bootstrap the Homebrew prefix without a password."
  printf '%s\n' "${RULES[@]}"
} > "$TMP"

echo "About to install these sudoers rules to ${DROPIN}:"
sed 's/^/  /' "$TMP"
echo

if ! sudo visudo -cf "$TMP"; then
  echo "ERROR: rules failed validation; not installing." >&2
  rm -f "$TMP"
  exit 1
fi

sudo install -m 0440 -o root -g wheel "$TMP" "$DROPIN"
rm -f "$TMP"

sudo visudo -cf "$DROPIN" && echo "OK -- homebrew sudo bridge installed at ${DROPIN}"
echo "The homebrew-installer agent can now create/own ${PREFIX} without a password prompt."
