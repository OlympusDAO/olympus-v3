#!/bin/bash

# Repairs deployed testnet bridges and unblocks stuck messages. The local gateway address is read
# from src/scripts/lz-bridge-testnet/deployments/<chain>.json; the delegate and the stuck-message
# sender are derived on-chain.
#
# Actions:
#   discover  : print the delegate and remote peers (read-only)
#   reapply   : re-apply ULN (DVN) + Executor config for all remotes (fixes wrong DVN addresses)
#   skip      : skip one stuck inbound nonce on the active (destination) chain
#   correct   : decrease the canonical bridgedSupply by a stuck transfer amount
#
# Usage:
#   ./shell/lz-bridge-testnet/fix.sh --action discover --chain base-sepolia
#   ./shell/lz-bridge-testnet/fix.sh --action reapply  --chain base-sepolia --account W --broadcast true
#   ./shell/lz-bridge-testnet/fix.sh --action skip     --chain base-sepolia --src sepolia --nonce 1 --account W --broadcast true
#   ./shell/lz-bridge-testnet/fix.sh --action correct  --chain sepolia      --amount 1000000000 --account W --broadcast true
#
# Requires ALCHEMY_API_KEY in .env.

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
source "$SCRIPT_DIR/../lib/arguments.sh"
source "$SCRIPT_DIR/../lib/forge.sh"

load_named_args "$@"

[ -f "$ROOT_DIR/.env" ] && set -a && source "$ROOT_DIR/.env" && set +a

validate_text "$action" "No action. Use --action <discover|reapply|skip|correct>."
validate_text "$chain" "No chain. Use --chain <sepolia|base-sepolia|arbitrum-sepolia>."

SCRIPT="./src/scripts/lz-bridge-testnet/LZBridgeTestnetFix.s.sol:LZBridgeTestnetFix"

case "$action" in
    discover)
        # Read-only: no account / broadcast.
        FOUNDRY_PROFILE=deploy forge script "$SCRIPT" \
            --sig "discover()" \
            --rpc-url "$chain" -vvv
        exit 0
        ;;
    reapply)
        SIG='reapplyConfig()'
        ARGS=()
        ;;
    skip)
        validate_text "$src" "No source chain. Use --src <sepolia|base-sepolia|arbitrum-sepolia>."
        validate_text "$nonce" "No nonce. Use --nonce <inbound nonce, e.g. 1>."
        SIG='skipInbound(string,uint64)'
        ARGS=("$src" "$nonce")
        ;;
    correct)
        validate_text "$amount" "No amount. Use --amount <ohm with 9 decimals>."
        SIG='correctBridgedSupply(uint256)'
        ARGS=("$amount")
        ;;
    *)
        display_error "Unknown action '$action'. Use discover|reapply|skip|correct."
        exit 1
        ;;
esac

BROADCAST=${broadcast:-false}
set_broadcast_flag "$BROADCAST"
validate_and_set_account "$account" "$ledger"

FOUNDRY_PROFILE=deploy forge script "$SCRIPT" \
    --sig "$SIG" "${ARGS[@]}" \
    --rpc-url "$chain" \
    $ACCOUNT_FLAG \
    $LEDGER_FLAGS \
    --slow \
    -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG
