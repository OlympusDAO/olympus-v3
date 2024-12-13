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
# CHAIN
# DAO_MS
# POLICY_MS
# EMERGENCY_MS
# LEDGER_MNEMONIC_INDEX (ledger only)

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

# If LEDGER is true, validate that MNEMONIC_INDEX is set
if [ "$LEDGER" == "true" ] && [ -z "$LEDGER_MNEMONIC_INDEX" ]; then
    echo "No LEDGER_MNEMONIC_INDEX provided. Specify the LEDGER_MNEMONIC_INDEX in the $ENV_FILE file."
    exit 1
fi

# Validate that CHAIN is set
if [ -z "$CHAIN" ]; then
    echo "No chain provided. Specify the CHAIN in the $ENV_FILE file."
    exit 1
fi

# Validate that DAO_MS is set
if [ -z "$DAO_MS" ]; then
    echo "No DAO MS provided. Specify the DAO_MS in the $ENV_FILE file."
    exit 1
fi

# Validate that POLICY_MS is set
if [ -z "$POLICY_MS" ]; then
    echo "No POLICY MS provided. Specify the POLICY_MS in the $ENV_FILE file."
    exit 1
fi

# Validate that EMERGENCY_MS is set
if [ -z "$EMERGENCY_MS" ]; then
    echo "No EMERGENCY MS provided. Specify the EMERGENCY_MS in the $ENV_FILE file."
    exit 1
fi

# Set the LEDGER_FLAG
LEDGER_FLAG=""
WALLET_TYPE_ENV=""
LEDGER_MNEMONIC_INDEX_ENV=""
if [ "$LEDGER" == "true" ]; then
    LEDGER_FLAG="--ledger"
    WALLET_TYPE_ENV="WALLET_TYPE=ledger"
    LEDGER_MNEMONIC_INDEX_ENV="MNEMONIC_INDEX=$LEDGER_MNEMONIC_INDEX"
else
    WALLET_TYPE_ENV="WALLET_TYPE=local"
fi

echo "Contract name: $contract"
echo "Batch name: $batch"
echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Using signer address: $SIGNER_ADDRESS"
echo "Using DAO MS: $DAO_MS"
echo "Using POLICY MS: $POLICY_MS"
echo "Using EMERGENCY MS: $EMERGENCY_MS"
echo "Broadcasting: $BROADCAST"
echo "Using testnet: $TESTNET"
echo "Using ledger: $LEDGER"

# Execute the batch
TESTNET=$TESTNET $WALLET_TYPE_ENV $LEDGER_MNEMONIC_INDEX_ENV forge script ./src/scripts/ops/batches/$contract.sol:$contract --sig "$batch(bool)()" $BROADCAST --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL $LEDGER_FLAG
