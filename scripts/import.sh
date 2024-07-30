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

# Inside and outside of the bb_mongodb docker container
# AND in the host OS
# we want to connect to localhost
MONGODB_URL=mongodb://localhost:27017
if [[ -z ${DATABASE_NAME:-""} ]]; then
    DATABASE_NAME="backup_brain_development"
fi

echo "Importing to the \"$DATABASE_NAME\" database found on"
echo "$MONGODB_URL"
echo "----------------------------------------------"

declare -a collections=("bookmarks" "users")

for collection in "${collections[@]}"
    do
    echo "replacing $collection with exported data..."
    mongoimport --uri="$MONGODB_URL" --drop --collection=$collection --db=$DATABASE_NAME --file=mongo_exports/$collection.json
done
