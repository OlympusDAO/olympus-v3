#!/bin/bash

# Checks whether the specified address has the role
#
# Usage:
# ./hasRole.sh --role <role name> --address <recipient address> --chain <chain name> --account <cast wallet> OR --ledger <mnemonic-index> --env <file>
#
# The chain is determined automatically from block.chainid. The --chain parameter specifies the RPC URL (from foundry.toml).
#
# Examples:
# Using cast wallet:
#   ./hasRole.sh --role minter_admin --address 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --account mywallet
#
# Using Ledger:
#   ./hasRole.sh --role minter_admin --address 0x1A5309F208f161a393E8b5A253de8Ab894A67188 --chain sepolia --ledger 0

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/../lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$role" "No role specified. Please provide the role after the --role flag."
validate_address "$address" "No address specified or it is not an EVM address. Provide the address after the --address flag."
validate_text "$chain" "No chain specified. Provide the chain after the --chain flag."

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
validate_and_set_account "$account" "$ledger"

echo ""
echo "Summary:"
echo "  Chain: $chain"
echo "  Role: $role"
echo "  Address: $address"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/Roles.s.sol:RolesScript \
    --sig "hasRole(string,address)()" $role $address \
    --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv \
    --sender $ACCOUNT_ADDRESS

echo ""
echo "hasRole complete"
