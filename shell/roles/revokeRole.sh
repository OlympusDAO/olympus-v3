#!/bin/bash

# Revokes a role from the specified address
#
# Usage:
# ./revokeRole.sh --role <role name> --from <recipient address> --chain <chain name> --account <cast wallet> OR --ledger <mnemonic-index> --broadcast <false> --env <file>
#
# The chain is determined automatically from block.chainid. The --chain parameter specifies the RPC URL (from foundry.toml).
#
# Examples:
# Using cast wallet:
#   ./revokeRole.sh --role minter_admin --from 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --account mywallet --broadcast true
#
# Using Ledger:
#   ./revokeRole.sh --role minter_admin --from 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --ledger 0 --broadcast true

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
validate_address "$from" "No recipient specified or it is not an EVM address. Provide the recipient after the --from flag."
validate_text "$chain" "No chain specified. Provide the chain after the --chain flag."

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
validate_and_set_account "$account" "$ledger"

echo ""
echo "Summary:"
echo "  Chain: $chain"
echo "  Role: $role"
echo "  From: $from"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Roles.s.sol:RolesScript \
    --sig "revokeRole(string,address)()" $role $from \
    --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Revoke role complete"
