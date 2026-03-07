#!/usr/bin/env bash

if [ -e "$HOME/.rbenv/shims/bundle" ]; then
  PATH_TO_BUNDLE="$HOME/.rbenv/shims/bundle"
else
  PATH_TO_BUNDLE="bundle"
fi
set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/colors.sh

function get_schema_version() {
  echo "about to get schema_version" >&2
  schema_version=$($PATH_TO_BUNDLE exec rails runner "puts Setting.where(lookup_key: 'schema_version').first&.value" | tail -n1)

  if [ "$schema_version" == "" ]; then
    schema_version=1
  fi
  echo $schema_version
}

function get_next_schema_version() {
    schema_version=$(get_schema_version)
    let schema_version+=1
    echo $schema_version
}

function next_schema_migration_file() {
    next_schema_version=$(get_next_schema_version)
    echo "scripts/data_migrations/schema_"$next_schema_version"_migration.rb"
}

function run_next_migration_file_if_present(){
    next_migration_file=$(next_schema_migration_file)
    if [ -e $next_migration_file ]; then
        echo "Making sure gems are all loaded…"
        bundle install
        echo $YELLOW"Migration to schema_version $(get_next_schema_version) found. Running now."$NOCOLOR
        bundle exec rails runner $next_migration_file
    else
        echo "No pending migrations found."
    fi
}
