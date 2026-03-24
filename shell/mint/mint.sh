#!/bin/bash

# Mints OHM to the specified address
#
# Usage:
# ./mint.sh --to <recipient address> --amount <amount> --category <category> --chain <chain name> --account <cast wallet> OR --ledger <mnemonic-index> --broadcast <false> --env <file>
#
# The chain is determined automatically from block.chainid. The --chain parameter specifies the RPC URL (from foundry.toml).
#
# Examples:
# Using cast wallet:
#   ./mint.sh --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --amount 100000000000 --category test --chain sepolia --account mywallet --broadcast true
#
# Using Ledger:
#   ./mint.sh --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --amount 100000000000 --category test --chain sepolia --ledger 0 --broadcast true
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
validate_address "$to" "No recipient specified or it is not an EVM address. Provide the recipient after the --to flag."
validate_number "$amount" "No amount specified. Provide the amount after the --amount flag."
validate_text "$category" "No category specified. Provide the category after the --category flag."
validate_text "$chain" "No chain specified. Provide the chain after the --chain flag."

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
validate_and_set_account "$account" "$ledger"

echo ""
echo "Summary:"
echo "  Chain: $chain"
echo "  To: $to"
echo "  Amount: $amount"
echo "  Category: $category"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Minter.s.sol:MinterScript \
    --sig "mint(string,address,uint256)()" $category $to $amount \
    --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Mint complete"
