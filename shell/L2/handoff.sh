#!/bin/bash

# Transfers the ownership of the Bophades installation to the DAO multisig.
#
# Usage:
# ./handoff.sh --chain <rpc-alias> --ledger <index> --broadcast <false> --resume <false>
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
RESUME=${resume:-false}
CHAIN=${chain:-$CHAIN}
RPC_URL=${chain:-$RPC_URL}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_boolean "$BROADCAST" "Provide true or false after --broadcast."
validate_boolean "$RESUME" "Provide true or false after --resume."

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
set_resume_flag "$RESUME"
validate_and_set_account "$account" "$ledger"

# Deploy using script
echo ""
echo "Running forge script"
FOUNDRY_PROFILE=deploy forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "handoffToMultisig(string)()" "$CHAIN" \
    --rpc-url "$RPC_URL" $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG \
    $RESUME_FLAG

echo ""
if [ "$BROADCAST" == "true" ]; then
    echo "Handoff broadcast complete. Creating the DAO Safe acceptance proposal."
    echo "The signing wallet must be an owner of the DAO Safe."
    SAFE_ARGS=(--contract L2HandoffBatch --function acceptHandoff --chain "$CHAIN" --multisig true --broadcast true)
    if [ -n "$account" ]; then
        SAFE_ARGS+=(--account "$account")
    else
        SAFE_ARGS+=(--ledger "$ledger")
    fi
    if [ -n "$nonce" ]; then SAFE_ARGS+=(--nonce "$nonce"); fi
    "$SCRIPT_DIR/../safeBatchV2.sh" "${SAFE_ARGS[@]}"
    echo "Confirm and execute the acceptance proposal in the DAO Safe to complete the handoff."
    echo "After execution, run ./shell/L2/verify.sh --chain $CHAIN to check the live deployer-access invariant."
else
    echo "Handoff preview complete. No transactions or Safe proposal were submitted."
    echo "A broadcast handoff also creates the DAO Safe acceptance batch."
fi
