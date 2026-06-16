#!/bin/bash

# Deploys the LayerZero testnet bridge stack on a single chain.
#
# Usage:
# ./shell/lz-bridge/testnet/deploy.sh
#   --chain <sepolia|base-sepolia|arbitrum-sepolia>
#   --account <cast wallet> OR --ledger <mnemonic-index>
#   [--broadcast <false>]
#
# Requires ALCHEMY_API_KEY in .env (used to resolve the foundry rpc alias).

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

validate_text "$chain" "No chain. Use --chain <sepolia|base-sepolia|arbitrum-sepolia>."
BROADCAST=${broadcast:-false}

set_broadcast_flag "$BROADCAST"
validate_and_set_account "$account" "$ledger"

FOUNDRY_PROFILE=deploy forge script \
    ./src/scripts/lz-bridge-testnet/LZBridgeTestnetDeploy.s.sol:LZBridgeTestnetDeploy \
    --sig "deploy()" \
    --rpc-url "$chain" \
    $ACCOUNT_FLAG \
    $LEDGER_FLAGS \
    --slow \
    -vvv \
    --sender "$ACCOUNT_ADDRESS" \
    $BROADCAST_FLAG
