#!/bin/bash

# Disables a contract that inherits from PolicyEnabler or IEnabler
#
# Usage:
# ./contractDisable.sh
# --contract <contract-address>
# --account <cast wallet>
# [--broadcast <true|false>]
# [--env <env-file>]
#
# Environment variables:
# RPC_URL

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_address "$contract" "No contract address specified. Provide the contract address after the --contract flag."
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."

# Validate and set forge script flags
source $SCRIPT_DIR/lib/forge.sh
set_account_address $account

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Using RPC at URL: $RPC_URL"
echo "  Contract: $contract"

# Set the cast subcommand to use
CAST_SUBCOMMAND=""
if [ "$BROADCAST" = "true" ]; then
    CAST_SUBCOMMAND="send"
    echo "  Broadcast: true"
else
    CAST_SUBCOMMAND="call"
    echo "  Broadcast: false"
fi

# Ensure that CHAIN is unset
# cast call doesn't handle it well
unset CHAIN

# Run
echo ""
echo "Sending transaction"
cast $CAST_SUBCOMMAND \
    --account $account \
    --rpc-url $RPC_URL \
    -vvv \
    $contract "disable(bytes)()" "0x"

echo ""
echo "Contract disabled"
