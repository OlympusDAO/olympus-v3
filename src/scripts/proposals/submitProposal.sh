#!/bin/bash

# This script submits a proposal to the governor.
#
# Usage: src/scripts/proposals/submitProposal.sh --file <proposal-path> --contract <contract-name> --account <forge account> --fork <true|false> --broadcast <true|false> --env <env-file>
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
set -a # Automatically export all variables
source $ENV_FILE
set +a # Disable automatic export

# Apply defaults to command-line arguments
FORK=${fork:-false}
BROADCAST=${broadcast:-false}

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

echo "Using proposal contract: $file:$contract"
echo "Using RPC at URL: $RPC_URL"
echo "Using forge account: $account"

# Set the fork flag
FORK_FLAG=""
if [ "$FORK" = "true" ]; then
    FORK_FLAG="--legacy"
    echo "Fork: enabled"
else
    echo "Fork: disabled"
fi

# Set the broadcast flag
BROADCAST_FLAG=""
if [ "$BROADCAST" = "true" ]; then
    BROADCAST_FLAG="--broadcast"
    echo "Broadcast: enabled"
else
    echo "Broadcast: disabled"
fi

# Run the forge script
forge script $file:$contract -vvv --rpc-url $RPC_URL --account $account $FORK_FLAG $BROADCAST_FLAG
