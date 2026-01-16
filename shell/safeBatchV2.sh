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
# [--signonly <true|false>]
# [--signature <signature>]
# [--nonce <nonce>]
# [--broadcast <true|false>]
# [--tenderly <true|false>]
# [--fork <true|false>]
# [--verbose <true|false>]
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
tenderly=${tenderly:-false}
fork=${fork:-false}
multisig=${multisig:-false}
signonly=${signonly:-false}
verbose=${verbose:-false}
signature=${signature:-"0x"}
ARGS_FILE=${args:-}

# Validate named arguments
echo ""
echo "Validating named arguments"
validate_text "$contract" "No contract name provided. Provide the contract name after the --contract flag."
validate_text "$function" "No function name provided. Provide the function name after the --function flag."
validate_text "$chain" "No chain specified. Specify the chain after the --chain flag."
validate_boolean "$tenderly" "Invalid value for --tenderly. Must be true or false."
validate_boolean "$fork" "Invalid value for --fork. Must be true or false."
validate_boolean "$broadcast" "Invalid value for --broadcast. Must be true or false."
validate_boolean "$multisig" "Invalid value for --multisig. Must be true or false."
validate_boolean "$signonly" "Invalid value for --signonly. Must be true or false."
validate_boolean "$verbose" "Invalid value for --verbose. Must be true or false."

# Handle fork mode (before summary so chain displays correctly)
if [ "$fork" == "true" ]; then
    # Verify Anvil is running
    if ! curl -sSf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
        display_error "Anvil is not running on http://localhost:8545. Start it with: pnpm run anvil:fork"
        exit 1
    fi

    # Override RPC and set env var for Anvil mode
    chain="http://localhost:8545"
    export USE_ANVIL_FORK=true
else
    # Set USE_TENDERLY_FORK based on tenderly flag
    export USE_TENDERLY_FORK=$tenderly
fi

echo ""
echo "Summary:"
echo "  Contract name: $contract"
echo "  Function name: $function"
echo "  Chain: $chain"
echo "  Account address: $ACCOUNT_ADDRESS"
echo "  Executing as multisig: $multisig"
echo "  Sign only: $signonly"
echo "  Tenderly mode: $tenderly"
echo "  Fork mode: $fork"
echo "  Broadcasting: $broadcast"
echo "  Verbose: $verbose"
if [ -n "$ARGS_FILE" ]; then
    echo "  Args file: $ARGS_FILE"
else
    echo "  Args file: (none)"
fi
if [ -n "$nonce" ]; then
    echo "  Nonce: $nonce"
else
    echo "  Nonce: (default)"
fi

# Validate and set account flags (consistent with deployV3.sh)
if [ "$signonly" == "true" ]; then
    # Validate that multisig is also true
    if [ "$multisig" != "true" ]; then
        display_error "When --signonly is true, --multisig must also be true."
        exit 1
    fi

    # Validate that a signature is not provided
    if [ "$signature" != "0x" ]; then
        display_error "When --signonly is true, --signature must not be provided."
        exit 1
    fi

    validate_text "$ledger" "No ledger index provided. Provide the mnemonic index after the --ledger flag."

    set_account_address_ledger "$ledger"

    # Calculate the derivation path
    LEDGER_DERIVATION_PATH="m/44'/60'/${ledger}'/0/0"
    # validate_and_set_account is not used, as it would set the LEDGER_FLAGS variable to use the Ledger. This would block ffi calls within the script from using the Ledger.
    echo "  The script will result in your Ledger device prompting for approval of a signature."
else
    validate_and_set_account "$account" "$ledger"
    LEDGER_DERIVATION_PATH=""
fi

# Set the nonce
export SAFE_NONCE=$nonce

# Set verbosity level
if [ "$verbose" == "true" ]; then
    VERBOSITY="-vvvv"
else
    VERBOSITY="-vvv"
fi

# Build forge command
FORGE_CMD="forge script ./src/scripts/ops/batches/$contract.sol:$contract --sig \"$function(bool,bool,string,string,bytes)()\" $multisig $signonly \"$ARGS_FILE\" \"$LEDGER_DERIVATION_PATH\" $signature --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --sender $ACCOUNT_ADDRESS --slow $VERBOSITY"

# Add broadcast flag
if [ "$broadcast" == "true" ]; then
    FORGE_CMD="$FORGE_CMD --broadcast"
fi

# Execute the command
eval $FORGE_CMD

echo ""
echo "Batch complete"
