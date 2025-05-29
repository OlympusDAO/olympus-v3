#!/bin/bash

# Bridges OHM to the specified address and EVM chain using CCIP
#
# Usage:
# ./bridge_ccip_evm.sh
#   --fromChain <chain>
#   --toChain <chain>
#   --to <recipient address>
#   --amount <amount>
#   --account <cast wallet>
#   --broadcast <false>
#   --env <file>
#
# Environment variables:
# RPC_URL
# CHAIN

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$fromChain" "No from chain specified. Provide the from chain after the --from-chain flag."
validate_text "$toChain" "No to chain specified. Provide the to chain after the --to-chain flag."
validate_address "$to" "No recipient specified or it is not an EVM address. Provide the recipient after the --to flag."
validate_number "$amount" "No amount specified. Provide the amount after the --amount flag."
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."
validate_text "$CHAIN" "No chain specified. Specify the CHAIN in the $ENV_FILE file."

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Using RPC at URL: $RPC_URL"
echo "  From chain: $fromChain"
echo "  To chain: $toChain"
echo "  To: $to"
echo "  Amount: $amount"

# Validate and set forge script flags
source $SCRIPT_DIR/lib/forge.sh
set_broadcast_flag $BROADCAST
set_account_address $account

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/ops/BridgeCCIP.s.sol:BridgeCCIPScript \
    --sig "bridgeToEVM(string,string,address,uint256)()" $fromChain $toChain $to $amount \
    --rpc-url $RPC_URL \
    --account $account \
    --slow \
    -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG

echo ""
echo "Bridge complete"
