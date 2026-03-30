#!/usr/bin/env bash
set -euo pipefail
YELLOW=$'\e[1;33m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
RESET=$'\033[0m'

function echoerr() { echo "$RED$@$RESET" 1>&2; }
function echowarn() { echo "$YELLOW$@$RESET" 1>&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Repo root ────────────────────────────────────────────────────────────────
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
echo "Repo root: $REPO_ROOT"
echo ""

# ── Homebrew checks ──────────────────────────────────────────────────────────
HOMEBREW_MEILISEARCH=false
HOMEBREW_MONGODB=false

if command -v brew &>/dev/null; then
  if brew list --formula 2>/dev/null | grep -q "^meilisearch$"; then
    HOMEBREW_MEILISEARCH=true
    echo "Meilisearch is installed via Homebrew — its plist will not be copied."
    echo "Use 'brew services start meilisearch' to manage it."
  fi
  if brew list --formula 2>/dev/null | grep -qE "^mongodb(-community.*)?$"; then
    HOMEBREW_MONGODB=true
    echo "MongoDB is installed via Homebrew — use 'brew services start mongodb-community' to manage it."
  fi
  if $HOMEBREW_MEILISEARCH || $HOMEBREW_MONGODB; then
    echo ""
  fi
else
  echo "Homebrew not found — skipping Homebrew service checks."
  echo ""
fi

# ── Tailscale Funnel ─────────────────────────────────────────────────────────
printf "Are you using Tailscale Funnel to expose Backup Brain? [y/N]: "
read -r tailscale_choice
USE_TAILSCALE=false
[[ "${tailscale_choice:-n}" =~ ^[Yy]$ ]] && USE_TAILSCALE=true

# ── RAILS_ENV ────────────────────────────────────────────────────────────────
echo ""
echo "Should Backup Brain run in development or production mode when run from launchd?"
echo "  1) development (default)"
echo "  2) production"
printf "Choice [1]: "
read -r rails_env_choice
case "${rails_env_choice:-1}" in
  2) RAILS_ENV="production" ;;
  *) RAILS_ENV="development" ;;
esac
echo "Setting RAILS_ENV=$RAILS_ENV"

# ── Copy plists to temp dir with all substitutions applied in one pass ─────────
WORK_DIR="$(mktemp -d -p "$SCRIPT_DIR" -t bb_launchd_services)"
KEEP_WORK_DIR=false
trap '[[ "$KEEP_WORK_DIR" == "false" ]] && rm -rf "$WORK_DIR"' EXIT

echo ""
echo "Applying substitutions and writing configured files to:"
echo "    $WORK_DIR"

for src_plist in "$SCRIPT_DIR"/app.backup_brain.*.plist; do
  filename="$(basename "$src_plist")"
  dest="$WORK_DIR/$filename"

  if [[ "$filename" == "app.backup_brain.tailscale_funnel.plist" ]]; then
    $USE_TAILSCALE || continue
  fi
  sed \
    -e "s|/path/to/backup_brain|$REPO_ROOT|g" \
    -e "s|<string>development</string>|<string>$RAILS_ENV</string>|g" \
    "$src_plist" > "$dest"
done

# ── Offer to install ─────────────────────────────────────────────────────────
echo ""
echo "Plist files are ready."
echo ""
printf "Copy plist files to ~/Library/LaunchAgents/ and load them now? [y/N]: "
read -r install_choice

if [[ "${install_choice:-n}" =~ ^[Yy]$ ]]; then
  mkdir -p ~/Library/LaunchAgents

  LOADED=()

  for plist in "$WORK_DIR"/app.backup_brain.*.plist; do
    filename="$(basename "$plist")"
    label="${filename%.plist}"

    dest=~/Library/LaunchAgents/"$filename"
    cp "$plist" "$dest"

    # Unload first in case it was previously loaded, ignore errors
    launchctl unload "$dest" 2>/dev/null || true

    launchctl load "$dest"
    echo "Loaded: $label"
    LOADED+=("$label")
  done

  echo ""
  echo "Done. ${#LOADED[@]} agent(s) loaded."

  echo ""
  printf "Delete the temporary directory with the configured plist files? [y/N]: "
  read -r delete_tmp_choice
  if [[ "${delete_tmp_choice:-n}" =~ ^[Yy]$ ]]; then
    rm -rf "$WORK_DIR"
    KEEP_WORK_DIR=false
  else
    KEEP_WORK_DIR=true
    echowarn "Keeping temporary files at: $WORK_DIR"
  fi
  # ── Managing the services ────────────────────────────────────────────────────
  cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Managing the Services
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Start a service
  launchctl start app.backup_brain.app

  # Stop a service (will restart on next login; use 'unload' to stop permanently)
  launchctl stop app.backup_brain.app

  # Unload (disable autostart) and stop
  launchctl unload ~/Library/LaunchAgents/app.backup_brain.app.plist

  # Re-load after editing a plist
  launchctl unload ~/Library/LaunchAgents/app.backup_brain.app.plist
  launchctl load   ~/Library/LaunchAgents/app.backup_brain.app.plist

  # Check which services are running
  launchctl list | grep backup_brain

The three columns in launchctl list output are: PID, last exit status, label.
A PID of '-' means not running; a non-zero exit status means it crashed or
failed to start.

For additional troubleshooting information see:
EOF
echo "  $SCRIPT_DIR/README.org"
else
  echo ""
  KEEP_WORK_DIR=true
  echowarn "Files were not copied. "
  echo "You can inspect the changes in the temp directory at "
  echo "    $WORK_DIR"
  echo "When you're ready, run this script again and"
  echo "choose to copy at the prompt, or copy and load manually:"
  echo ""
  echo "  cp \"$WORK_DIR\"/app.backup_brain.*.plist ~/Library/LaunchAgents/"
  echo "  launchctl load ~/Library/LaunchAgents/app.backup_brain.app.plist"
  echo "  launchctl load ~/Library/LaunchAgents/app.backup_brain.delayed_job.1.plist"
  echo "  launchctl load ~/Library/LaunchAgents/app.backup_brain.delayed_job.2.plist"
  echo ""
  echowarn "⚠️ temp files have NOT been deleted."
  echowarn "⚠️ Be sure to run "
  echowarn "    rm -rf \"$WORK_DIR\""
  echowarn "to delete these temp files when you're done with them."
  echo "For additional troubleshooting information see:"
  echo "  $SCRIPT_DIR/README.org"
fi

