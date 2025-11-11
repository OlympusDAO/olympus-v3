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
        if [ "$sign_only" = "true" ]; then
            ledger_path="m/44'/60'/${ledger_index}'/0/0"
        else
            signer_flags+=(--ledger --mnemonic-indexes "$ledger_index")
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

# ARGC-BUILD {
# This block was generated by argc (https://github.com/sigoden/argc).
# Modifying it manually is not recommended

_argc_run() {
    if [[ "${1:-}" == "___internal___" ]]; then
        _argc_die "error: unsupported ___internal___ command"
    fi
    if [[ "${OS:-}" == "Windows_NT" ]] && [[ -n "${MSYSTEM:-}" ]]; then
        set -o igncr
    fi
    argc__args=("$(basename "$0" .sh)" "$@")
    argc__positionals=()
    _argc_index=1
    _argc_len="${#argc__args[@]}"
    _argc_tools=()
    _argc_parse
    if [ -n "${argc__fn:-}" ]; then
        $argc__fn "${argc__positionals[@]}"
    fi
}

_argc_usage() {
    cat <<-'EOF'
Olympus emergency shutdown orchestrator

USAGE: shutdown.argc [OPTIONS] [COMPONENT]

ARGS:
  [COMPONENT]  Component to shut down (treasury, minter, cooler-v2, etc.)

OPTIONS:
      --chain <CHAIN>          Chain name or Foundry RPC alias (required)
      --rpc-url <RPC-URL>      RPC URL to use (defaults to value from .env.emergency or the chain alias)
      --account <ACCOUNT>      Cast wallet account name to sign with
      --ledger <LEDGER>        Mnemonic index for Ledger signing
      --sign                   Generate a signature without submitting the transaction
      --submit <SUBMIT>        Hex signature produced via --sign to submit to the multisig
      --broadcast <BROADCAST>  Broadcast the transaction on completion [possible values: true, false]
      --args <ARGS>            Path to a JSON arguments file to forward to the batch script
      --list                   List supported shutdown targets and exit
  -h, --help                   Print help
  -V, --version                Print version
EOF
    exit
}

_argc_version() {
    echo shutdown.argc 0.0.0
    exit
}

_argc_parse() {
    local _argc_key _argc_action
    local _argc_subcmds=""
    while [[ $_argc_index -lt $_argc_len ]]; do
        _argc_item="${argc__args[_argc_index]}"
        _argc_key="${_argc_item%%=*}"
        case "$_argc_key" in
        --help | -help | -h)
            _argc_usage
            ;;
        --version | -version | -V)
            _argc_version
            ;;
        --)
            _argc_dash="${#argc__positionals[@]}"
            argc__positionals+=("${argc__args[@]:$((_argc_index + 1))}")
            _argc_index=$_argc_len
            break
            ;;
        --chain)
            _argc_take_args "--chain <CHAIN>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_chain:-}" ]]; then
                argc_chain="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--chain\` cannot be used multiple times"
            fi
            ;;
        --rpc-url)
            _argc_take_args "--rpc-url <RPC-URL>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_rpc_url:-}" ]]; then
                argc_rpc_url="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--rpc-url\` cannot be used multiple times"
            fi
            ;;
        --account)
            _argc_take_args "--account <ACCOUNT>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_account:-}" ]]; then
                argc_account="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--account\` cannot be used multiple times"
            fi
            ;;
        --ledger)
            _argc_take_args "--ledger <LEDGER>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_ledger:-}" ]]; then
                argc_ledger="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--ledger\` cannot be used multiple times"
            fi
            ;;
        --sign)
            if [[ "$_argc_item" == *=* ]]; then
                _argc_die "error: flag \`--sign\` don't accept any value"
            fi
            _argc_index=$((_argc_index + 1))
            if [[ -n "${argc_sign:-}" ]]; then
                _argc_die "error: the argument \`--sign\` cannot be used multiple times"
            else
                argc_sign=1
            fi
            ;;
        --submit)
            _argc_take_args "--submit <SUBMIT>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_submit:-}" ]]; then
                argc_submit="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--submit\` cannot be used multiple times"
            fi
            ;;
        --broadcast)
            _argc_take_args "--broadcast <BROADCAST>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            _argc_validate_choices '`<BROADCAST>`' "$(printf "%s\n" true false)" "${_argc_take_args_values[@]}"
            if [[ -z "${argc_broadcast:-}" ]]; then
                argc_broadcast="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--broadcast\` cannot be used multiple times"
            fi
            ;;
        --args)
            _argc_take_args "--args <ARGS>" 1 1 "-" ""
            _argc_index=$((_argc_index + _argc_take_args_len + 1))
            if [[ -z "${argc_args:-}" ]]; then
                argc_args="${_argc_take_args_values[0]:-}"
            else
                _argc_die "error: the argument \`--args\` cannot be used multiple times"
            fi
            ;;
        --list)
            if [[ "$_argc_item" == *=* ]]; then
                _argc_die "error: flag \`--list\` don't accept any value"
            fi
            _argc_index=$((_argc_index + 1))
            if [[ -n "${argc_list:-}" ]]; then
                _argc_die "error: the argument \`--list\` cannot be used multiple times"
            else
                argc_list=1
            fi
            ;;
        *)
            if _argc_maybe_flag_option "-" "$_argc_item"; then
                _argc_die "error: unexpected argument \`$_argc_key\` found"
            fi
            argc__positionals+=("$_argc_item")
            _argc_index=$((_argc_index + 1))
            ;;
        esac
    done
    if [[ -n "${_argc_action:-}" ]]; then
        $_argc_action
    else
        argc__fn=main
        if [[ "${argc__positionals[0]:-}" == "help" ]] && [[ "${#argc__positionals[@]}" -eq 1 ]]; then
            _argc_usage
        fi
        _argc_match_positionals 0
        local values_index values_size
        IFS=: read -r values_index values_size <<<"${_argc_match_positionals_values[0]:-}"
        if [[ -n "$values_index" ]]; then
            argc_component="${argc__positionals[values_index]}"
        fi
    fi
}

