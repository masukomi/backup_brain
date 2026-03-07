#!/usr/bin/env bash

REPO_ROOT=$(git rev-parse --show-toplevel)

source "$REPO_ROOT/scripts/bash_helpers/colors.sh"
source "$REPO_ROOT/scripts/bash_helpers/get_env_key.sh"
source "$REPO_ROOT/scripts/bash_helpers/migrations.sh"

echo "DB schema version is "$(get_schema_version)

run_next_migration_file_if_present
