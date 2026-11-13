# shellcheck shell=bash
# Shared helpers of the YieldRepurchaseFacilityV2 Anvil harness: run.sh and callback-auth.sh
# source this file.
#
# The harness drives the deployment scripts and the multisig batches of the repository against
# a local Anvil fork of Ethereum mainnet. Deployments are signed with Anvil dev account #0;
# multisig and timelock calls are sent from the real on-chain owners through Anvil account
# impersonation (--auto-impersonate).

# The variables below are read by the scripts that source this file.
# shellcheck disable=SC2034

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(git -C "$HARNESS_DIR" rev-parse --show-toplevel)"
BACKUP_DIR="$HARNESS_DIR/.backup"
LOG_DIR="$HARNESS_DIR/logs"

ENV_JSON="src/scripts/env.json"
ADDR_JSON="src/proposals/addresses.json"

# Anvil dev account #0. Its key is public and signs only the deployments on the fork.
DEPLOYER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
# 10000 ETH in wei.
FUND_WEI_HEX="0x21E19E0C9BAB2400000"
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
# The block hash history contract of EIP-2935 and the number of slots of its ring buffer.
HISTORY_STORAGE="0x0000F90827F1C53a10cb7A02335B175320002935"
HISTORY_SERVE_WINDOW=8191

# Upstream RPC throttle of the fork and the transaction type of the broadcasts.
ANVIL_CUPS="${ANVIL_CUPS:-250}"
ANVIL_BACKOFF_MS="${ANVIL_BACKOFF_MS:-1000}"
TX_FLAGS="${TX_FLAGS:---legacy}"
# Split into words once, so that an empty value passes no argument to forge or cast.
read -r -a TX_FLAG_ARGS <<< "$TX_FLAGS"

# The gas limit of the transactions the harness sends with cast, below the transaction gas
# limit of mainnet (2^24).
SEND_GAS_LIMIT="${SEND_GAS_LIMIT:-12000000}"

PORT="${PORT:-8545}"
RPC="http://127.0.0.1:${PORT}"
ANVIL_PID=""
LAST_BATCH_LOG=""

log() { printf '\n\033[1;36m[yrf-harness]\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;33m==== %s ====\033[0m\n' "$*"; }
die() {
    printf '\n\033[1;31m[yrf-harness:error]\033[0m %s\n' "$*" >&2
    exit 1
}

# ========== FORK ========== #

load_dotenv() {
    [ -f "$REPO_ROOT/.env" ] || die ".env not found in $REPO_ROOT (needs ALCHEMY_API_KEY)"
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
    [ -n "${ALCHEMY_API_KEY:-}" ] || die "ALCHEMY_API_KEY is empty after sourcing .env"
}

# start_anvil [fork-block]: starts the fork from the repo root, so that the mainnet alias of
# foundry.toml resolves; no subshell, so that ANVIL_PID is the PID of Anvil itself.
start_anvil() {
    mkdir -p "$LOG_DIR"
    if cast block-number --rpc-url "$RPC" > /dev/null 2>&1; then
        die "$RPC already serves an RPC (port $PORT in use)"
    fi
    local block_args=()
    [ -n "${1:-}" ] && block_args=(--fork-block-number "$1")
    log "Starting an Anvil fork of mainnet on $RPC"
    anvil --fork-url mainnet "${block_args[@]}" --port "$PORT" --auto-impersonate \
        --compute-units-per-second "$ANVIL_CUPS" --fork-retry-backoff "$ANVIL_BACKOFF_MS" \
        --timeout 60000 > "$LOG_DIR/anvil.log" 2>&1 &
    ANVIL_PID=$!
    for _ in $(seq 1 90); do
        kill -0 "$ANVIL_PID" 2> /dev/null || {
            tail -n 30 "$LOG_DIR/anvil.log"
            die "Anvil exited during startup"
        }
        if cast block-number --rpc-url "$RPC" > /dev/null 2>&1; then
            log "Anvil ready at block $(cast block-number --rpc-url "$RPC")"
            return 0
        fi
        sleep 1
    done
    die "Anvil did not become ready within 90s"
}

