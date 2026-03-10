#!/bin/bash

# This script prints the inputs for a proposal to the governor.
#
# Usage:
# src/scripts/proposals/printInputs.sh
#   --file <proposal-path>
#   --contract <contract-name>
#   --chain <chain-name-or-url> (e.g. mainnet, base, or provide a custom RPC URL)
#   [--env <env-file>]

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/../../../shell/lib/arguments.sh

load_named_args "$@"
load_env

echo ""
echo "Validating arguments"
validate_file "$file" "Proposal file not found. Provide correct path after --file."
validate_text "$contract" "Contract name not specified. Use --contract."
validate_text "$chain" "No chain specified. Specify the chain after the --chain flag."

FORK_FLAGS=""
if [[ "$chain" == *"localhost"* ]] || [[ "$chain" == *"127.0.0.1"* ]]; then
    FORK_FLAGS="--legacy"
fi

echo ""
echo "Summary:"
echo "  Proposal: $file:$contract"
echo "  Chain: $chain"

echo ""
echo "Running forge script..."
forge script $file:$contract --sig "printProposalInputs()" --rpc-url $chain $FORK_FLAGS -vvv
