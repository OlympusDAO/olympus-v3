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
# [--nonce <nonce>]
# [--broadcast <true|false>]
# [--tenderly <true|false>]
# [--fork <true|false>]
# [--owner <dao|emergency>] (fork mode only: the multisig to impersonate; defaults to dao)
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
for arg in "$@"; do
    case "$arg" in
        --signonly | --signature)
            display_error "$arg has been removed. Use --broadcast true to sign and propose a Safe batch in one run."
            exit 1
            ;;
    esac
done
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
broadcast=${broadcast:-false}
tenderly=${tenderly:-false}
fork=${fork:-false}
multisig=${multisig:-false}
verbose=${verbose:-false}
owner=${owner:-dao}
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
validate_boolean "$verbose" "Invalid value for --verbose. Must be true or false."
if [ "$owner" != "dao" ] && [ "$owner" != "emergency" ]; then
    display_error "Invalid value for --owner. Must be dao or emergency."
    exit 1
fi

# Safe proposals sign through cast via FFI. Forge must not open the same Ledger.
if [ "$multisig" == "true" ] && [ -n "$ledger" ] && [ -z "$account" ]; then
    validate_number "$ledger" "Invalid Ledger mnemonic index. Must be a non-negative integer."
    set_account_address_ledger "$ledger"
    ACCOUNT_FLAG=""
    LEDGER_FLAGS=""
    LEDGER_DERIVATION_PATH="m/44'/60'/${ledger}'/0/0"
else
    validate_and_set_account "$account" "$ledger"
    LEDGER_DERIVATION_PATH=""
fi

# Handle fork mode (before summary so chain displays correctly)
if [ "$fork" == "true" ]; then
    # Verify Anvil is running
    if ! curl -sSf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
        display_error "Anvil is not running on http://localhost:8545. Start it with: pnpm run anvil:fork"
        exit 1
    fi

    # Set the unlocked address: the multisig whose batch functions are being run
    ACCOUNT_ADDRESS="$(get_address_not_zero "$chain" "olympus.multisig.$owner")"
    ACCOUNT_FLAG=""
    LEDGER_FLAGS=""
    LEDGER_DERIVATION_PATH=""
    UNLOCKED_FLAG="--unlocked"

    # Override RPC and set env var for Anvil mode
    chain="http://localhost:8545"
    export USE_ANVIL_FORK=true
    export USE_TENDERLY_FORK=false
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
echo "  Tenderly mode: $tenderly"
echo "  Fork mode: $fork"
echo "  Fork owner: $owner"
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

# Set the nonce
export SAFE_NONCE=$nonce

# Set verbosity level
if [ "$verbose" == "true" ]; then
    VERBOSITY="-vvvv"
else
    VERBOSITY="-vvv"
fi

# Use deployment compiler settings while simulating the batch calls in one transaction.
FORGE_CMD="FOUNDRY_PROFILE=deploy forge script ./src/scripts/ops/batches/$contract.sol:$contract --sig \"$function(bool,string,string)()\" $multisig \"$ARGS_FILE\" \"$LEDGER_DERIVATION_PATH\" --rpc-url $chain $ACCOUNT_FLAG $LEDGER_FLAGS --sender $ACCOUNT_ADDRESS $UNLOCKED_FLAG --no-isolate --slow $VERBOSITY"

# Add broadcast flag
if [ "$broadcast" == "true" ]; then
    FORGE_CMD="$FORGE_CMD --broadcast"
fi

# Execute the command
eval $FORGE_CMD

echo ""
echo "Batch complete"
