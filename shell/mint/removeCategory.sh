#!/bin/bash

# Removes a minting category
#
# Usage:
# ./removeCategory.sh --category <category name> --chain <chain name> --account <cast wallet> OR --ledger <mnemonic-index> --broadcast <false> --env <file>
#
# The chain is determined automatically from block.chainid. The --chain parameter specifies the RPC URL (from foundry.toml).
#
# Examples:
# Using cast wallet:
#   ./removeCategory.sh --category test --chain sepolia --account mywallet --broadcast true
#
# Using Ledger:
#   ./removeCategory.sh --category test --chain sepolia --ledger 0 --broadcast true
#
# Environment variables:
# RPC_URL (optional, defaults to --chain parameter)

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
validate_text "$category" "No category specified. Please provide the category after the --category flag."
validate_text "$chain" "No chain specified. Provide the chain after the --chain flag."

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
validate_and_set_account "$account" "$ledger"

echo ""
echo "Summary:"
echo "  Chain: $chain"
echo "  Category: $category"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Minter.s.sol:MinterScript \
    --sig "removeCategory(string)()" $category \
    --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Remove category complete"
