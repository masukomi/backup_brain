#!/usr/bin/env bash
#
# docs here: https://www.mongodb.com/docs/database-tools/mongoexport/

# MONGODB_URL tells us where to find the database
# If you don't set it in your environment, we'll just assume
# it's running on the default port on localhost.
#
# A connection string might look like this
# mongodb://mongodb0.example.com:27017/reporting
# The form is documented here:
# https://www.mongodb.com/docs/manual/reference/connection-string/

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/bash_helpers/colors.sh
# Always <repo root>/mongo_exports, no matter where this is run from.
# export.sh writes to the same place.
EXPORTS_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)/mongo_exports"

# Inside and outside of the bb_mongodb docker container
# AND in the host OS
# we want to connect to localhost
MONGODB_URL=mongodb://localhost:27017
if [[ -z ${DATABASE_NAME:-""} ]]; then
    DATABASE_NAME="backup_brain_development"
fi

echo "Importing to the \"$DATABASE_NAME\" database found on"
echo "$MONGODB_URL"
echo "from $EXPORTS_DIR"
echo "----------------------------------------------"

if [ ! -d "$EXPORTS_DIR" ]; then
  echo $RED"‼ $EXPORTS_DIR doesn't exist. Nothing to import."$NOCOLOR
  echo "Copy the mongo_exports directory produced by export.sh to the repo root first."
  exit 66 # EX_NOINPUT (66) An input file did not exist or was not readable.
fi

declare -a collections=(
  "api_keys"
  "bookmarks"
  "content_triggers"
  "domain_triggers"
  "notes"
  "oauth_site_types"
  "oauth_sites"
  "people"
  "reviews"
  "secret_keys"
  "settings"
  "social_media_accounts"
  "tags"
  "users"
)

skipped=()
for collection in "${collections[@]}"; do
  import_file="$EXPORTS_DIR/$collection.json"
  if [ ! -f "$import_file" ]; then
    echo $YELLOW"⚠ skipping $collection: $import_file not found"$NOCOLOR
    skipped+=("$collection")
    continue
  fi
  echo "replacing $collection with exported data..."
  mongoimport --uri="$MONGODB_URL" --drop --collection=$collection --db=$DATABASE_NAME --file=$import_file

  if [ $? -eq 0 ]; then
      echo $GREEN"✅ imported $collection from $import_file"$NOCOLOR
  else
      echo $RED"‼ couldn't import $collection from $import_file"$NOCOLOR
  fi
done

if [ ${#skipped[@]} -gt 0 ]; then
  echo ""
  echo $YELLOW"⚠ ${#skipped[@]} collection(s) had no export file and were left untouched:"$NOCOLOR
  printf '    %s\n' "${skipped[@]}"
  echo "If you expected them, check that export.sh produced them and that they were copied to"
  echo "    $EXPORTS_DIR"
fi