fund() { cast rpc --rpc-url "$RPC" anvil_setBalance "$1" "$FUND_WEI_HEX" > /dev/null; }

# prefill_block_hash_history: writes zero into every slot of the block hash history contract
# on the fork, in one batch request.
#
# The governor simulation of a proposal rolls the block number forward by about 93,600 blocks.
# Forge 1.9.0 then reads every slot of the ring buffer of the contract, one request at a time,
# and a fork that does not hold a slot fetches it from the upstream RPC. A slot written on the
# fork is answered by the fork itself. Nothing the harness runs reads a block hash from the
# contract.
prefill_block_hash_history() {
    local batch response written i
    batch="$(for ((i = 0; i < HISTORY_SERVE_WINDOW; i++)); do
        printf '{"jsonrpc":"2.0","id":%d,"method":"anvil_setStorageAt","params":["%s","0x%x","0x%064x"]}\n' \
            "$i" "$HISTORY_STORAGE" "$i" 0
    done | jq -c -s '.')"
    response="$(curl -s -X POST -H 'Content-Type: application/json' --data-binary @- "$RPC" <<< "$batch")" ||
        die "the batch request to $RPC failed"
    written="$(jq '[.[] | select(.result == true)] | length' <<< "$response" 2> /dev/null)" ||
        die "the fork did not answer the storage batch with a JSON array"
    [ "$written" = "$HISTORY_SERVE_WINDOW" ] ||
        die "the fork wrote $written of $HISTORY_SERVE_WINDOW slots of the block hash history contract"
    log "Wrote $written slots of the block hash history contract on the fork"
}

block_timestamp() { cast block latest --field timestamp --rpc-url "$RPC"; }

# warp <seconds>: advances the fork clock, mines a block and refreshes the price feeds, whose
# answers would otherwise age past the thresholds of the PRICE module.
warp() {
    cast rpc --rpc-url "$RPC" evm_increaseTime "$1" > /dev/null
    cast rpc --rpc-url "$RPC" anvil_mine 0x1 > /dev/null
    log "Warped $1 seconds; the block timestamp is $(block_timestamp)"
    refresh_price_feeds
}

# ========== VALUES ========== #

lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }

# env_value <dot.path.below.current.mainnet>: the value, or empty.
# The path is split on dots, so that keys with dashes (bond-protocol) are read as keys; a
# numeric part is an array index.
env_value() {
    jq -r --arg p "$1" \
        'getpath(["current", "mainnet"] + ($p | split(".") | map(tonumber? // .))) // empty' \
        "$REPO_ROOT/$ENV_JSON"
}

# set_env_value <dot.path.below.current.mainnet> <json-value>: rewrites one key of env.json.
set_env_value() {
    local tmp
    tmp="$(mktemp)"
    jq --indent 4 --arg p "$1" --argjson v "$2" \
        'setpath(["current", "mainnet"] + ($p | split(".") | map(tonumber? // .)); $v)' \
        "$REPO_ROOT/$ENV_JSON" > "$tmp" || {
        rm -f "$tmp"
        die "failed to set $1 in $ENV_JSON"
    }
    mv "$tmp" "$REPO_ROOT/$ENV_JSON"
    log "env.json: $1 = $2"
}

# delete_env_value <dot.path.below.current.mainnet>: removes one key from env.json, which leaves
# the file as it is before a deployment writes that key.
delete_env_value() {
    local tmp
    tmp="$(mktemp)"
    jq --indent 4 --arg p "$1" \
        'delpaths([["current", "mainnet"] + ($p | split(".") | map(tonumber? // .))])' \
        "$REPO_ROOT/$ENV_JSON" > "$tmp" || {
        rm -f "$tmp"
        die "failed to delete $1 from $ENV_JSON"
    }
    mv "$tmp" "$REPO_ROOT/$ENV_JSON"
    log "env.json: $1 deleted"
}

require_addr() {
    case "$1" in
        "$ZERO_ADDRESS" | "" | null) die "expected a non-zero address for $2, got '$1'" ;;
    esac
}

