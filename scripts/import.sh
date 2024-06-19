#!/usr/bin/env bash
#
# docs here: https://www.mongodb.com/docs/database-tools/mongoexport/

# MONGODB_URI tells us where to find the database
# If you don't set it in your environment, we'll just assume
# it's running on the default port on localhost.
#
# A connection string might look like this
# mongodb://mongodb0.example.com:27017/reporting
# The form is documented here:
# https://www.mongodb.com/docs/manual/reference/connection-string/
if [[ -z ${MONGODB_URI:-""} ]]; then
    MONGODB_URI="mongodb://localhost/"
fi

declare -a collections=("bookmarks", "users")

for collection in "${collections[@]}"
    do
    echo "replacing $collection with exported data..."
    mongoimport --uri="$MONGODB_URI" --drop --collection=$collection --db=devgood_development --file=mongo_exports/$collection.json
done
