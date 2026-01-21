#!/bin/bash

# warp.sh - Script to mine blocks on a local anvil fork

# Exit if any error occurs
set -e

# Check if block count argument provided
if [ -z "$1" ]; then
    echo "Usage: $0 <block_count>"
    echo "Example: $0 100"
    echo "Note: Script requires anvil running with --auto-impersonate:"
    echo "  pnpm run anvil:fork"
    exit 1
fi

BLOCK_COUNT=$1
RPC_URL="http://localhost:8545"

# Check if anvil is running
if ! cast block-number --rpc-url $RPC_URL &> /dev/null; then
    echo "Error: Cannot connect to anvil at $RPC_URL"
    echo "Please start anvil fork first:"
    echo "  pnpm run anvil:fork"
    exit 1
fi

# Validate it's a positive integer
if ! [[ "$BLOCK_COUNT" =~ ^[0-9]+$ ]] || [ "$BLOCK_COUNT" -eq 0 ]; then
    echo "Error: block_count must be a positive integer"
    exit 1
fi

BLOCK_HEX=$(cast to-hex "$BLOCK_COUNT")

echo "Mining $BLOCK_COUNT blocks on $RPC_URL..."
cast rpc --rpc-url $RPC_URL anvil_mine "$BLOCK_HEX"

echo "Complete."
echo ""
echo "Current block:"
cast block-number --rpc-url $RPC_URL
echo ""
