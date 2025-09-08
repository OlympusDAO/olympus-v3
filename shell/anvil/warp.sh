#!/bin/bash

# Script to warp time forward on anvil fork
# Usage: ./shell/anvil/warp.sh <seconds> [rpc_url]
#
# Examples:
#   ./shell/anvil/warp.sh 950400                 # Warp 11 days forward (950400 seconds)
#   ./shell/anvil/warp.sh 3600                   # Warp 1 hour forward
#   ./shell/anvil/warp.sh 86400 http://localhost:8546  # Use custom RPC URL

set -e

# Default RPC URL
DEFAULT_RPC_URL="http://localhost:8545"

usage() {
    echo "Usage: $0 <seconds> [rpc_url]"
    echo ""
    echo "Examples:"
    echo "  $0 950400                           # 11 days (OCG proposal delay)"
    echo "  $0 86400                            # 1 day"
    echo "  $0 3600                             # 1 hour"
    echo "  $0 950400 http://localhost:8546     # Custom RPC URL"
    echo ""
    echo "Default RPC URL: $DEFAULT_RPC_URL"
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
    echo "Error: Wrong number of arguments"
    usage
fi

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

SECONDS_TO_WARP="$1"
RPC_URL="${2:-$DEFAULT_RPC_URL}"

# Validate seconds is a positive number
if ! [[ "$SECONDS_TO_WARP" =~ ^[0-9]+$ ]] || [[ "$SECONDS_TO_WARP" -le 0 ]]; then
    echo "Error: Seconds must be a positive integer"
    usage
fi

echo "Warping time forward by $SECONDS_TO_WARP seconds..."

# Check if anvil is running
if ! curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; then
    echo "Error: Cannot connect to anvil at $RPC_URL"
    echo "Make sure anvil is running with: anvil --fork-url \$FORK_TEST_RPC_URL --allow-origin-passthrough --auto-impersonate"
    exit 1
fi

# Get current timestamp for reference
CURRENT_TIMESTAMP=$(cast rpc eth_getBlockByNumber "latest" false --rpc-url "$RPC_URL" | jq -r '.timestamp' | xargs printf "%d\n")
echo "Current timestamp: $CURRENT_TIMESTAMP"

# Increase time
echo "Increasing time by $SECONDS_TO_WARP seconds..."
cast rpc evm_increaseTime "$SECONDS_TO_WARP" --rpc-url "$RPC_URL" > /dev/null

# Mine a block to apply the change
echo "Mining block to apply time change..."
cast rpc evm_mine --rpc-url "$RPC_URL" > /dev/null

# Get new timestamp to verify
NEW_TIMESTAMP=$(cast rpc eth_getBlockByNumber "latest" false --rpc-url "$RPC_URL" | jq -r '.timestamp' | xargs printf "%d\n")
ACTUAL_DIFF=$((NEW_TIMESTAMP - CURRENT_TIMESTAMP))

echo "New timestamp: $NEW_TIMESTAMP"
echo "Actual time difference: $ACTUAL_DIFF seconds"
echo "Time warp completed successfully!"
