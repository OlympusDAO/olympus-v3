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

# Deploy using script
echo ""
echo "Checking Berachain"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "verifyBerachain(string)()" "berachain" \
    --rpc-url "https://rpc.berachain.com" --slow -vvv

echo ""
echo "Checking Mainnet"
forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "verifyMainnet(string)()" "mainnet" \
    --rpc-url "https://eth.llamarpc.com" --slow -vvv

echo ""
echo "Verification complete"
