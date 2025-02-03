#!/bin/bash

# Installs a module in the kernel
#
# Usage:
# ./installModule.sh --module <module address> --account <cast wallet> --broadcast <false> --env <file>
#
# Environment variables:
# RPC_URL
# CHAIN

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/../lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_address "$module" "No module specified. Please provide the module address after the --module flag."
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
echo "  Module: $module"

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
set_account_address $account

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Kernel.s.sol:KernelScript \
    --sig "installModule(string,address)()" $CHAIN $module \
    --rpc-url $RPC_URL --account $account --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Install module complete"
