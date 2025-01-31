#!/bin/bash

# Transfers the ownership of the Bophades installation to the DAO multisig.
#
# Usage:
# ./handoff.sh --account <cast wallet> --broadcast <false> --resume <false> --env <env-file>
#
# Environment variables:
# RPC_URL
# CHAIN

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${BROADCAST:-false}
RESUME=${RESUME:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."
validate_text "$CHAIN" "No chain specified. Specify the CHAIN in the $ENV_FILE file."

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Chain: $CHAIN"
echo "  Using RPC at URL: $RPC_URL"

# Validate and set forge script flags
source $SCRIPT_DIR/lib/forge.sh
set_broadcast_flag $BROADCAST
set_resume_flag $RESUME

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "handoffToMultisig(string)()" $CHAIN \
    --rpc-url $RPC_URL --account $account --slow -vvv \
    $BROADCAST_FLAG \
    $RESUME_FLAG

echo ""
echo "Handoff complete"
