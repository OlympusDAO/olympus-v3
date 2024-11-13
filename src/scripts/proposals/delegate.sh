#!/bin/bash

# This script delegates voting power to a delegate.
#
# Usage: src/scripts/proposals/delegate.sh --account <forge account> --delegate <delegate>  --env <env-file>
#
# Environment variables:
# RPC_URL

# Exit if any error occurs
set -e

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Get the name of the .env file or use the default
ENV_FILE=${env:-".env"}
echo "Sourcing environment variables from $ENV_FILE"

# Load environment file
set -a  # Automatically export all variables
source $ENV_FILE
set +a  # Disable automatic export

# Check if the RPC_URL was specified
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL was not specified"
  exit 1
fi

# Check if the forge account was specified
if [ -z "$account" ]; then
  echo "Error: Forge account was not specified. Set up using 'cast wallet'."
  exit 1
fi

# Check if the delegate was specified
if [ -z "$delegate" ]; then
  echo "Error: Delegate was not specified"
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using forge account: $account"
echo "Delegating to delegate: $delegate"

# Run the delegate command
# TODO this doesn't seem to work due to an error with cast call:
# > Error: invalid type: found string "mainnet", expected u64
cast call 0x0ab87046fbb341d058f17cbc4c1133f25a20a52f "delegate(address)()" $delegate --chain mainnet --rpc-url $RPC_URL --account $account
