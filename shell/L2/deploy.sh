#!/bin/bash

# Deploys an L2 installation of the Olympus protocol.
#
# Usage:
# ./deploy.sh --account <cast wallet> --broadcast <false> --verify <false> --resume <false> --env <env-file>
#
# Environment variables:
# RPC_URL
# CHAIN
# ETHERSCAN_KEY (only needed if verify is true)
# VERIFIER_URL (only needed for a custom verifier or on a fork)

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${BROADCAST:-false}
VERIFY=${VERIFY:-false}
RESUME=${RESUME:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "No chain specified. Specify the CHAIN in the $ENV_FILE file."
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Chain: $CHAIN"
echo "  Using RPC at URL: $RPC_URL"

# Validate and set forge script flags
source $SCRIPT_DIR/lib/forge.sh
set_broadcast_flag $BROADCAST
set_verify_flag $VERIFY $ETHERSCAN_KEY $VERIFIER_URL
set_resume_flag $RESUME

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "deploy(string)()" $CHAIN \
    --rpc-url $RPC_URL --account $account --slow -vvv \
    $BROADCAST_FLAG \
    $VERIFY_FLAG \
    $RESUME_FLAG

echo ""
echo "Deployment complete"

# Step 1.2: Install into kernel
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "installBridge(address,address,address)()" $ARB_GOERLI_KERNEL "0xeac3eC0CC130f4826715187805d1B50e861F2DaC" $ARB_GOERLI_BRIDGE --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network

# Step 2: Setup paths to other bridges. Repeat n times.
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address,uint16)()" $ARB_BRIDGE $MAINNET_BRIDGE $MAINNET_LZ_CHAIN_ID --rpc-url $ARB_RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast

# for goerli
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address, uint16)()" $GOERLI_BRIDGE $ARB_GOERLI_BRIDGE $ARB_GOERLI_LZ_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast

# Step 3: If new chain, pass executor and roles to MS
