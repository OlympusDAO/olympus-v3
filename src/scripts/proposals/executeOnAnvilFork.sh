#!/bin/bash

# This script executes a proposal's actions on a local Anvil fork.
#
# Usage: src/scripts/proposals/executeOnAnvilFork.sh --file <proposal-path> --contract <contract-name> --env <env-file>
#
# Requires: Anvil running on RPC_URL (default http://localhost:8545)
#
# Environment variables:
# RPC_URL (optional, defaults to http://localhost:8545)

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

# Set default RPC URL if not provided
export RPC_URL=${RPC_URL:-"http://localhost:8545"}

# Log only the scheme, host and port; the userinfo, path and query can carry provider credentials
RPC_ENDPOINT=$RPC_URL
RPC_SCHEME=""
if [[ $RPC_ENDPOINT == *://* ]]; then
    RPC_SCHEME="${RPC_ENDPOINT%%://*}://"
    RPC_ENDPOINT=${RPC_ENDPOINT#*://}
fi
RPC_ENDPOINT=${RPC_ENDPOINT%%[/?#]*}
RPC_ENDPOINT="$RPC_SCHEME${RPC_ENDPOINT##*@}"

# Verify Anvil is running; any node answers basic RPC calls, so check the client name.
# Discard cast errors, which can print the RPC URL.
if ! RPC_CLIENT=$(cast client --rpc-url "$RPC_URL" 2> /dev/null); then
    echo "Error: Anvil is not running on $RPC_ENDPOINT"
    echo "Start it with: pnpm run anvil:fork"
    exit 1
fi
if [[ $RPC_CLIENT != anvil/* ]]; then
    echo "Error: $RPC_ENDPOINT is not an Anvil node (client: $RPC_CLIENT)"
    echo "Point RPC_URL at an Anvil fork (default http://localhost:8545); start one with: pnpm run anvil:fork"
    exit 1
fi

echo "Funding timelock with ETH for gas..."
cast rpc --rpc-url $RPC_URL anvil_setBalance "0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39" "0xDE0B6B3A7640000" --silent

echo "Executing proposal via Anvil fork"
echo "Proposal contract: $file:$contract"
echo "RPC URL: $RPC_ENDPOINT"

# Run the forge script
forge script $file:$contract --sig "executeOnAnvilFork()" --rpc-url $RPC_URL --broadcast --unlocked
