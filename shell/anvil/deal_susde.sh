#!/bin/bash

# deal_susde.sh - Deal sUSDe to a wallet on a local anvil fork

set -euo pipefail

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <recipient_address> <amount_wei> [source_address]"
    echo "Example: $0 0x1A5309F208f161a393E8b5A253de8Ab894A67188 1000000000000000000"
    echo "Example: $0 0x1A5309F208f161a393E8b5A253de8Ab894A67188 1000000000000000000 0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2"
    echo ""
    echo "Note: Script requires anvil running with --auto-impersonate:"
    echo "  pnpm run anvil:fork"
    exit 1
fi

RECIPIENT=$1
AMOUNT_WEI=$2
SOURCE=${3:-0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2}
RPC_URL=${RPC_URL:-"http://127.0.0.1:8545"}
SUSDE="0x9D39A5DE30e57443BfF2A8307A4256c8797A3497"

if ! [[ "$AMOUNT_WEI" =~ ^[0-9]+$ ]] || [ "$AMOUNT_WEI" -eq 0 ]; then
    echo "Error: amount_wei must be a positive integer"
    exit 1
fi

# Check if anvil is running
if ! cast block-number --rpc-url "$RPC_URL" &> /dev/null; then
    echo "Error: Cannot connect to anvil at $RPC_URL"
    echo "Please start anvil fork first:"
    echo "  pnpm run anvil:fork"
    echo "Or set a custom RPC URL:"
    echo "  RPC_URL=http://localhost:8545 $0 <recipient_address> <amount_wei> [source_address]"
    exit 1
fi

echo "=== Dealing sUSDe ==="
echo "Recipient: $RECIPIENT"
echo "Amount (wei): $AMOUNT_WEI"
echo "Source: $SOURCE"
echo "Token: $SUSDE"
echo ""

RECIPIENT_BALANCE_BEFORE=$(cast call "$SUSDE" "balanceOf(address)(uint256)" "$RECIPIENT" --rpc-url "$RPC_URL")
SOURCE_BALANCE_BEFORE=$(cast call "$SUSDE" "balanceOf(address)(uint256)" "$SOURCE" --rpc-url "$RPC_URL")

echo "Recipient balance before: $RECIPIENT_BALANCE_BEFORE"
echo "Source balance before:    $SOURCE_BALANCE_BEFORE"

echo "Funding $SOURCE with ETH for gas..."
cast rpc --rpc-url "$RPC_URL" anvil_setBalance "$SOURCE" "0xDE0B6B3A7640000" --silent

echo "Transferring sUSDe from $SOURCE to $RECIPIENT..."
cast send --unlocked --from "$SOURCE" "$SUSDE" "transfer(address,uint256)" "$RECIPIENT" "$AMOUNT_WEI" \
    --rpc-url "$RPC_URL"

RECIPIENT_BALANCE_AFTER=$(cast call "$SUSDE" "balanceOf(address)(uint256)" "$RECIPIENT" --rpc-url "$RPC_URL")
SOURCE_BALANCE_AFTER=$(cast call "$SUSDE" "balanceOf(address)(uint256)" "$SOURCE" --rpc-url "$RPC_URL")

echo ""
echo "Recipient balance after:  $RECIPIENT_BALANCE_AFTER"
echo "Source balance after:     $SOURCE_BALANCE_AFTER"
echo ""
echo "=== SUCCESS ==="
echo "Transferred $AMOUNT_WEI sUSDe (wei) to $RECIPIENT."
