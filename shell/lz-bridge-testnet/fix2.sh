#!/bin/bash

# Drops the Nethermind DVN from the bridge config (re-applies the 2-DVN set from
# LZTestnetConfig.sol on all three chains). A message stuck only on Nethermind verification
# becomes deliverable afterwards, so skipping is usually NOT needed; pass --skip true as a
# fallback if it still does not deliver.
#
# Usage:
#   ./shell/lz-bridge-testnet/fix2.sh --account <wallet> --broadcast true
#   ./shell/lz-bridge-testnet/fix2.sh --account <wallet> --broadcast true \
#       --skip true --dst base-sepolia --src sepolia --nonce 2
#
# Requires ALCHEMY_API_KEY in .env.

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
source "$SCRIPT_DIR/../lib/arguments.sh"
source "$SCRIPT_DIR/../lib/forge.sh"

load_named_args "$@"

[ -f "$ROOT_DIR/.env" ] && set -a && source "$ROOT_DIR/.env" && set +a

BROADCAST=${broadcast:-false}
set_broadcast_flag "$BROADCAST"
validate_and_set_account "$account" "$ledger"

SCRIPT="./src/scripts/lz-bridge-testnet/LZBridgeTestnetFix.s.sol:LZBridgeTestnetFix"
CHAINS=(sepolia base-sepolia arbitrum-sepolia)

for c in "${CHAINS[@]}"; do
    echo ""
    echo "=== Reapplying DVN config on $c ==="
    FOUNDRY_PROFILE=deploy forge script "$SCRIPT" \
        --sig "reapplyConfig()" \
        --rpc-url "$c" \
        $ACCOUNT_FLAG \
        $LEDGER_FLAGS \
        --slow \
        -vvv \
        --sender "$ACCOUNT_ADDRESS" \
        $BROADCAST_FLAG
done

if [ "$(echo "${skip:-false}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    validate_text "$dst" "No destination chain. Use --dst <chain of the stuck message>."
    validate_text "$src" "No source chain. Use --src <chain the message came from>."
    validate_text "$nonce" "No nonce. Use --nonce <inbound nonce>."
    echo ""
    echo "=== Skipping inbound nonce $nonce on $dst (from $src) ==="
    FOUNDRY_PROFILE=deploy forge script "$SCRIPT" \
        --sig "skipInbound(string,uint64)" "$src" "$nonce" \
        --rpc-url "$dst" \
        $ACCOUNT_FLAG \
        $LEDGER_FLAGS \
        --slow \
        -vvv \
        --sender "$ACCOUNT_ADDRESS" \
        $BROADCAST_FLAG
else
    echo ""
    echo "Skip not requested. The stuck message should deliver once the 2-DVN config is applied;"
    echo "check with: ./shell/lz-bridge-testnet/message_status.sh --tx <srcTxHash>"
fi
