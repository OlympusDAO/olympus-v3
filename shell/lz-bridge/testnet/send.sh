#!/bin/bash
# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

# Sends OHM across the testnet bridge from one chain to another, then records the message in
# deployments/messages.json (source tx hash + metadata) so its status can be tracked later.
#
# Usage:
# ./shell/lz-bridge/testnet/send.sh
#   --chain <source chain>          (sepolia | base-sepolia | arbitrum-sepolia)
#   --dst <destination chain>       (sepolia | base-sepolia | arbitrum-sepolia)
#   --amount <ohm amount, 9 decimals>   (1 OHM == 1000000000)
#   --account <cast wallet> OR --ledger <mnemonic-index>
#   [--recipient <address>]         (defaults to the sender address)
#   [--broadcast <true>]            (defaults to true)
#
# Requires ALCHEMY_API_KEY in .env, plus jq and cast.

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2> /dev/null)
[ -n "$ROOT_DIR" ] || {
    echo "Error: not inside a git repository." >&2
    exit 1
}
source "$ROOT_DIR/shell/lib/arguments.sh"
source "$ROOT_DIR/shell/lib/forge.sh"

load_named_args "$@"

# Load .env so the foundry rpc alias can substitute ALCHEMY_API_KEY.
[ -f "$ROOT_DIR/.env" ] && set -a && source "$ROOT_DIR/.env" && set +a

validate_text "$chain" "No source chain. Use --chain <sepolia|base-sepolia|arbitrum-sepolia>."
validate_text "$dst" "No destination chain. Use --dst <sepolia|base-sepolia|arbitrum-sepolia>."
validate_text "$amount" "No amount. Use --amount <ohm with 9 decimals>."

validate_chain_name() {
    case "$1" in
        sepolia | base-sepolia | arbitrum-sepolia) ;;
        *)
            display_error "Unsupported chain '$1'. Use sepolia|base-sepolia|arbitrum-sepolia."
            exit 1
            ;;
    esac
}

validate_chain_name "$chain"
validate_chain_name "$dst"

BROADCAST=${broadcast:-true}
set_broadcast_flag "$BROADCAST"
validate_and_set_account "$account" "$ledger"

RECIPIENT=${recipient:-$ACCOUNT_ADDRESS}

eid_for_chain() {
    case "$1" in
        sepolia) echo 40161 ;;
        base-sepolia) echo 40245 ;;
        arbitrum-sepolia) echo 40231 ;;
        *) return 1 ;;
    esac
}

echo ""
echo "Sending $amount OHM (9dp) from $chain to $dst, recipient $RECIPIENT"

FOUNDRY_PROFILE=deploy forge script \
    ./src/scripts/lz-bridge-testnet/LZBridgeTestnetSend.s.sol:LZBridgeTestnetSend \
    --sig "send(string,address,uint256)" "$dst" "$RECIPIENT" "$amount" \
    --rpc-url "$chain" \
    $ACCOUNT_FLAG \
    $LEDGER_FLAGS \
    --slow \
    -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG

# Record the message only on a real broadcast.
if [ "$(echo "$BROADCAST" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
    echo "Dry run (broadcast disabled): not recording a message."
    exit 0
fi

CHAIN_ID=$(cast chain-id --rpc-url "$chain")
RUN_JSON="$ROOT_DIR/broadcast/LZBridgeTestnetSend.s.sol/$CHAIN_ID/run-latest.json"
if [ ! -f "$RUN_JSON" ]; then
    echo "Could not find broadcast output at $RUN_JSON; message not recorded."
    exit 1
fi

# The sendOhm call is the last transaction whose function starts with "sendOhm".
TX_HASH=$(jq -r '[.transactions[] | select((.function // "") | startswith("sendOhm")) | .hash] | last // empty' "$RUN_JSON")
if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
    echo "Could not extract sendOhm tx hash from $RUN_JSON; message not recorded."
    exit 1
fi

MESSAGES="$ROOT_DIR/src/scripts/lz-bridge-testnet/deployments/messages.json"
[ -f "$MESSAGES" ] || echo '[]' > "$MESSAGES"

SRC_EID=$(eid_for_chain "$chain") || exit 1
DST_EID=$(eid_for_chain "$dst") || exit 1

ENTRY=$(jq -n \
    --arg src "$chain" \
    --arg dst "$dst" \
    --argjson srcEid "$SRC_EID" \
    --argjson dstEid "$DST_EID" \
    --arg recipient "$RECIPIENT" \
    --arg amount "$amount" \
    --arg tx "$TX_HASH" \
    '{srcChain:$src, dstChain:$dst, srcEid:$srcEid, dstEid:$dstEid, recipient:$recipient, amount:$amount, srcTxHash:$tx, status:"PENDING"}')

jq --argjson e "$ENTRY" '. + [$e]' "$MESSAGES" > "$MESSAGES.tmp" && mv "$MESSAGES.tmp" "$MESSAGES"

echo ""
echo "Recorded message in $MESSAGES"
echo "  srcTxHash: $TX_HASH"
echo "Check status with: ./shell/lz-bridge/testnet/message_status.sh"
