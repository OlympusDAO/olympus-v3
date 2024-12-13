#!/bin/bash

# Run a multisig batch
#
# Usage:
# ./batch.sh --contract <contract-name> --batch <batch-name> --ledger <true|false> --broadcast <true|false> --testnet <true|false> --env <env-file>
#
# Environment variables:
# RPC_URL
# SIGNER_ADDRESS
# TESTNET

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

# Set sane defaults
BROADCAST=${broadcast:-false}
TESTNET=${testnet:-false}
LEDGER=${ledger:-false}

# Check if contract is set
if [ -z "$contract" ]; then
    echo "No contract name provided. Provide the contract name after the --contract flag."
    exit 1
fi

# Check if batch is set
if [ -z "$batch" ]; then
    echo "No batch name provided. Provide the batch name after the --batch flag."
    exit 1
fi

# Check if RPC_URL is set
if [ -z "$RPC_URL" ]; then
    echo "No RPC URL provided. Specify the RPC_URL in the $ENV_FILE file."
    exit 1
fi

# Check if SIGNER_ADDRESS is set
if [ -z "$SIGNER_ADDRESS" ]; then
    echo "No signer address provided. Specify the SIGNER_ADDRESS in the $ENV_FILE file."
    exit 1
fi

# Validate that LEDGER is set to true or false
if [ "$LEDGER" != "true" ] && [ "$LEDGER" != "false" ]; then
    echo "Invalid value for LEDGER. Must be true or false."
    exit 1
fi

# Set the LEDGER_FLAG
LEDGER_FLAG=""
if [ "$LEDGER" == "true" ]; then
    LEDGER_FLAG="--ledger"
fi

echo "Contract name: $contract"
echo "Batch name: $batch"
echo "Using RPC at URL: $RPC_URL"
echo "Using signer address: $SIGNER_ADDRESS"
echo "Broadcasting: $BROADCAST"
echo "Using testnet: $TESTNET"
echo "Using ledger: $LEDGER"

# Execute the batch
TESTNET=$TESTNET forge script ./src/scripts/ops/batches/$contract.sol:$contract --sig "$batch(bool)()" $BROADCAST --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL $LEDGER_FLAG