# call <target> <signature> [args...]: the first word of the cast output, without the
# scientific notation that cast appends to integers.
call() {
    local target="$1" signature="$2"
    shift 2
    cast call "$target" "$signature" "$@" --rpc-url "$RPC" | awk '{print $1}'
}

# send_as <from> <target> <signature> [args...]: a transaction from an impersonated account.
# The gas limit is fixed: an estimate is too low for a call that hands a set amount of gas to
# an isolated step or absorbs the failure of a nested call. cast exits with zero for a mined
# transaction that reverted, so the status of the receipt is checked.
send_as() {
    local from="$1" target="$2" signature="$3" status
    shift 3
    fund "$from"
    status="$(cast send "${TX_FLAG_ARGS[@]}" "$target" "$signature" "$@" --rpc-url "$RPC" \
        --from "$from" --unlocked --gas-limit "$SEND_GAS_LIMIT" --json | jq -r '.status')" ||
        die "transaction $signature from $from to $target was not sent"
    [ "$status" = "0x1" ] || die "transaction $signature from $from to $target reverted"
}

# expect <label> <actual> <expected>: case-insensitive comparison, so addresses compare
# regardless of the checksum.
expect() {
    if [ "$(lower "$2")" = "$(lower "$3")" ]; then
        printf '  [ok] %s = %s\n' "$1" "$2"
    else
        die "$1: expected $3, got $2"
    fi
}

# set_registry_addr <name> <addr>: updates the chainId 1 entry of addresses.json.
set_registry_addr() {
    local tmp
    tmp="$(mktemp)"
    jq --indent 4 --arg n "$1" --arg a "$2" '
        if any(.[]; .name == $n and .chainId == 1)
        then map(if .name == $n and .chainId == 1 then .addr = $a else . end)
        else error("no chainId 1 entry for " + $n)
        end
    ' "$REPO_ROOT/$ADDR_JSON" > "$tmp" || {
        rm -f "$tmp"
        die "failed to update $ADDR_JSON for $1"
    }
    mv "$tmp" "$REPO_ROOT/$ADDR_JSON"
    printf '  %s = %s\n' "$1" "$2"
}

# has_role <account> <role>: true or false, read from the ROLES module.
has_role() {
    call "$(env_value olympus.modules.OlympusRoles)" 'hasRole(address,bytes32)(bool)' "$1" \
        "$(cast format-bytes32-string "$2")"
}

# ========== PRICE FEEDS ========== #

# chainlink_feeds: the Chainlink aggregators the live PRICE module reads, one address per line.
# Every asset of the module carries its feeds as an ABI-encoded Component[]; a component of the
# PRICE.CHAINLINK submodule carries one (feed, threshold) pair or two of them.
chainlink_feeds() {
    local price asset raw feeds target params words w
    local chainlink
    chainlink="$(cast format-bytes32-string PRICE.CHAINLINK | cut -c1-42)"
    # The PRICE keycode as bytes5.
    price="$(call "$(env_value olympus.Kernel)" 'getModuleForKeycode(bytes5)(address)' 0x5052494345)"
    for asset in $(cast call "$price" 'getAssets()(address[])' --rpc-url "$RPC" | tr -d '[],'); do
        raw="$(cast call "$price" 'getAssetData(address)' "$asset" --rpc-url "$RPC")"
        # The feeds are the last member of the Asset struct.
        feeds="$(cast abi-decode \
            'f()((bool,bool,bool,uint32,uint16,uint16,uint48,uint256,uint256[],bytes,bytes))' "$raw" |
            sed -E 's/.*, (0x[0-9a-fA-F]*)\)$/\1/')"
        while read -r target _ params; do
            target="${target#(}"
            target="${target%,}"
            params="${params%)}"
            [ "$(lower "$target")" = "$chainlink" ] || continue
            words=$(((${#params} - 2) / 64))
            for ((w = 0; w < words; w += 2)); do
                echo "0x${params:$((2 + w * 64 + 24)):40}"
            done
        done < <(cast abi-decode 'f()((bytes20,bytes4,bytes)[])' "$feeds" |
            grep -oE '\(0x[0-9a-fA-F]{40}, 0x[0-9a-fA-F]{8}, 0x[0-9a-fA-F]*\)' || true)
    done | sort -u
}

# Feeds the harness refreshes although the PRICE module does not read them yet: run.sh lists
# the USDe/USD feed, which the launch registers.
EXTRA_PRICE_FEEDS=()

# refresh_price_feeds [timestamp]: makes every Chainlink-type feed of the live PRICE module, and
# every feed of EXTRA_PRICE_FEEDS, report its last answer as of the timestamp, by default the
# one of the current block. The fork does not receive feed updates, so the answers age past
# the thresholds of the module: with the wall clock for the hourly feeds, and with every warp
# for the daily ones. A timestamp ahead of the block keeps the answers fresh through a
# simulation that moves its own clock forward.
#
# The first call for a feed places the code of MockPriceFeed at its address and carries over
# the answer, the decimals and the round the feed reports at that moment; every call sets the
# update time. The first call has to come before the fork clock moves: some of the feeds
# (RedStone) revert in latestRoundData() once their own data is stale.
refresh_price_feeds() {
    local mock_code feed data answer decimals round now count=0
    mock_code="$(jq -r '.deployedBytecode.object' "$REPO_ROOT/out/MockPriceFeed.sol/MockPriceFeed.json")"
    [ -n "$mock_code" ] && [ "$mock_code" != "null" ] ||
        die "out/MockPriceFeed.sol/MockPriceFeed.json has no deployed bytecode; build the repository first"
    now="${1:-$(block_timestamp)}"
    for feed in $({
        chainlink_feeds
        printf '%s\n' "${EXTRA_PRICE_FEEDS[@]}"
    } | grep . | tr '[:upper:]' '[:lower:]' | sort -u); do
        if [ "$(cast code "$feed" --rpc-url "$RPC")" != "$mock_code" ]; then
            data="$(cast call "$feed" 'latestRoundData()(uint80,int256,uint256,uint256,uint80)' \
                --rpc-url "$RPC")" ||
                die "feed $feed does not answer latestRoundData(), so its answer cannot be carried over"
            round="$(awk 'NR == 1 {print $1}' <<< "$data")"
            answer="$(awk 'NR == 2 {print $1}' <<< "$data")"
            decimals="$(call "$feed" 'decimals()(uint8)')"
            cast rpc --rpc-url "$RPC" anvil_setCode "$feed" "$mock_code" > /dev/null
            send_as "$DEPLOYER_ADDR" "$feed" 'setLatestAnswer(int256)' "$answer"
            send_as "$DEPLOYER_ADDR" "$feed" 'setDecimals(uint8)' "$decimals"
            send_as "$DEPLOYER_ADDR" "$feed" 'setRoundId(uint80)' "$round"
            send_as "$DEPLOYER_ADDR" "$feed" 'setAnsweredInRound(uint80)' "$round"
        fi
        send_as "$DEPLOYER_ADDR" "$feed" 'setTimestamp(uint256)' "$now"
        count=$((count + 1))
    done
    log "Refreshed $count price feeds to the timestamp $now"
}

# ========== BATCHES ========== #

# owner_address <dao|emergency|0x...>: the multisig of env.json, or the address itself.
owner_address() {
    case "$1" in
        dao | emergency) env_value "olympus.multisig.$1" ;;
        *) echo "$1" ;;
    esac
}

# The percentage forge applies to the gas a simulated transaction used to derive the gas limit
# of the broadcast transaction. The default of forge; a step raises it for a call that needs
# more gas than it uses.
BATCH_GAS_ESTIMATE_MULTIPLIER="${BATCH_GAS_ESTIMATE_MULTIPLIER:-130}"

# batch_forge <log> <Contract> <signature> <sender> [forge script args...]: one forge script
# run of a batch entry point with the settings of shell/safeBatchV2.sh in fork mode: the deploy
# profile, no isolation, and the local broadcast path of BatchScriptV2 (USE_ANVIL_FORK).
batch_forge() {
    local batch_log="$1" contract="$2" signature="$3" sender="$4"
    shift 4
    (
        cd "$REPO_ROOT" || exit
        set -o pipefail
        USE_ANVIL_FORK=true FOUNDRY_PROFILE=deploy forge script \
            "./src/scripts/ops/batches/${contract}.sol:${contract}" --sig "$signature" "$@" \
            --rpc-url "$RPC" --sender "$sender" --unlocked --no-isolate --slow \
            --gas-estimate-multiplier "$BATCH_GAS_ESTIMATE_MULTIPLIER" \
            "${TX_FLAG_ARGS[@]}" -vvv 2>&1 | tee "$batch_log"
    )
}

# run_batch <Contract> <function> <dao|emergency|0x...> [args-file] [log-suffix]: sends a batch
# entry point from the impersonated owner. The log goes to logs/batch-<Contract>-<fn><suffix>.log
# and its path to LAST_BATCH_LOG.
run_batch() {
    local contract="$1" fn="$2" owner args="${4:-}" suffix="${5:-}"
    owner="$(owner_address "$3")"
    require_addr "$owner" "the batch owner $3"
    fund "$owner"
    LAST_BATCH_LOG="$LOG_DIR/batch-${contract}-${fn}${suffix}.log"
    step "Batch ${contract}.${fn} (owner $3)"
    batch_forge "$LAST_BATCH_LOG" "$contract" "${fn}(bool,string,string)()" "$owner" \
        true "$args" "" --broadcast ||
        die "batch ${contract}.${fn} failed; see $LAST_BATCH_LOG"
}

# run_batch_expect_fail <Contract> <function> <dao|emergency|0x...> <expected-substring>
#     [args-file] [log-suffix] [useDaoMS]: the run must fail and its log must carry the
# substring. With useDaoMS false the sender itself is the batch owner of an entry point that
# would otherwise take the DAO MS.
run_batch_expect_fail() {
    local contract="$1" fn="$2" owner expected="$4" args="${5:-}" suffix="${6:-}"
    local use_dao_ms="${7:-true}"
    owner="$(owner_address "$3")"
    require_addr "$owner" "the batch owner $3"
    fund "$owner"
    LAST_BATCH_LOG="$LOG_DIR/batch-${contract}-${fn}${suffix}.log"
    step "Batch ${contract}.${fn} (owner $3, expected to fail)"
    if batch_forge "$LAST_BATCH_LOG" "$contract" "${fn}(bool,string,string)()" "$owner" \
        "$use_dao_ms" "$args" "" --broadcast; then
        die "batch ${contract}.${fn} was expected to fail; see $LAST_BATCH_LOG"
    fi
    grep -qF -- "$expected" "$LAST_BATCH_LOG" ||
        die "batch ${contract}.${fn} failed without the expected message '$expected'; see $LAST_BATCH_LOG"
    log "OK: ${contract}.${fn} failed with the expected message"
}

# expect_empty_batch <label>: the last batch must have proposed nothing.
expect_empty_batch() {
    grep -q "No batch targets to execute" "$LAST_BATCH_LOG" ||
        die "$1 was expected to propose nothing; see $LAST_BATCH_LOG"
    log "OK: $1 proposed no action"
}

# expect_non_empty_batch <label>: the last batch must have executed on the fork.
expect_non_empty_batch() {
    grep -q "Batch executed successfully on Anvil fork" "$LAST_BATCH_LOG" ||
        die "$1 was expected to execute actions; see $LAST_BATCH_LOG"
    log "OK: $1 executed on the fork"
}

# expect_log_line <substring> <label>: the last batch log must carry the substring.
expect_log_line() {
    grep -qF -- "$1" "$LAST_BATCH_LOG" || die "$2: '$1' not found in $LAST_BATCH_LOG"
    log "OK: $2"
}

# expect_heartbeat_validated <label>: the last batch must have simulated the heart beats.
expect_heartbeat_validated() {
    expect_log_line "All heart beats validated successfully" "$1 validated the heart beat"
}

# write_args <name> <json>: writes a generated args file where forge may read it
# (fs_permissions) and prints its path. The exit trap of run.sh removes the files.
write_args() {
    local path="deployments/.yrf-harness-$1.json"
    printf '%s\n' "$2" > "$REPO_ROOT/$path"
    echo "$path"
}
