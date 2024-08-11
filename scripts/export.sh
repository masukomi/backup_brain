#!/usr/bin/env bash
#
# docs here: https://www.mongodb.com/docs/database-tools/mongoexport/

IN_DOCKER=$(ls /.dockerenv 2> /dev/null; echo $?)
if [[ $IN_DOCKER -ne 0 ]] || [[ $IN_DOCKER -eq 0 && $DOCKER_BACKUPS == "true" ]]; then


  # MONGODB_URL tells us where to find the database
  # If you don't set it in your environment, we'll just assume
  # it's running on the default port on localhost.
  #
  # A connection string might look like this
  # mongodb://mongodb0.example.com:27017/reporting
  #
  # The form is documented here:
  # https://www.mongodb.com/docs/manual/reference/connection-string/

  SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  source $SCRIPT_DIR/bash_helpers/colors.sh

  # Inside and outside of the bb_mongodb docker container
  # AND in the host OS
  # we want to connect to localhost

  MONGODB_URL=mongodb://localhost:27017
  if [[ -z ${DATABASE_NAME:-""} ]]; then
      DATABASE_NAME="backup_brain_development"
  fi

  echo "Exporting the \"$DATABASE_NAME\" database found on"
  echo "$MONGODB_URL"
  echo "----------------------------------------------"

  mkdir -p mongo_exports

  declare -a collections=("bookmarks" "users" "tags" "settings")

  for collection in "${collections[@]}"; do
    export_file=mongo_exports/$collection.json
    echo "exporting $collection …"
    mongoexport --uri="$MONGODB_URL" --jsonFormat=canonical --collection=$collection --db=$DATABASE_NAME --out=$export_file

    if [ $? -eq 0 ]; then
      echo $GREEN"✅ exported $collection to $export_file"$NOCOLOR
    else
      echo $RED"‼ couldn't export $collection to $export_file"$NOCOLOR
    fi
  done
else
  echo "skipped db backup"
fi

if [[ $IN_DOCKER -eq 0 ]]; then
   echo 'db.runCommand("ping").ok' | mongosh 0.0.0.0:27017/test --quiet
fi
