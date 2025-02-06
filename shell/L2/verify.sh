#!/bin/bash

# Verifies the deployment.
#
# Usage:
# ./verify.sh --env <env-file>
#
# Environment variables:
# RPC_URL
# CHAIN

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

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "No chain specified. Specify the CHAIN in the $ENV_FILE file."
validate_text "$RPC_URL" "No RPC URL specified. Specify the RPC_URL in the $ENV_FILE file."

echo ""
echo "Summary:"
echo "  Chain: $CHAIN"
echo "  Using RPC at URL: $RPC_URL"

# Deploy using script
echo ""
echo "Running forge script"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "verify(string)()" $CHAIN \
    --rpc-url $RPC_URL --slow -vvv

echo ""
echo "Verification complete"
