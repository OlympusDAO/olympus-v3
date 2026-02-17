#!/bin/bash

# Grants a role to the specified address
#
# Usage:
# ./grantRole.sh --role <role name> --to <recipient address> --chain <chain name> --account <cast wallet> OR --ledger <mnemonic-index> --broadcast <false> --env <file>
#
# Environment variables:
# RPC_URL (optional if chain is in foundry.toml)
# CHAIN (optional if --chain is provided)
#
# Examples:
# Using cast wallet:
#   ./grantRole.sh --role minter_admin --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --account mywallet --broadcast true
#
# Using Ledger:
#   ./grantRole.sh --role minter_admin --to 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --ledger 0 --broadcast true

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
validate_text "$role" "No role specified. Please provide the role after the --role flag."
validate_address "$to" "No recipient specified or it is not an EVM address. Provide the recipient after the --to flag."
validate_text "$chain" "No chain specified. Provide the chain after the --chain flag."

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
validate_and_set_account "$account" "$ledger"

# Set RPC URL from chain if not provided
if [ -z "$RPC_URL" ]; then
    RPC_URL=$chain
fi

echo ""
echo "Summary:"
echo "  Chain: $chain"
echo "  Using RPC at URL: $RPC_URL"
echo "  Role: $role"
echo "  To: $to"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Roles.s.sol:RolesScript \
    --sig "grantRole(string,string,address)()" $chain $role $to \
    --rpc-url $RPC_URL $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Grant role complete"
