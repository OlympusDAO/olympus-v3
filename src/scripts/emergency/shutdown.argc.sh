#!/usr/bin/env bash
# @describe Olympus emergency shutdown orchestrator
# @option --chain Chain name or Foundry RPC alias (required)
# @option --rpc-url RPC URL to use (defaults to value from .env.emergency or the chain alias)
# @option --account Cast wallet account name to sign with
# @option --ledger Mnemonic index for Ledger signing
# @flag --sign Generate a signature without submitting the transaction
# @option --submit Hex signature produced via --sign to submit to the multisig
# @option --broadcast[true|false] Broadcast the transaction on completion
# @option --args Path to a JSON arguments file to forward to the batch script
# @flag --list List supported shutdown targets and exit
# @arg component Component to shut down (treasury, minter, cooler-v2, etc.)

:

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)

die() {
    echo "$*" >&2
    exit 1
}

find_repo_root() {
    local dir="$SCRIPT_DIR"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

REPO_ROOT=$(find_repo_root) || die "Could not locate repository root from $SCRIPT_DIR"

LIB_DIR="$REPO_ROOT/shell/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/error.sh"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        display_error "Required command '$1' not found in PATH."
        exit 1
    fi
}

load_env_defaults() {
    local emergency_env="$REPO_ROOT/.env.emergency"
    if [ -f "$emergency_env" ]; then
        # shellcheck disable=SC2046
        set -a
        # shellcheck source=/dev/null
        source "$emergency_env"
        set +a
    fi
}

declare -A SCRIPT_TARGETS=(
    ["treasury"]="src/scripts/emergency/Treasury.sol:Treasury"
    ["minter"]="src/scripts/emergency/Minter.sol:Minter"
    ["cooler-v2"]="src/scripts/emergency/CoolerV2.sol:CoolerV2"
    ["cooler-v2-periphery"]="src/scripts/emergency/CoolerV2Periphery.sol:CoolerV2Periphery"
    ["emission-manager"]="src/scripts/emergency/EmissionManager.sol:EmissionManager"
    ["convertible-deposits"]="src/scripts/emergency/ConvertibleDeposits.sol:ConvertibleDeposits"
    ["ccip"]="src/scripts/emergency/CCIP.sol:CCIP"
    ["ccip-bridge"]="src/scripts/emergency/CCIPBridge.sol:CCIPBridge"
    ["ccip-token-pool-mainnet"]="src/scripts/emergency/CCIPTokenPoolMainnet.sol:CCIPTokenPoolMainnet"
    ["ccip-token-pool-non-mainnet"]="src/scripts/emergency/CCIPTokenPoolNonMainnet.sol:CCIPTokenPoolNonMainnet"
    ["layerzero-bridge"]="src/scripts/emergency/LayerZeroBridge.sol:LayerZeroBridge"
    ["yield-repurchase-facility"]="src/scripts/emergency/YieldRepurchaseFacility.sol:YieldRepurchaseFacility"
    ["heart"]="src/scripts/emergency/Heart.sol:Heart"
    ["reserve-migrator"]="src/scripts/emergency/ReserveMigrator.sol:ReserveMigrator"
    ["reserve-wrapper"]="src/scripts/emergency/ReserveWrapper.sol:ReserveWrapper"
)

declare -A OWNER_TYPES=(
    ["treasury"]="Emergency multisig"
    ["minter"]="Emergency multisig"
    ["cooler-v2"]="Emergency multisig"
    ["cooler-v2-periphery"]="DAO multisig"
    ["emission-manager"]="Emergency multisig"
    ["convertible-deposits"]="Emergency multisig"
    ["ccip"]="Emergency multisig"
    ["ccip-bridge"]="DAO multisig"
    ["ccip-token-pool-mainnet"]="DAO multisig"
    ["ccip-token-pool-non-mainnet"]="Emergency multisig"
    ["layerzero-bridge"]="DAO multisig"
    ["yield-repurchase-facility"]="DAO multisig"
    ["heart"]="Emergency multisig"
    ["reserve-migrator"]="DAO multisig"
    ["reserve-wrapper"]="DAO multisig"
)

SUPPORTED_CHAINS=(
    arbitrum
    arbitrum-sepolia
    base
    base-sepolia
    berachain
    berachain-bartio
    goerli
    mainnet
    optimism
    sepolia
)

print_supported_overview() {
    echo "Supported chains:"
    for chain in "${SUPPORTED_CHAINS[@]}"; do
        printf "  %s\n" "$chain"
    done
    echo ""
    echo "Supported shutdown targets:"
    for key in "${!SCRIPT_TARGETS[@]}"; do
        printf "  %-30s %s\n" "$key" "${OWNER_TYPES[$key]}"
    done | sort
}

show_component_error() {
    display_error "Unsupported component '$1'. Run with --list to see supported targets."
    exit 1
}

