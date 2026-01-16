#!/bin/bash

# This script executes a proposal's actions on a local Anvil fork.
#
# Usage: src/scripts/proposals/executeOnAnvilFork.sh --file <proposal-path> --contract <contract-name> --env <env-file>
#
# Requires: Anvil running on http://localhost:8545
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

# Verify Anvil is running
if ! curl -sSf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
    echo "Error: Anvil is not running on http://localhost:8545"
    echo "Start it with: pnpm run anvil:fork"
    exit 1
fi

# Set default RPC URL if not provided
export RPC_URL=${RPC_URL:-"http://localhost:8545"}

echo "Executing proposal via Anvil fork"
echo "Proposal contract: $file:$contract"
echo "RPC URL: $RPC_URL"

# Run the forge script
forge script $file:$contract --sig "executeOnAnvilFork()" --rpc-url $RPC_URL --broadcast
