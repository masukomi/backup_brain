#!/usr/bin/env bash

# this function is intended to be sourced into other scripts
# note that it _must_ be written in such a way that it'll work
# under linux and macOS (BSD)

function get_env_key() {
  key=$1
  value=$(cat $ENV_FILE | grep "^$key" | sed  "s/$key=//" | sed "#.*//")
  echo $value
}

