#!/usr/bin/env bash
ESCAPE=$(printf "\033")
RED="${ESCAPE}[91m"
GREEN="${ESCAPE}[92m"
YELLOW="${ESCAPE}[33m"
NOCOLOR="${ESCAPE}[0m"

# Exit on error
set -e

ENV_FILE=".env"

cd /app
source "scripts/bash_helpers/get_env_key.sh"

if [ -e $ENV_FILE ]; then
    echo "✅ .env file found"
else
    echo "⚠ ⛔ NO .env file found"
    echo "Please copy .env.sample to .env & edit as per Getting Started instructions."
    exit 78 # EX_CONFIG (78)  Something was found in an unconfigured or misconfigured state.
fi

## GENEREATE MEILI_MASTER_KEY
meili_master_key=$(get_env_key 'MEILI_MASTER_KEY')

if [ -z "$meili_master_key" ]; then
    echo "✋ MEILI_MASTER_KEY not found in .env"
    echo "Generating MEILI_MASTER_KEY"
    meili_master_key=$(openssl rand -base64 32 | sed 's/=$//')
    echo "editing .env"
    cat $ENV_FILE | sed -E "s/^.*MEILI_MASTER_KEY=.*/MEILI_MASTER_KEY=$meili_master_key/" > .env.temp
    mv .env.temp $ENV_FILE
    echo "✅ NEW MEILI_MASTER_KEY generated and saved in .env"
else
    echo "✅ MEILI_MASTER_KEY found in .env"
    meilisearch_search_key=$(get_env_key 'MEILISEARCH_SEARCH_KEY')
    if [ -z "$meilisearch_search_key" ]; then
        echo "⚠️ MEILISEARCH_SEARCH_KEY not found in .env"
        echo "⚠️ PLEASE ADD MEILISEARCH_SEARCH_KEY to .env to improve security"
        echo "   See Getting Started instructions for details."
    else
        echo "✅ MEILISEARCH_SEARCH_KEY found in .env Good for you!"
    fi

    meiliadmin_admin_key=$(get_env_key 'MEILIADMIN_ADMIN_KEY')
    if [ -z "$meilisearch_admin_key" ]; then
        echo "⚠️ MEILISEARCH_ADMIN_KEY not found in .env"
        echo "⚠️ PLEASE ADD MEILISEARCH_ADMIN_KEY to .env to improve security"
        echo "   See Getting Started instructions for details."
    else
        echo "✅ MEILISEARCH_ADMIN_KEY found in .env Good for you!"
    fi
fi

## COMPILE READER IF NEEDED
if [ ! -e "bin/reader" ]; then
    echo "✋ reader not found in ./bin"

    if [ ! -e "reader-clone" ]; then
        echo "Cloning reader repo"
        git clone https://github.com/mrusme/reader.git /app/reader-clone
    fi
    cd reader-clone

    echo "Building reader"
    go mod download && go build -v -o /app/bin/reader

    grep "I_INSTALLED_READER=true" /app/.env > /dev/null
    if [ $? -ne 0 ]; then
        echo "editing .env"
        echo "setting I_INSTALLED_READER=true"
        cat $ENV_FILE | sed -E "s/.*I_INSTALLED_READER.*/I_INSTALLED_READER=true/" > .env.temp
        mv .env.temp .env
    fi
    rm -rf reader-clone
    echo "✅ reader executable compiled to bin/reader"
else
    echo "✅ reader found. No need to build."
fi