normalise_bool() {
    local value
    value=$(echo "${1:-false}" | tr '[:upper:]' '[:lower:]')
    case "$value" in
        true|false) echo "$value" ;;
        *)
            display_error "Invalid boolean value '$1'. Expected true or false."
            exit 1
            ;;
    esac
}

main() {
    require_command forge
    require_command cast

    load_env_defaults

    if [ -n "${argc_list:-}" ]; then
        print_supported_overview
        exit 0
    fi

    local chain="${argc_chain:-}"
    local rpc_url="${argc_rpc_url:-${RPC_URL:-}}"
    local account="${argc_account:-${ACCOUNT:-}}"
    local ledger_index="${argc_ledger:-${LEDGER_INDEX:-}}"
    local component="${argc_component:-}"
    local sign_only="false"
    local submit_signature="${argc_submit:-0x}"
    local args_file="${argc_args:-}"
    local broadcast
    broadcast=$(normalise_bool "${argc_broadcast:-false}")

    if [ -z "$chain" ]; then
        display_error "Provide --chain (try --list for supported chains)."
        exit 1
    fi

    if [ -z "$component" ]; then
        show_component_error ""
    fi

    if [ -n "${argc_sign:-}" ]; then
        sign_only="true"
    fi

    if [ "$sign_only" = "true" ] && [ "$submit_signature" != "0x" ]; then
        display_error "The --submit flag cannot be used together with --sign."
        exit 1
    fi

    if [ "$broadcast" = "true" ] && [ "$sign_only" = "true" ]; then
        display_error "Cannot broadcast while --sign is enabled. Submit the signature in a separate step."
        exit 1
    fi

    if [ -n "$args_file" ] && [ ! -f "$args_file" ]; then
        display_error "Arguments file '$args_file' does not exist."
        exit 1
    fi

    if [ -n "$account" ] && [ -n "$ledger_index" ]; then
        display_error "Specify either --account or --ledger, not both."
        exit 1
    fi

    if [ -z "$account" ] && [ -z "$ledger_index" ]; then
        display_error "Provide --account or --ledger (or set ACCOUNT/LEDGER_INDEX in .env.emergency)."
        exit 1
    fi

    if [ -z "$rpc_url" ]; then
        rpc_url="$chain"
    fi

    local script_target="${SCRIPT_TARGETS[$component]:-}"
    if [ -z "$script_target" ]; then
        show_component_error "$component"
    fi

    local script_file="${script_target%%:*}"
    local contract_name="${script_target##*:}"

    if [ ! -f "$REPO_ROOT/$script_file" ]; then
        display_error "Batch script '$script_file' has not been implemented yet."
        exit 1
    fi

    local owner_type="${OWNER_TYPES[$component]:-Unknown signer}"

    local account_address=""
    local -a signer_flags=()
    local ledger_path=""

    if [ -n "$account" ]; then
        account_address=$(cast wallet address --account "$account")
        signer_flags+=(--account "$account")
    else
        account_address=$(cast wallet address --ledger --mnemonic-index "$ledger_index")
        signer_flags+=(--ledger --mnemonic-indexes "$ledger_index")
        if [ "$sign_only" = "true" ]; then
            ledger_path="m/44'/60'/${ledger_index}'/0/0"
        fi
    fi

    if [ "$broadcast" = "true" ] && [ -z "$account_address" ]; then
        display_error "Unable to resolve signer address."
        exit 1
    fi

    if [[ "$submit_signature" != 0x* ]]; then
        display_error "Signature must be a hex string prefixed with 0x."
        exit 1
    fi

    local args_value="${args_file:-}"
    local ledger_value="${ledger_path:-}"

    local -a forge_cmd=(forge script "$script_file:$contract_name" --sig "run(bool,string,string,bytes)" "$sign_only" "$args_value" "$ledger_value" "$submit_signature" --rpc-url "$rpc_url" --sender "$account_address" --slow -vvv)

    forge_cmd+=("${signer_flags[@]}")

    if [ "$broadcast" = "true" ]; then
        forge_cmd+=(--broadcast)
    fi

    echo ""
    echo "Shutdown summary"
    echo "----------------"
    echo " Component        : $component"
    echo " Contract target  : $contract_name"
    echo " Owner            : $owner_type"
    echo " Chain            : $chain"
    echo " RPC URL          : $rpc_url"
    echo " Sign only        : $sign_only"
    echo " Broadcast        : $broadcast"
    if [ -n "$args_file" ]; then
        echo " Args file        : $args_file"
    else
        echo " Args file        : (none)"
    fi
    echo " Sender address   : $account_address"
    echo ""

    (
        cd "$REPO_ROOT"
        echo "Executing:"
        printf ' %q' "${forge_cmd[@]}"
        echo ""
        "${forge_cmd[@]}"
    )
}

eval "$(argc --argc-eval "$0" "$@")"

