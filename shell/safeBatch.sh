#!/bin/bash

# Run a multisig batch
#
# Usage:
# ./safeBatch.sh
# --contract <contract-name>
# --batch <batch-name>
# --account <cast wallet>
# [--ledger <true|false>]
# [--ledgerMnemonicIndex <mnemonic-index>]
# [--broadcast <true|false>]
# [--testnet <true|false>]
# [--env <env-file>]
#
# Environment variables:
# RPC_URL
# CHAIN

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
source $SCRIPT_DIR/lib/forge.sh
source $SCRIPT_DIR/lib/error.sh
source $SCRIPT_DIR/lib/addresses.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
broadcast=${broadcast:-false}
testnet=${testnet:-false}
ledger=${ledger:-false}

# Validate named arguments
echo ""
echo "Validating named arguments"
validate_text "$contract" "No contract name provided. Provide the contract name after the --contract flag."
validate_text "$batch" "No batch name provided. Provide the batch name after the --batch flag."
validate_boolean "$ledger" "Invalid value for --ledger. Must be true or false."
validate_boolean "$testnet" "Invalid value for --testnet. Must be true or false."
validate_boolean "$broadcast" "Invalid value for --broadcast. Must be true or false."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$RPC_URL" "No RPC URL provided. Specify the RPC_URL in the $ENV_FILE file."
validate_text "$CHAIN" "No chain provided. Specify the CHAIN in the $ENV_FILE file."

# If --ledger is true, validate that --ledgerMnemonicIndex is set
if [ "$ledger" == "true" ]; then
    if [ -z "$ledgerMnemonicIndex" ]; then
        display_error "--ledger is true and no --ledgerMnemonicIndex provided. Specify the --ledgerMnemonicIndex flag."
        exit 1
    fi
# Otherwise the account must be provided
elif [ -z "$account" ]; then
    display_error "No account provided. Specify the account after the --account flag."
    exit 1
fi

# Determine the account address and store in ACCOUNT_ADDRESS
# Export variables that BatchScript.sol uses
if [ "$ledger" == "true" ]; then
    set_account_address_ledger "$ledgerMnemonicIndex"
    export MNEMONIC_INDEX="$ledgerMnemonicIndex"
    WALLET_TYPE="ledger"
else
    set_account_address "$account"
    WALLET_TYPE="local"
    ACCOUNT_FLAG="--account $account"
fi

# Set the multisig addresses
# Policy is largely unused, so can be zero
DAO_MS=$(get_address_not_zero "$CHAIN" "olympus.multisig.dao")
POLICY_MS=$(get_address "$CHAIN" "olympus.multisig.policy")
EMERGENCY_MS=$(get_address_not_zero "$CHAIN" "olympus.multisig.emergency")

echo ""
echo "Summary:"
echo "  Contract name: $contract"
echo "  Batch name: $batch"
echo "  Chain: $CHAIN"
echo "  RPC at URL: $RPC_URL"
echo "  Wallet type: $WALLET_TYPE"
echo "  Account address: $ACCOUNT_ADDRESS"
echo "  DAO MS: $DAO_MS"
echo "  POLICY MS: $POLICY_MS"
echo "  EMERGENCY MS: $EMERGENCY_MS"
echo "  Testnet: $testnet"
echo "  Broadcasting: $broadcast"

# Execute the batch
export DAO_MS=$DAO_MS
export POLICY_MS=$POLICY_MS
export EMERGENCY_MS=$EMERGENCY_MS
export TESTNET=$testnet
export WALLET_TYPE=$WALLET_TYPE
forge script ./src/scripts/ops/batches/$contract.sol:$contract \
    --sig "$batch(bool)()" $broadcast \
    --rpc-url $RPC_URL \
    $ACCOUNT_FLAG \
    --sender $ACCOUNT_ADDRESS \
    --slow -vvv

echo ""
echo "Batch complete"