_argc_take_args() {
    _argc_take_args_values=()
    _argc_take_args_len=0
    local param="$1" min="$2" max="$3" signs="$4" delimiter="$5"
    if [[ "$min" -eq 0 ]] && [[ "$max" -eq 0 ]]; then
        return
    fi
    local _argc_take_index=$((_argc_index + 1)) _argc_take_value
    if [[ "$_argc_item" == *=* ]]; then
        _argc_take_args_values=("${_argc_item##*=}")
    else
        while [[ $_argc_take_index -lt $_argc_len ]]; do
            _argc_take_value="${argc__args[_argc_take_index]}"
            if _argc_maybe_flag_option "$signs" "$_argc_take_value"; then
                if [[ "${#_argc_take_value}" -gt 1 ]]; then
                    break
                fi
            fi
            _argc_take_args_values+=("$_argc_take_value")
            _argc_take_args_len=$((_argc_take_args_len + 1))
            if [[ "$_argc_take_args_len" -ge "$max" ]]; then
                break
            fi
            _argc_take_index=$((_argc_take_index + 1))
        done
    fi
    if [[ "${#_argc_take_args_values[@]}" -lt "$min" ]]; then
        _argc_die "error: incorrect number of values for \`$param\`"
    fi
    if [[ -n "$delimiter" ]] && [[ "${#_argc_take_args_values[@]}" -gt 0 ]]; then
        local item values arr=()
        for item in "${_argc_take_args_values[@]}"; do
            IFS="$delimiter" read -r -a values <<<"$item"
            arr+=("${values[@]}")
        done
        _argc_take_args_values=("${arr[@]}")
    fi
}

_argc_match_positionals() {
    _argc_match_positionals_values=()
    _argc_match_positionals_len=0
    local params=("$@")
    local args_len="${#argc__positionals[@]}"
    if [[ $args_len -eq 0 ]]; then
        return
    fi
    local params_len=$# arg_index=0 param_index=0
    while [[ $param_index -lt $params_len && $arg_index -lt $args_len ]]; do
        local takes=0
        if [[ "${params[param_index]}" -eq 1 ]]; then
            if [[ $param_index -eq 0 ]] &&
                [[ ${_argc_dash:-} -gt 0 ]] &&
                [[ $params_len -eq 2 ]] &&
                [[ "${params[$((param_index + 1))]}" -eq 1 ]] \
                ; then
                takes=${_argc_dash:-}
            else
                local arg_diff=$((args_len - arg_index)) param_diff=$((params_len - param_index))
                if [[ $arg_diff -gt $param_diff ]]; then
                    takes=$((arg_diff - param_diff + 1))
                else
                    takes=1
                fi
            fi
        else
            takes=1
        fi
        _argc_match_positionals_values+=("$arg_index:$takes")
        arg_index=$((arg_index + takes))
        param_index=$((param_index + 1))
    done
    if [[ $arg_index -lt $args_len ]]; then
        _argc_match_positionals_values+=("$arg_index:$((args_len - arg_index))")
    fi
    _argc_match_positionals_len=${#_argc_match_positionals_values[@]}
    if [[ $params_len -gt 0 ]] && [[ $_argc_match_positionals_len -gt $params_len ]]; then
        local index="${_argc_match_positionals_values[params_len]%%:*}"
        _argc_die "error: unexpected argument \`${argc__positionals[index]}\` found"
    fi
}

_argc_validate_choices() {
    local render_name="$1" raw_choices="$2" choices item choice concated_choices=""
    while IFS= read -r line; do
        choices+=("$line")
    done <<<"$raw_choices"
    for choice in "${choices[@]}"; do
        if [[ -z "$concated_choices" ]]; then
            concated_choices="$choice"
        else
            concated_choices="$concated_choices, $choice"
        fi
    done
    for item in "${@:3}"; do
        local pass=0 choice
        for choice in "${choices[@]}"; do
            if [[ "$item" == "$choice" ]]; then
                pass=1
            fi
        done
        if [[ $pass -ne 1 ]]; then
            _argc_die "error: invalid value \`$item\` for $render_name"$'\n'"  [possible values: $concated_choices]"
        fi
    done
}

_argc_maybe_flag_option() {
    local signs="$1" arg="$2"
    if [[ -z "$signs" ]]; then
        return 1
    fi
    local cond=false
    if [[ "$signs" == *"+"* ]]; then
        if [[ "$arg" =~ ^\+[^+].* ]]; then
            cond=true
        fi
    elif [[ "$arg" == -* ]]; then
        if (( ${#arg} < 3 )) || [[ ! "$arg" =~ ^---.* ]]; then
            cond=true
        fi
    fi
    if [[ "$cond" == "false" ]]; then
        return 1
    fi
    local value="${arg%%=*}"
    if [[ "$value" =~ [[:space:]] ]]; then
        return 1
    fi
    return 0
}

_argc_die() {
    if [[ $# -eq 0 ]]; then
        cat
    else
        echo "$*" >&2
    fi
    exit 1
}

_argc_run "$@"

# ARGC-BUILD }

