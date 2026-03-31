#!/usr/bin/env bash

# Exit on error
set -e

function shutdown() {
  trap - INT TERM EXIT
  echo "Shutting down"
}

trap shutdown INT TERM EXIT
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
bundle install
source "$REPO_ROOT/scripts/bash_helpers/migrations.sh"
run_next_migration_file_if_present

