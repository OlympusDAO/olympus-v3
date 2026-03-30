#!/bin/bash

set -euo pipefail

RPC_URL=${RPC_URL:-"http://127.0.0.1:8545"}
RECIPIENT=${1:-}
AMOUNT_WEI=${2:-10000000000000000000}

if [ -z "$RECIPIENT" ]; then
    echo "Usage: $0 <recipient_address> [amount_wei]"
    echo "Example: $0 0x2075e3b46470cfcE124Daaf52b46Dcf965727Dd1"
    echo "Example: $0 0x2075e3b46470cfcE124Daaf52b46Dcf965727Dd1 10000000000000000000"
    exit 1
fi

if ! [[ "$AMOUNT_WEI" =~ ^[0-9]+$ ]] || [ "$AMOUNT_WEI" -eq 0 ]; then
    echo "Error: amount_wei must be a positive integer"
    echo "Usage: $0 [recipient_address] [amount_wei]"
    exit 1
fi

if ! cast block-number --rpc-url "$RPC_URL" > /dev/null 2>&1; then
    echo "Error: Cannot connect to anvil at $RPC_URL"
    echo "Please start anvil fork first (for example: pnpm run anvil:fork)"
    exit 1
fi

BALANCE_BEFORE_WEI=$(cast balance --rpc-url "$RPC_URL" "$RECIPIENT")
BALANCE_BEFORE_ETH=$(cast balance --rpc-url "$RPC_URL" --ether "$RECIPIENT")

echo "=== Deal ETH on Anvil ==="
echo "Recipient: $RECIPIENT"
echo "Target balance (wei): $AMOUNT_WEI"
echo "Balance before: $BALANCE_BEFORE_WEI wei ($BALANCE_BEFORE_ETH ETH)"

HEX_BALANCE=$(printf '0x%x' "$AMOUNT_WEI")
cast rpc --rpc-url "$RPC_URL" anvil_setBalance "$RECIPIENT" "$HEX_BALANCE" --silent > /dev/null

BALANCE_AFTER_WEI=$(cast balance --rpc-url "$RPC_URL" "$RECIPIENT")
BALANCE_AFTER_ETH=$(cast balance --rpc-url "$RPC_URL" --ether "$RECIPIENT")

echo "Balance after:  $BALANCE_AFTER_WEI wei ($BALANCE_AFTER_ETH ETH)"
echo "=== SUCCESS ==="
