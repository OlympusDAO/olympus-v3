#!/bin/bash

# Deploys an L2 installation of the Olympus protocol, including the CCIP pool and bridge.
# Requires external.ccip.RMN and external.ccip.Router in src/scripts/env.json.
#
# Usage:
# ./deploy.sh
#   --account <cast wallet> OR --ledger <mnemonic-index>
#   --chain <foundry-rpc-alias>
#   --ohm <true|false>
#   --broadcast <false>
#   --verify <false>
#   --resume <false>
#   --env <env-file> (optional; defaults to .env if present)
#
# Environment variables:
# RPC_URL, CHAIN (legacy alternative to --chain)
# Source verification uses Sourcify and requires no Etherscan API key.

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
VERIFY=${verify:-false}
RESUME=${resume:-false}
CHAIN=${chain:-$CHAIN}
RPC_URL=${chain:-$RPC_URL}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_boolean "$ohm" "No ohm flag specified. Provide true or false after the --ohm flag."
validate_boolean "$BROADCAST" "Provide true or false after --broadcast."
validate_boolean "$VERIFY" "Provide true or false after --verify."
validate_boolean "$RESUME" "Provide true or false after --resume."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "Provide --chain <foundry-rpc-alias>, or CHAIN and RPC_URL in the environment."
validate_text "$RPC_URL" "No RPC URL or alias specified."

echo ""
echo "Summary:"
echo "  Chain: $CHAIN"
echo "  Deploying OHM: $ohm"

# Validate and set forge script flags
source "$SCRIPT_DIR/../lib/forge.sh"
set_broadcast_flag "$BROADCAST"
set_verify_flag "$VERIFY"
if [ -n "$VERIFY_FLAG" ] && [ -z "$BROADCAST_FLAG" ]; then
    display_error "Foundry requires --broadcast true with --verify true. To retry a saved deployment, inspect receipts and use --resume true."
    exit 1
fi
set_resume_flag "$RESUME"
validate_and_set_account "$account" "$ledger"

# Deploy using script
echo ""
echo "Running forge script"
FOUNDRY_PROFILE=deploy forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "deploy(string,bool)()" "$CHAIN" "$ohm" \
    --rpc-url "$RPC_URL" $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG \
    $VERIFY_FLAG \
    $RESUME_FLAG

echo ""
echo "Deployment complete"
