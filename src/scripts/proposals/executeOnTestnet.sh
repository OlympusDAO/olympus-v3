#!/bin/bash

# This script executes a proposal's actions on a testnet.
#
# Usage: src/scripts/proposals/executeOnTestnet.sh --file <proposal-path> --contract <contract-name> --env <env-file>
#
# Environment variables:
# TENDERLY_ACCOUNT_SLUG
# TENDERLY_PROJECT_SLUG
# TENDERLY_VNET_ID
# TENDERLY_ACCESS_KEY
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

# Check if the proposal file was specified
if [ -z "$file" ]; then
  echo "Error: Proposal file was not specified"
  exit 1
fi

# Check if the proposal file exists
if [ ! -f "$file" ]; then
  echo "Error: Proposal file does not exist. Provide the correct relative path after the --file flag."
  exit 1
fi

# Check if the contract name was specified
if [ -z "$contract" ]; then
  echo "Error: Contract name was not specified"
  exit 1
fi

# Check if the TENDERLY_ACCOUNT_SLUG was specified
if [ -z "$TENDERLY_ACCOUNT_SLUG" ]; then
  echo "Error: TENDERLY_ACCOUNT_SLUG was not specified"
  exit 1
fi

# Check if the TENDERLY_PROJECT_SLUG was specified
if [ -z "$TENDERLY_PROJECT_SLUG" ]; then
  echo "Error: TENDERLY_PROJECT_SLUG was not specified"
  exit 1
fi

# Check if the TENDERLY_VNET_ID was specified
if [ -z "$TENDERLY_VNET_ID" ]; then
  echo "Error: TENDERLY_VNET_ID was not specified"
  exit 1
fi

# Check if the TENDERLY_ACCESS_KEY was specified
if [ -z "$TENDERLY_ACCESS_KEY" ]; then
  echo "Error: TENDERLY_ACCESS_KEY was not specified"
  exit 1
fi

# Check if the RPC_URL was specified
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL was not specified"
  exit 1
fi

echo "Using proposal contract: $file:$contract"
echo "Using TENDERLY_ACCOUNT_SLUG: $TENDERLY_ACCOUNT_SLUG"
echo "Using TENDERLY_PROJECT_SLUG: $TENDERLY_PROJECT_SLUG"
echo "Using TENDERLY_VNET_ID: $TENDERLY_VNET_ID"
echo "Using RPC_URL: $RPC_URL"

# Run the forge script
TENDERLY_ACCOUNT_SLUG=$TENDERLY_ACCOUNT_SLUG TENDERLY_PROJECT_SLUG=$TENDERLY_PROJECT_SLUG TENDERLY_VNET_ID=$TENDERLY_VNET_ID TENDERLY_ACCESS_KEY=$TENDERLY_ACCESS_KEY forge script $file:$contract --sig "executeOnTestnet()" --rpc-url $RPC_URL
