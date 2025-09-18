#!/bin/bash

# Run a multisig batch
#
# Usage:
# ./safeBatchV2.sh
# --contract <contract-name>
# --function <function-name>
# --account <cast wallet> OR --ledger <mnemonic-index>
# --chain <chain-name>
# [--multisig <true|false>]
# [--broadcast <true|false>]
# [--testnet <true|false>]
# [--args <args-file>]
# [--env <env-file>]

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
source $SCRIPT_DIR/lib/forge.sh
source $SCRIPT_DIR/lib/error.sh
source $SCRIPT_DIR/lib/addresses.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
broadcast=${broadcast:-false}
testnet=${testnet:-false}
multisig=${multisig:-false}
ARGS_FILE=${args:-}

# Validate named arguments
echo ""
echo "Validating named arguments"
validate_text "$contract" "No contract name provided. Provide the contract name after the --contract flag."
validate_text "$function" "No function name provided. Provide the function name after the --function flag."
validate_text "$chain" "No chain specified. Specify the chain after the --chain flag."
validate_boolean "$testnet" "Invalid value for --testnet. Must be true or false."
validate_boolean "$broadcast" "Invalid value for --broadcast. Must be true or false."
validate_boolean "$multisig" "Invalid value for --multisig. Must be true or false."

# Validate and set account flags (consistent with deployV3.sh)
validate_and_set_account "$account" "$ledger"

echo ""
echo "Summary:"
echo "  Contract name: $contract"
echo "  Function name: $function"
echo "  Chain: $chain"
echo "  Account address: $ACCOUNT_ADDRESS"
echo "  Executing as multisig: $multisig"
echo "  Testnet: $testnet"
echo "  Broadcasting: $broadcast"
if [ -n "$ARGS_FILE" ]; then
    echo "  Args file: $ARGS_FILE"
else
    echo "  Args file: (none)"
fi

# Execute the batch
export TESTNET=$testnet

# Build forge command
FORGE_CMD="forge script ./src/scripts/ops/batches/$contract.sol:$contract --sig \"$function(bool,string)()\" $multisig \"$ARGS_FILE\" --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --sender $ACCOUNT_ADDRESS --slow -vvv"

# Add broadcast flag only if not executing as multisig
if [ "$multisig" != "true" ] && [ "$broadcast" == "true" ]; then
    FORGE_CMD="$FORGE_CMD --broadcast"
fi

# Execute the command
eval $FORGE_CMD

echo ""
echo "Batch complete"
