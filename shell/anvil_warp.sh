#!/bin/bash

# anvil_warp.sh - Script to mine blocks on a local anvil fork

# Exit if any error occurs
set -e

# Check if block count argument provided
if [ -z "$1" ]; then
    echo "Usage: $0 <block_count>"
    exit 1
fi

BLOCK_COUNT=$1

# Validate it's a positive integer
if ! [[ "$BLOCK_COUNT" =~ ^[0-9]+$ ]] || [ "$BLOCK_COUNT" -eq 0 ]; then
    echo "Error: block_count must be a positive integer"
    exit 1
fi

BLOCK_HEX=$(cast to-hex "$BLOCK_COUNT")

echo "Mining $BLOCK_COUNT blocks on http://localhost:8545..."
cast rpc --rpc-url http://localhost:8545 anvil_mine "$BLOCK_HEX"

echo "Complete."
echo ""
echo "Current block:"
cast block-number --rpc-url http://localhost:8545
echo ""
