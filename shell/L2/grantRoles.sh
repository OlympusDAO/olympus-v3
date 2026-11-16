#!/bin/bash

# Grants roles.
#
# Usage:
# ./grantRoles.sh --chain <rpc-alias> --ledger <index> --broadcast <false>
# --account <cast wallet> is an alternative to --ledger. --env is optional.
#
# Environment variables:
# RPC_URL
# CHAIN

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/arguments.sh"
load_named_args "$@"

# Load environment variables
if [ -z "$env" ] && [ -f .env ]; then env=.env; fi
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}
CHAIN=${chain:-$CHAIN}
RPC_URL=${chain:-$RPC_URL}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_boolean "$BROADCAST" "Provide true or false after --broadcast."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "Provide --chain <foundry-rpc-alias>, or CHAIN and RPC_URL in the environment."
validate_text "$RPC_URL" "No RPC URL or alias specified."

echo ""
echo "Summary:"
echo "  Chain: $CHAIN"

# Validate and set forge script flags
source "$SCRIPT_DIR/../lib/forge.sh"
set_broadcast_flag "$BROADCAST"
validate_and_set_account "$account" "$ledger"

# Deploy using script
echo ""
echo "Running forge script"
FOUNDRY_PROFILE=deploy forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "grantRoles(string)()" "$CHAIN" \
    --rpc-url "$RPC_URL" $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG

echo ""
echo "Grant roles complete"
