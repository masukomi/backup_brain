#!/usr/bin/env bash
set -euo pipefail
YELLOW=$'\e[1;33m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
RESET=$'\033[0m'

function echoerr()  { echo "$RED$@$RESET" 1>&2; }
function echowarn() { echo "$YELLOW$@$RESET" 1>&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Repo root ─────────────────────────────────────────────────────────────────
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
echo "Repo root: $REPO_ROOT"
echo ""

# ── Username ──────────────────────────────────────────────────────────────────
DEFAULT_USER="$(whoami)"
printf "Username to run services as [%s]: " "$DEFAULT_USER"
read -r input_user
SERVICE_USER="${input_user:-$DEFAULT_USER}"

# ── Group ─────────────────────────────────────────────────────────────────────
DEFAULT_GROUP="$(id -gn)"
printf "Group to run services as [%s]: " "$DEFAULT_GROUP"
read -r input_group
SERVICE_GROUP="${input_group:-$DEFAULT_GROUP}"

# ── Tailscale Funnel ──────────────────────────────────────────────────────────
echo ""
printf "Are you using Tailscale Funnel to expose Backup Brain? [y/N]: "
read -r tailscale_choice
USE_TAILSCALE=false
[[ "${tailscale_choice:-n}" =~ ^[Yy]$ ]] && USE_TAILSCALE=true

# ── RAILS_ENV ─────────────────────────────────────────────────────────────────
echo ""
echo "Should Backup Brain run in development or production mode?"
echo "  1) development (default)"
echo "  2) production"
printf "Choice [1]: "
read -r rails_env_choice
case "${rails_env_choice:-1}" in
  2) RAILS_ENV="production" ;;
  *) RAILS_ENV="development" ;;
esac
echo "Setting RAILS_ENV=$RAILS_ENV"

# ── Meilisearch master key ────────────────────────────────────────────────────
echo ""
echo "Meilisearch master key — will be written into /etc/meilisearch.toml."
echo "Generate one with: openssl rand -base64 32 | sed 's/=*\$//'"
while true; do
  printf "Master key: "
  read -r MEILI_MASTER_KEY
  [[ -n "$MEILI_MASTER_KEY" ]] && break
  echoerr "Master key cannot be empty."
done

# ── Build substituted copies in a temp directory ──────────────────────────────
WORK_DIR="$(mktemp -d -p "$SCRIPT_DIR" -t bb_systemd_services)"
KEEP_WORK_DIR=false
trap '[[ "$KEEP_WORK_DIR" == "false" ]] && rm -rf "$WORK_DIR"' EXIT


echo ""
echo "Applying substitutions and writing configured files to:"
echo "    $WORK_DIR"

for src in "$SCRIPT_DIR"/*.service; do
  filename="$(basename "$src")"

  if [[ "$filename" == "tailscale_funnel.service" ]]; then
    $USE_TAILSCALE || continue
  fi
  sed \
    -e "s|YOUR_USERNAME|$SERVICE_USER|g" \
    -e "s|USER_GROUP|$SERVICE_GROUP|g" \
    -e "s|/path/to/backup_brain|$REPO_ROOT|g" \
    -e "s|RAILS_ENV=development|RAILS_ENV=$RAILS_ENV|g" \
    "$src" > "$WORK_DIR/$filename"
done

# meilisearch.toml — substitute master key only; all other settings are defaults
sed \
  -e "s|YOUR_MASTER_KEY_VALUE|$MEILI_MASTER_KEY|g" \
  "$SCRIPT_DIR/meilisearch.toml" > "$WORK_DIR/meilisearch.toml"

# ── Offer to install ──────────────────────────────────────────────────────────
echo ""
echo "Service files are ready."
echo ""
printf "Copy files to /etc/systemd/system/ and enable services now? [y/N]: "
read -r install_choice

if [[ "${install_choice:-n}" =~ ^[Yy]$ ]]; then
  ENABLED=()

  for svc in "$WORK_DIR"/*.service; do
    filename="$(basename "$svc")"
    sudo cp "$svc" /etc/systemd/system/
    echo "Copied: $filename → /etc/systemd/system/$filename"
  done

  sudo cp "$WORK_DIR/meilisearch.toml" /etc/meilisearch.toml
  echo "Copied: meilisearch.toml → /etc/meilisearch.toml"

  sudo systemctl daemon-reload
  echo "Reloaded systemd daemon."
  echo ""

  for svc in "$WORK_DIR"/*.service; do
    filename="$(basename "$svc")"
    label="${filename%.service}"

    # backup_brain_delayed_job@.service is a template — it is started automatically via
    # backup_brain.service's Wants= directive; enabling it directly would fail.
    [[ "$label" == "backup_brain_delayed_job@" ]] && continue

    sudo systemctl enable --now "$label"
    echo "Enabled and started: $label"
    ENABLED+=("$label")
  done

  echo ""
  echo "Done. ${#ENABLED[@]} service(s) enabled."

  echo ""
  printf "Delete the temporary directory with the configured files? [y/N]: "
  read -r delete_tmp_choice
  if [[ "${delete_tmp_choice:-n}" =~ ^[Yy]$ ]]; then
    rm -rf "$WORK_DIR"
    KEEP_WORK_DIR=false
  else
    KEEP_WORK_DIR=true
    echowarn "Keeping temporary files at: $WORK_DIR"
  fi

  cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Managing the Services
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Start / stop / restart the app (also starts/stops delayed_job workers)
  sudo systemctl start backup_brain
  sudo systemctl stop backup_brain
  sudo systemctl restart backup_brain

  # Check status
  sudo systemctl status backup_brain
  sudo systemctl status "backup_brain_delayed_job@*"

  # View logs
  journalctl -u backup_brain -f
  journalctl -u "backup_brain_delayed_job@1" -f

  # Reload systemd after manually editing a service file
  sudo systemctl daemon-reload

For additional troubleshooting information see:
EOF
  echo "  $SCRIPT_DIR/README.org"

else
  echo ""
  KEEP_WORK_DIR=true
  echowarn "Files were not copied."
  echo "You can inspect the changes in the temp directory at"
  echo "    $WORK_DIR"
  echo "When you're ready, run this script again and choose to copy at the prompt,"
  echo "or copy and enable manually:"
  echo ""
  echo "  sudo cp \"$WORK_DIR\"/*.service /etc/systemd/system/"
  echo "  sudo cp \"$WORK_DIR/meilisearch.toml\" /etc/meilisearch.toml"
  echo "  sudo systemctl daemon-reload"
  echo "  sudo systemctl enable --now backup_brain meilisearch"
  if $USE_TAILSCALE; then
    echo "  sudo systemctl enable --now tailscale_funnel"
  fi
  echo ""
  echowarn "⚠️  temp files have NOT been deleted."
  echowarn "⚠️  Be sure to run"
  echowarn "    rm -rf \"$WORK_DIR\""
  echowarn "to delete these temp files when you're done with them."
  echo ""
  echo "For additional troubleshooting information see:"
  echo "  $SCRIPT_DIR/README.org"
fi
