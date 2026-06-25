#!/usr/bin/env bash
# One-time setup so the onboarding agents can (a) bootstrap Homebrew and
# (b) install the AWS VPN Client — both without a password prompt.
#
# WHY THIS EXISTS
#   Claude Code runs agent commands in a NO-TTY shell (`tty` -> "not a tty"), so
#   `sudo` can't prompt for a password. Two onboarding steps need root silently:
#
#   1. HOMEBREW BOOTSTRAP — on a brand-new Mac, Homebrew's install.sh needs root
#      once to create and own its prefix (/opt/homebrew on Apple Silicon, /usr/local
#      on Intel). Two pinned rules cover this:
#        • /bin/mkdir -p <prefix>
#        • /usr/sbin/chown -R <you>:admin <prefix>
#      After those run, the official install.sh needs no further sudo.
#
#   2. AWS VPN CLIENT — Homebrew's aws-vpn-client cask calls
#        sudo installer -pkg .../*.pkg -target /
#      with `-E` (env-preserving), which requires SETENV in the sudoers rule.
#      Without this rule the cask install fails with "a terminal is required to
#      read the password" because there is no TTY available.
#
# SECURITY
#   NOT blanket sudo. Every rule is pinned to exactly the path(s) it needs:
#     • mkdir / chown are locked to the Homebrew prefix only.
#     • installer is locked to the aws-vpn-client Caskroom dir only.
#   `*` in the installer rule matches the version dir + pkg filename within that
#   one cask directory and never crosses a `/` boundary into other paths.
#   Remove all rules at once with:
#     sudo rm /etc/sudoers.d/onboarding-bridge
#
# PORTABILITY
#   The username comes from `whoami`. The Homebrew prefix and Caskroom path are
#   auto-detected from the CPU architecture (Apple Silicon -> /opt/homebrew,
#   Intel -> /usr/local). Safe to run on any Mac as-is.
#
# USAGE (run once, in a normal terminal — you'll type your password that one time):
#   bash setup-sudo-bridge.sh
set -euo pipefail

U="$(whoami)"
DROPIN="/etc/sudoers.d/onboarding-bridge"

# Auto-detect the Homebrew prefix for THIS machine.
case "$(uname -m)" in
  arm64) PREFIX="/opt/homebrew" ;;   # Apple Silicon
  *)     PREFIX="/usr/local"    ;;   # Intel
esac

RULES=(
  # --- Homebrew bootstrap ---
  # Pre-create and own the prefix so install.sh needs no further sudo.
  "${U} ALL=(root) NOPASSWD: /bin/mkdir -p ${PREFIX}"
  "${U} ALL=(root) NOPASSWD: /usr/sbin/chown -R ${U}\\:admin ${PREFIX}"

  # --- AWS VPN Client installer ---
  # Homebrew runs `sudo -E installer ...`; SETENV lets it preserve the environment.
  # `*/*.pkg` = version-dir / arch-specific pkg inside the aws-vpn-client cask dir.
  "${U} ALL=(root) NOPASSWD: SETENV: /usr/sbin/installer -pkg ${PREFIX}/Caskroom/aws-vpn-client/*/*.pkg -target /"
)

# Write to a temp file, validate it, then install atomically. Never edit sudoers in
# place without validating -- a syntax error can lock you out of sudo.
TMP="$(mktemp)"
{
  echo "# Managed by setup-sudo-bridge.sh -- do not edit by hand."
  echo "# Covers: Homebrew prefix bootstrap + AWS VPN Client cask install."
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

sudo visudo -cf "$DROPIN" && echo "OK -- onboarding sudo bridge installed at ${DROPIN}"
echo "Homebrew bootstrap and AWS VPN Client install can now run without a password prompt."

# Clean up the old separate dropins if they exist.
for OLD in aws-vpn-installer homebrew-bootstrap; do
  OLD_PATH="/etc/sudoers.d/${OLD}"
  if [ -f "$OLD_PATH" ]; then
    sudo rm "$OLD_PATH"
    echo "Removed old dropin: ${OLD_PATH}"
  fi
done
