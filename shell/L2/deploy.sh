#!/bin/bash

# Deploys an L2 installation of the Olympus protocol.
#
# Usage:
# ./deploy.sh
#   --account <cast wallet>
#   --ohm <true|false>
#   --broadcast <false>
#   --verify <false>
#   --resume <false>
#   --env <env-file>
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
source $SCRIPT_DIR/../lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}
VERIFY=${verify:-false}
RESUME=${resume:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."
validate_boolean "$ohm" "No ohm flag specified. Provide true or false after the --ohm flag."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "No chain specified. Specify the CHAIN in the $ENV_FILE file."
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Chain: $CHAIN"
echo "  Deploying OHM: $ohm"
echo "  Using RPC at URL: $RPC_URL"

# Validate and set forge script flags
source $SCRIPT_DIR/../lib/forge.sh
set_broadcast_flag $BROADCAST
set_verify_flag $VERIFY $ETHERSCAN_KEY $VERIFIER_URL
set_resume_flag $RESUME
set_account_address $account

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "deploy(string,bool)()" $CHAIN $ohm \
    --rpc-url $RPC_URL --account $account --slow -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG \
    $VERIFY_FLAG \
    $RESUME_FLAG

echo ""
echo "Deployment complete"
