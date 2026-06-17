#!/bin/bash

# Reports the LayerZero status of bridge messages by querying the LayerZero Scan testnet API
# (https://scan-testnet.layerzero-api.com) by source transaction hash.
#
# Usage:
#   # All messages recorded by send.sh:
#   ./shell/lz-bridge/testnet/message_status.sh
#
#   # A single source tx hash (also works for any external testnet bridge tx):
#   ./shell/lz-bridge/testnet/message_status.sh --tx 0x<sourceTxHash>
#
#   # A custom messages file:
#   ./shell/lz-bridge/testnet/message_status.sh --messages path/to/messages.json
#
# Requires curl and jq.

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2> /dev/null)
[ -n "$ROOT_DIR" ] || {
    echo "Error: not inside a git repository." >&2
    exit 1
}
source "$ROOT_DIR/shell/lib/arguments.sh"

load_named_args "$@"

API_BASE="https://scan-testnet.layerzero-api.com/v1"
MESSAGES=${messages:-"$ROOT_DIR/src/scripts/lz-bridge-testnet/deployments/messages.json"}

command -v jq > /dev/null || {
    echo "jq is required"
    exit 1
}
command -v curl > /dev/null || {
    echo "curl is required"
    exit 1
}

# Queries the API for one source tx hash and prints a one-line summary.
# Echoes the resolved status name on the last line so callers can capture it.
report_tx() {
    local tx="$1"
    local resp status dsttx guid src_eid dst_eid
    resp=$(curl -sf --max-time 20 "$API_BASE/messages/tx/$tx" 2> /dev/null) || {
        echo "  $tx -> no LZ Scan data (not indexed yet, or API unavailable); keeping prior status"
        echo "__NO_UPDATE__"
        return
    }

    if [ -z "$resp" ] || [ "$(echo "$resp" | jq -r '.data | length')" = "0" ]; then
        echo "  $tx -> NOT INDEXED YET (pending, or wrong/old hash)"
        echo "PENDING"
        return
    fi

    status=$(echo "$resp" | jq -r '.data[0].status.name // "UNKNOWN"')
    src_eid=$(echo "$resp" | jq -r '.data[0].pathway.srcEid // "?"')
    dst_eid=$(echo "$resp" | jq -r '.data[0].pathway.dstEid // "?"')
    dsttx=$(echo "$resp" | jq -r '.data[0].destination.tx.txHash // "-"')
    guid=$(echo "$resp" | jq -r '.data[0].guid // "-"')

    echo "  $tx"
    echo "    status:  $status   (srcEid $src_eid -> dstEid $dst_eid)"
    echo "    guid:    $guid"
    echo "    dst tx:  $dsttx"
    echo "$status"
}

echo ""
echo "Querying LayerZero Scan testnet API: $API_BASE"

# Single-hash mode.
if [ -n "$tx" ]; then
    report_tx "$tx" | sed '$d' # drop the trailing status-only line
    exit 0
fi

# File mode: iterate recorded messages and write back the latest status.
if [ ! -f "$MESSAGES" ]; then
    echo "No messages file at $MESSAGES. Send a message first with send.sh, or pass --tx."
    exit 1
fi

COUNT=$(jq 'length' "$MESSAGES")
if [ "$COUNT" = "0" ]; then
    echo "No messages recorded in $MESSAGES."
    exit 0
fi

echo "Found $COUNT recorded message(s) in $MESSAGES"
echo ""

UPDATED="[]"
for i in $(seq 0 $((COUNT - 1))); do
    ENTRY=$(jq ".[$i]" "$MESSAGES")
    TX=$(echo "$ENTRY" | jq -r '.srcTxHash')
    SRC=$(echo "$ENTRY" | jq -r '.srcChain')
    DST=$(echo "$ENTRY" | jq -r '.dstChain')
    AMT=$(echo "$ENTRY" | jq -r '.amount')
    echo "[$i] $SRC -> $DST, amount $AMT (9dp)"

    OUT=$(report_tx "$TX")
    echo "$OUT" | sed '$d'
    STATUS=$(echo "$OUT" | tail -n1)

    if [ "$STATUS" = "__NO_UPDATE__" ]; then
        NEW_ENTRY="$ENTRY" # not indexed / API unavailable: keep the prior status
    else
        NEW_ENTRY=$(echo "$ENTRY" | jq --arg s "$STATUS" '.status = $s')
    fi
    UPDATED=$(echo "$UPDATED" | jq --argjson e "$NEW_ENTRY" '. + [$e]')
    echo ""
done

echo "$UPDATED" > "$MESSAGES.tmp" && mv "$MESSAGES.tmp" "$MESSAGES"
echo "Updated statuses in $MESSAGES"
