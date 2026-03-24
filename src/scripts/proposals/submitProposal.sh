#!/bin/bash

# This script submits a proposal to the governor.
#
# Usage:
# src/scripts/proposals/submitProposal.sh
#   --file <proposal-path>
#   --contract <contract-name>
#   (--account <cast-wallet> OR --ledger <mnemonic-index>)
#   --chain <chain-name-or-url> (e.g. mainnet, base, or provide a custom RPC URL)
#   [--broadcast <true|false>]
#   [--env <env-file>]

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/../../../shell/lib/arguments.sh
source $SCRIPT_DIR/../../../shell/lib/forge.sh

load_named_args "$@"
load_env

BROADCAST=${broadcast:-false}

echo ""
echo "Validating arguments"
validate_file "$file" "Proposal file not found. Provide correct path after --file."
validate_text "$contract" "Contract name not specified. Use --contract."
validate_text "$chain" "No chain specified. Specify the chain after the --chain flag."

validate_and_set_account "$account" "$ledger"

set_broadcast_flag $BROADCAST

FORK_FLAGS=""
if [[ "$chain" == *"localhost"* ]] || [[ "$chain" == *"127.0.0.1"* ]]; then
    FORK_FLAGS="--legacy"
fi

echo ""
echo "Summary:"
echo "  Proposal: $file:$contract"
echo "  Chain: $chain"
echo "  Sender: $ACCOUNT_ADDRESS"

echo ""
echo "Running forge script..."
forge script $file:$contract \
    --rpc-url $chain \
    $ACCOUNT_FLAG \
    $LEDGER_FLAGS \
    --sender $ACCOUNT_ADDRESS \
    $FORK_FLAGS \
    $BROADCAST_FLAG \
    -vvv
