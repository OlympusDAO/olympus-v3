#!/bin/bash

# Deploys a sequence of contracts using the V3 deployment script.
#
# Usage:
# ./deployV3.sh
#   --account <cast wallet>
#   --sequence <sequence-file>
#   --chain <chain-name>
#   [--broadcast <false>]
#   [--verify <false>]
#   [--resume <false>]
#   [--env <env-file>]
#
# Environment variables:
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
BROADCAST=${broadcast:-false}
VERIFY=${verify:-false}
RESUME=${resume:-false}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_text "$sequence" "No deployment sequence specified or it does not exist. Provide the relative path after the --sequence flag."
validate_text "$account" "No account specified. Provide the cast wallet after the --account flag."
validate_text "$chain" "No chain specified. Specify the chain after the --chain flag."

# Validate environment variables
echo ""
echo "Validating environment variables"

echo ""
echo "Summary:"
echo "  Deploying from account: $account"
echo "  Deployment sequence: $sequence"
echo "  Chain: $chain"

# Validate and set forge script flags
source $SCRIPT_DIR/lib/forge.sh
set_broadcast_flag $BROADCAST
set_verify_flag $VERIFY $ETHERSCAN_KEY $VERIFIER_URL
set_resume_flag $RESUME
set_account_address $account

# Deploy using script
echo ""
echo "Running forge script"
FOUNDRY_PROFILE=deploy forge script ./src/scripts/deploy/DeployV3.s.sol:DeployV3 \
    --sig "deploy(string)()" $sequence \
    --rpc-url $chain \
    --account $account \
    --slow \
    -vvv \
    --sender $ACCOUNT_ADDRESS \
    $BROADCAST_FLAG \
    $VERIFY_FLAG \
    $RESUME_FLAG
