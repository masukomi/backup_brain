#!/usr/bin/env bash

ESCAPE=$(printf "\033")
RED="${ESCAPE}[91m"
GREEN="${ESCAPE}[92m"
YELLOW="${ESCAPE}[33m"
NOCOLOR="${ESCAPE}[0m"

set -e #stop if anything goes wrong

source "scripts/bash_helpers/get_env_key.sh"

# ENV FILE SHENANIGANS

ENV_FILE=".env"

if [ ! -e ".env" ]; then
    echo "✋ $YELLOW.env file not found. Copying from .env.sample$NOCOLOR"
    cp .env.sample .env
else
    echo "✅ $GREEN.env file already exists.$NOCOLOR"
fi

echo "
$YELLOW""Will you be using search❓$NOCOLOR (y/n)"
read search_intended

search_enabled=$(get_env_key 'SEARCH_ENABLED')

if [ $search_intended == "y" ] || [ $search_intended == "Y" ]; then

    if [ -z "$search_enabled" ] || [ $search_enabled != "true" ]; then
        echo "✋ $YELLOW enabling search in .env$NOCOLOR"
        if [ grep -q "^SEARCH_ENABLED" .env ]; then
            echo "Setting value of SEARCH_ENABLED to true"
            cat $ENV_FILE | sed -e "s/.*SEARCH_ENABLED.*/SEARCH_ENABLED=true/" > .env.temp
            mv .env.temp .env
        else
            echo "SEARCH_ENABLED=true" >> .env
            echo "✅ $GREEN SEARCH_ENABLED=true added to .env$NOCOLOR"
        fi
        echo "✅ $GREEN search is now enabled$NOCOLOR"
    else
        echo "✅ $GREEN search is enabled$NOCOLOR"
    fi
    echo "
ℹ If it's not already present, a MEILI_MASTER_KEY will be automatically
   generated and added to your .env file IF you use docker.
   You should also add an MEILISEARCH_ADMIN_KEY and MEILISEARCH_SEARCH_KEY
   for security if you intend to expose your Backup Brain to the internet.
   See Getting Started instructions for details."
else
    # Why wouldn't you want search?! That's the best part!
    if [ -z "$search_enabled" ] || [ $search_enabled == "true" ]; then
        echo "✋ $YELLOW disabling search in .env$NOCOLOR"
        if [ grep -q "^SEARCH_ENABLED" .env ]; then
            echo "Setting value of SEARCH_ENABLED to false"
            cat $ENV_FILE | sed -e "s/.*SEARCH_ENABLED.*/SEARCH_ENABLED=false/" > .env.temp
            mv .env.temp .env
        else
            echo "SEARCH_ENABLED=false" >> .env
            echo "✅ $GREEN SEARCH_ENABLED=false added to .env$NOCOLOR"
        fi
        echo "✅ $GREEN search is now disabled$NOCOLOR"
    else
        echo "✅ $GREEN search is already disabled$NOCOLOR"
    fi
    echo "SEARCH_ENABLED=false" >> .env
    echo "✅ $GREENSEARCH_ENABLED=false$NOCOLOR"
fi

# DOCKER SHENANIGANS

echo "
$YELLOW""Do you intend to use Docker❓$NOCOLOR (y/n)"
read docker_intended

if [ $docker_intended == "y" ] || [ $docker_intended == "Y" ]; then
    # DOCKER COMPOSE
    if [ -e "docker-compose.yml" ]; then
        echo "✅ $GREEN docker-compose.yml already exists$NOCOLOR"
    else
        echo "✋ $YELLOW docker-compose.yml not found.$NOCOLOR"
        echo "Will you be using Tailscale Funnel to expose your Backup Brain to the internet❓ (y/n)"
        read tailscale_intended
        if [ $tailscale_intended == "y" ] || [ $tailscale_intended == "Y" ]; then
            echo "✋ $YELLOW copying docker-compose-with-tailscale.yml to docker-compose.yml$NOCOLOR"
            cp docker-compose-with-tailscale.yml docker-compose.yml
            echo "✅ $GREEN docker-compose.yml configured for use with Tailscale$NOCOLOR"
            echo "
⚠️$YELLOW You WILL need to add an ADMIN KEY to docker-compose.yml
   to finish configuring Tailscale.
   See the Getting Started instructions for details.$NOCOLOR"
        else
            echo "✋ $YELLOW copying docker-compose-without-tailscale.yml to docker-compose.yml$NOCOLOR"
            cp docker-compose-without-tailscale.yml docker-compose.yml
            echo "✅ $GREEN docker-compose.yml configured for use use on localhost$NOCOLOR"
        fi

    fi
    # MONGODB With Docker
    mongodb_url=$(get_env_key 'MONGODB_URL')
    if [ "$mongodb_url" == 'mongodb://bb_mongodb:27017']; then
        echo "✅ $GREEN MONGODB_URL is mongodb://bb_mongodb:27017 $NOCOLOR"
    elif [ -z "$mongodb_url" ]; then
        echo "MONGODB_URL=mongodb://bb_mongodb:27017" >> .env
    else
        cat $ENV_FILE | sed -e "s/.*MONGODB_URL.*/MONGODB_URL=mongodb://bb_mongodb:27017/" > .env.temp
        mv .env.temp .env
        echo "✅ $GREEN MONGODB_URL configured for docker$NOCOLOR"
    fi


    echo "✅ $GREEN Docker setup complete$NOCOLOR"
else

    # MONGODB Without Docker
    mongodb_url=$(get_env_key 'MONGODB_URL')
    if [ "$mongodb_url" == 'mongodb://localhost:27017']; then
        echo "✅ $GREEN MONGODB_URL is mongodb://localhost:27017 $NOCOLOR"
    elif [ -z "$mongodb_url" ]; then
        echo "MONGODB_URL=localhost:27017" >> .env
    else
        cat $ENV_FILE | sed -e "s/.*MONGODB_URL.*/MONGODB_URL=mongodb://localhost:27017/" > .env.temp
        mv .env.temp .env
        echo "✅ $GREEN MONGODB_URL configured for docker$NOCOLOR"
    fi


    echo "
Good luck with the manual setup intreped hacker.
I wish you the best."

fi

echo "🆗 Initial setup complete.
   There's not much left to do.
   Please continue with the instructions in Getting Started."
