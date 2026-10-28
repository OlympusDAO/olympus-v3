#!/usr/bin/env bash
# =====================================================================
# LZ Bridge Migration: Bridged Supply Calculator
# =====================================================================
#
# Run AFTER migration Step 4 (all old bridges disabled, in-flight
# messages drained) and BEFORE Step 5 (setBridgedSupply).
#
# What this script does:
#   1.  Verifies all old CrossChainBridge contracts are disabled
#   2.  Checks for in-flight LZ V1 messages (nonce comparison + stored payloads)
#   2b. Checks for unretried failedMessages (delta from verified nonces)
#   3.  Cross-checks via LayerZero Scan API (paginated, supplementary)
#   4.  Queries OHM totalSupply, verifies no CCIP BurnMint pools on L2s
#   5.  Reports the initialBridgedSupply value for LZBridgeGatewayBatch
#   6.  Reports the CCIP pool funding amount for CCIPTokenPoolBatch.fundPool
#       and cross-checks the free liquidity of the pool against the Solana
#       OHM mint supply
#
# Bridged supply = totalSupply(OHM_Arb) + totalSupply(OHM_Opt) + totalSupply(OHM_Base) + totalSupply(OHM_Bera)
#
# CCIP pool funding amount = minimumPoolBacking - poolUnclaimableBalance
#   (both under olympus.config.CCIP of mainnet in env.json)
#   - The mainnet lock/release pool releases against burns on the burn/mint
#     chains from its own balance, which also holds the OHM locked for Solana
#     (the Solana mint supply, which a release toward Ethereum withdraws) and
#     an unclaimable part: OHM locked against burns on Solana outside CCIP
#     that no message will ever release (poolUnclaimableBalance). The free
#     liquidity of the pool, its balance minus the Solana mint supply, is the
#     backing it offers the burn/mint chains
#   - minimumPoolBacking is the bridged supply rounded up to a whole OHM; the
#     amount reads neither the pool balance nor the Solana supply, so a
#     transfer in flight cannot understate it, and on a pool whose balance
#     minus the Solana supply is the unclaimable balance the free liquidity
#     after the transfer is the key exactly
#   - fundPool requires that amount in its args file, reads the Solana mint
#     supply itself at build time, proposes nothing when the free liquidity
#     already covers the key, and requires the free liquidity and the raw
#     balance after the transfer at or above the key (the proposal build and
#     the proposal checker compare the raw balance with the key)
#   - The Solana read here is a cross-check: the balance minus the supply is
#     printed next to poolUnclaimableBalance, and a difference is a warning
#     (transfers in flight, a further burn outside CCIP or OHM sent to the
#     pool directly), not an error
#
# Why this is correct:
#   - All OHM on non-canonical chains was minted by the old CrossChainBridge
#     (burn on source, mint on destination via MINTR)
#   - CCIP only bridges Ethereum<>Solana via LockRelease pool on Ethereum;
#     no CCIP BurnMint pool exists for OHM on L2s (verified dynamically)
#   - L2<>L2 transfers are net-neutral (burn on one L2, mint on another),
#     so sum of totalSupply across non-canonical chains == net OHM bridged
#     from Ethereum
#
# Prerequisites: cast (foundry), jq, python3, ALCHEMY_API_KEY in env or .env
#   If using Alchemy, all networks (Ethereum, Arbitrum, Optimism, Base, Berachain)
#   must be enabled in the Alchemy dashboard: https://dashboard.alchemy.com/apps/<app-id>/networks
#   curl serves the LayerZero Scan cross-check and the Solana mint supply cross-check (both
#   skipped with a warning without it); the Solana endpoint is the `solana` alias of foundry.toml
#   (Alchemy, ${ALCHEMY_API_KEY} expanded from the environment or .env) unless SOLANA_RPC_URL
#   overrides it (the public RPC is https://api.mainnet-beta.solana.com); without either the
#   cross-check is skipped with a warning.
#   The script also needs the mainnet minimumPoolBacking and poolUnclaimableBalance keys in
#   env.json and exits without them.
#
# Usage:
#   ./shell/calc_bridged_supply.sh
#
# RPC endpoints are resolved from foundry.toml [rpc_endpoints] aliases by default.
# Override per-chain via env vars:
#   ETH_RPC_URL, ARB_RPC_URL, OPT_RPC_URL, BASE_RPC_URL, BERA_RPC_URL
# =====================================================================

set -euo pipefail

# =====================================================================
# CONFIGURATION
# =====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Chains ---
# Non-canonical chains whose OHM totalSupply contributes to bridged supply
BRIDGE_CHAINS=("arbitrum" "optimism" "base" "berachain")
# All chains with an old CrossChainBridge deployment
ALL_CHAINS=("ethereum" "arbitrum" "optimism" "base" "berachain")

# --- env.json chain key mapping (ethereum -> mainnet, others match) ---
ENV_JSON="src/scripts/env.json"
declare -A ENV_KEY=(
    [ethereum]="mainnet"
    [arbitrum]="arbitrum"
    [optimism]="optimism"
    [base]="base"
    [berachain]="berachain"
)

# --- OHM token addresses (9 decimals) ---
declare -A OHM=(
    [ethereum]="0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5"
    [arbitrum]="0xf0cb2dc0db5e6c66B9a70Ac27B06b878da017028"
    [optimism]="0x060cb087a9730E13aa191f31A6d86bFF8DfcdCC0"
    [base]="0x060cb087a9730E13aa191f31A6d86bFF8DfcdCC0"
    [berachain]="0x18878Df23e2a36f81e820e4b47b4A40576D3159C"
)

# --- Old CrossChainBridge policy addresses (loaded from env.json) ---
declare -A BRIDGE
for _chain in "${ALL_CHAINS[@]}"; do
    BRIDGE[$_chain]=$(jq -r ".current.${ENV_KEY[$_chain]}.olympus.policies.CrossChainBridge // empty" "$ENV_JSON")
    if [[ -z "${BRIDGE[$_chain]}" ]]; then
        printf '%bError: CrossChainBridge address not found in env.json for %s (key: %s)%b\n' "${RED}" "$_chain" "${ENV_KEY[$_chain]}" "${NC}"
        exit 1
    fi
done

# --- LZ V1 Endpoint addresses (loaded from env.json) ---
declare -A ENDPOINT
for _chain in "${ALL_CHAINS[@]}"; do
    ENDPOINT[$_chain]=$(jq -r ".current.${ENV_KEY[$_chain]}.external.layerzero.endpoint // empty" "$ENV_JSON")
    if [[ -z "${ENDPOINT[$_chain]}" ]]; then
        printf '%bError: LZ V1 endpoint not found in env.json for %s (key: %s)%b\n' "${RED}" "$_chain" "${ENV_KEY[$_chain]}" "${NC}"
        exit 1
    fi
done

# --- LZ V1 chain IDs ---
declare -A LZID=(
    [ethereum]=101
    [arbitrum]=110
    [optimism]=111
    [base]=184
    [berachain]=362
)

# --- RPC URLs ---
# Uses foundry.toml [rpc_endpoints] aliases by default (requires ALCHEMY_API_KEY).
# Override per-chain via env vars: ETH_RPC_URL, ARB_RPC_URL, OPT_RPC_URL, BASE_RPC_URL, BERA_RPC_URL.
declare -A RPC=(
    [ethereum]="${ETH_RPC_URL:-mainnet}"
    [arbitrum]="${ARB_RPC_URL:-arbitrum}"
    [optimism]="${OPT_RPC_URL:-optimism}"
    [base]="${BASE_RPC_URL:-base}"
    [berachain]="${BERA_RPC_URL:-berachain}"
)

# --- CCIP LockRelease pool (Ethereum, for Solana bridge) ---
CCIP_LOCK_RELEASE_POOL="0xa5588e518CE5ee0e4628C005E4edAbD5e87de3aD"

# --- Solana OHM mint (loaded from env.json) and RPC, for the free-liquidity cross-check ---
# The endpoint is SOLANA_RPC_URL when set, else the `solana` alias of foundry.toml. forge
# config prints the alias as the raw template, so ${ALCHEMY_API_KEY} is expanded here from
# the environment or from .env.
resolve_solana_rpc_url() {
    if [[ -n "${SOLANA_RPC_URL:-}" ]]; then
        echo "$SOLANA_RPC_URL"
        return
    fi
    local template
    template=$(forge config --json 2>/dev/null \
        | jq -r '.rpc_endpoints.solana | if type == "object" then .endpoint else . end // empty')
    if [[ -z "$template" ]]; then
        return
    fi
    local key="${ALCHEMY_API_KEY:-}"
    if [[ -z "$key" && -f .env ]]; then
        key=$(grep -E '^ALCHEMY_API_KEY=' .env | tail -n1 | cut -d= -f2- | tr -d "\"'")
    fi
    local url="${template//\$\{ALCHEMY_API_KEY\}/$key}"
    if [[ "$url" == *'${'* || "$url" == */v2/ ]]; then
        return
    fi
    echo "$url"
}
# Empty when neither resolves; the cross-check of STEP 5 then warns and is skipped
SOLANA_RPC_URL=$(resolve_solana_rpc_url)
SOLANA_OHM_MINT=$(jq -r '.current.solana.olympus.legacy.OHM // empty' "$ENV_JSON")
if [[ -z "$SOLANA_OHM_MINT" ]]; then
    printf '%bError: Solana OHM mint not found in env.json (key: current.solana.olympus.legacy.OHM)%b\n' "${RED}" "${NC}"
    exit 1
fi

# --- Minimum backing of the CCIP pool (loaded from env.json), which the free liquidity must reach ---
CCIP_MIN_POOL_BACKING=$(jq -r '.current.mainnet.olympus.config.CCIP.minimumPoolBacking // empty' "$ENV_JSON")
if [[ ! "$CCIP_MIN_POOL_BACKING" =~ ^[0-9]+$ ]]; then
    printf '%bError: minimumPoolBacking not found in env.json (key: current.mainnet.olympus.config.CCIP.minimumPoolBacking)%b\n' "${RED}" "${NC}"
    exit 1
fi
# --- Unclaimable balance of the CCIP pool (loaded from env.json; zero is valid), net of the amount ---
CCIP_POOL_UNCLAIMABLE=$(jq -r '.current.mainnet.olympus.config.CCIP.poolUnclaimableBalance // empty' "$ENV_JSON")
if [[ ! "$CCIP_POOL_UNCLAIMABLE" =~ ^[0-9]+$ ]]; then
    printf '%bError: poolUnclaimableBalance not found in env.json (key: current.mainnet.olympus.config.CCIP.poolUnclaimableBalance)%b\n' "${RED}" "${NC}"
    exit 1
fi
CCIP_FUND_ARGS_FILE="src/scripts/ops/batches/args/CCIPTokenPoolBatch_fundPool.json"

# --- One OHM in base units (9 decimals): the rounding unit of minimumPoolBacking ---
OHM_UNIT=1000000000

# --- CCIP TokenAdminRegistry addresses (to check for BurnMint pools) ---
declare -A CCIP_REGISTRY=(
    [arbitrum]="0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E"
    [optimism]="0x657c42abE4CD8aa731Aec322f871B5b90cf6274F"
    [base]="0x6f6C373d09C07425BaAE72317863d7F6bb731e37"
    [berachain]="0x0944C3Fb1dB7D165336569221995B31cBE6c8A55"
)

# --- Verified failedMessages nonces (2026-10-15) ---
# All nonces from 1 to these values have been checked: 0 unretried failures.
# Format: VERIFIED_<dst>_FROM_<src>=<last_verified_nonce>
# Total verified: 9641 nonces across 12 routes (the inbound nonces of the
# destination bridges read on 2026-10-15, with every bridge inactive and no
# message in flight).
declare -A VERIFIED_NONCE=(
    # Ethereum bridge (receiving from):
    [ethereum:arbitrum]=1158
    [ethereum:optimism]=2
    [ethereum:base]=429
    [ethereum:berachain]=1129
    # Arbitrum bridge (receiving from):
    [arbitrum:ethereum]=1511
    [arbitrum:optimism]=2
    [arbitrum:base]=1560
    # Optimism bridge (receiving from):
    [optimism:ethereum]=1
    [optimism:arbitrum]=1
    # Base bridge (receiving from):
    [base:ethereum]=452
    [base:arbitrum]=1653
    # Berachain bridge (receiving from):
    [berachain:ethereum]=1743
)

# --- Counters ---
ERRORS=0
WARNINGS=0

# =====================================================================
# HELPERS
# =====================================================================

section() {
    printf '\n%b============================================================%b\n' "${BOLD}${BLUE}" "${NC}"
    printf '%b  %s%b\n' "${BOLD}${BLUE}" "$1" "${NC}"
    printf '%b============================================================%b\n' "${BOLD}${BLUE}" "${NC}"
}

subsection() { printf '\n%b  --- %s ---%b\n' "${CYAN}" "$1" "${NC}"; }
ok()         { printf '  %b[OK]%b %s\n' "${GREEN}" "${NC}" "$1"; }
info()       { printf '  %b[i]%b %s\n' "${BLUE}" "${NC}" "$1"; }

warn() {
    printf '  %b[!]%b %s\n' "${YELLOW}" "${NC}" "$1"
    WARNINGS=$((WARNINGS + 1))
}

err() {
    printf '  %b[X]%b %s\n' "${RED}" "${NC}" "$1"
    ERRORS=$((ERRORS + 1))
}

# Format raw OHM value (9 decimals) as human-readable string
fmt_ohm() {
    python3 -c "v=int('$1'); print(f'{v/1e9:,.9f}')"
}

# Attempt to fetch the original payload for a failed message via LZ Scan API.
# Paginates through source bridge messages to find one matching the given nonce.
# Returns the payload hex string, or empty on failure.
fetch_failed_payload() {
    local src="$1" dst="$2" nonce="$3"
    local src_eid="${LZID[$src]}"
    local src_bridge="${BRIDGE[$src]}"

    if ! command -v curl &>/dev/null; then
        return
    fi

    local api_url="https://scan.layerzero-api.com/v1/messages/oapp/${src_eid}/${src_bridge}"
    local next_token=""
    for ((page = 0; page < 200; page++)); do
        local url="$api_url"
        [[ -n "$next_token" ]] && url="${api_url}?nextToken=${next_token}"

        local response
        response=$(curl -sf --max-time 15 "$url" 2>/dev/null) || break

        local found
        found=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for m in data.get('data', []):
        pw = m.get('pathway', {})
        if pw.get('nonce') == $nonce:
            p = m.get('source', {}).get('tx', {}).get('payload', '')
            if p:
                print(p)
                sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null)

        if [[ -n "$found" ]]; then
            echo "$found"
            return
        fi

        # Next page
        next_token=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('nextToken') or '')
except:
    print('')
" 2>/dev/null)
        [[ -z "$next_token" ]] && break
    done
}

# Run cast call, return stdout on success or literal "ERROR" on failure
safe_call() {
    local result
    if result=$(cast call "$@" 2>/dev/null); then
        # cast may append annotations like [1.974e16] to large numbers; strip them
        echo "$result" | sed 's/\[.*\]//g' | tr -d '[:space:]'
    else
        echo "ERROR"
    fi
}

# =====================================================================
# STEP 1: Verify all old bridges are disabled (bridgeActive == false)
# =====================================================================
check_bridge_status() {
    section "STEP 1: Bridge Status Check"

    local all_ok=true
    for chain in "${ALL_CHAINS[@]}"; do
        local status
        status=$(safe_call "${BRIDGE[$chain]}" "bridgeActive()(bool)" --rpc-url "${RPC[$chain]}")

        case "$status" in
            false) ok "$chain: bridge disabled" ;;
            true)
                err "$chain: bridge is STILL ACTIVE at ${BRIDGE[$chain]}"
                all_ok=false
                ;;
            *)
                err "$chain: failed to query bridgeActive(). Check RPC connectivity"
                all_ok=false
                ;;
        esac
    done

    if $all_ok; then
        echo ""
        ok "All old CrossChainBridge contracts are disabled"
    else
        echo ""
        err "BLOCKER: Disable all bridges (Step 4) before running this script"
    fi
}

# =====================================================================
# STEP 2: Check for in-flight LZ V1 messages (nonce comparison)
#
# For each active route (src -> dst):
#   outbound_nonce = src_endpoint.getOutboundNonce(lzId_dst, bridge_src)
#   trusted_path   = bridge_dst.trustedRemoteLookup(lzId_src)
#   inbound_nonce  = dst_endpoint.getInboundNonce(lzId_src, trusted_path)
#
# If outbound_nonce > inbound_nonce => in-flight messages exist
# Also checks hasStoredPayload for blocked message queues
# =====================================================================
check_inflight() {
    section "STEP 2: In-Flight LZ V1 Message Check"

    local has_issues=false
    local routes_checked=0

    for src in "${ALL_CHAINS[@]}"; do
        for dst in "${ALL_CHAINS[@]}"; do
            [[ "$src" == "$dst" ]] && continue

            # 1. Query outbound nonce on source endpoint
            local out_nonce
            out_nonce=$(safe_call "${ENDPOINT[$src]}" \
                "getOutboundNonce(uint16,address)(uint64)" \
                "${LZID[$dst]}" "${BRIDGE[$src]}" \
                --rpc-url "${RPC[$src]}")

            # Route never used: skip silently (legitimate for e.g. Berachain<>L2 pairs)
            [[ "$out_nonce" == "0" ]] && continue

            # RPC error: cannot skip, this route may have in-flight messages
            if [[ "$out_nonce" == "ERROR" ]]; then
                err "$src -> $dst: failed to query outbound nonce. Check ${RPC[$src]}"
                has_issues=true
                continue
            fi

            # 2. Get the trusted remote path from destination bridge
            #    trustedRemoteLookup(srcChainId) = abi.encodePacked(srcBridge, dstBridge)
            local path
            path=$(safe_call "${BRIDGE[$dst]}" \
                "trustedRemoteLookup(uint16)(bytes)" \
                "${LZID[$src]}" \
                --rpc-url "${RPC[$dst]}")

            # Path not configured: unusual since outbound nonce > 0 means messages were sent
            if [[ "$path" == "0x" || -z "$path" ]]; then
                warn "$src -> $dst: outbound nonce $out_nonce but no trustedRemote on $dst"
                continue
            fi

            # RPC error: cannot skip, we know messages were sent on this route
            if [[ "$path" == "ERROR" ]]; then
                err "$src -> $dst: failed to query trustedRemoteLookup on $dst. Check ${RPC[$dst]}"
                has_issues=true
                continue
            fi

            routes_checked=$((routes_checked + 1))
            subsection "$src -> $dst"

            # 3. Query inbound nonce on destination endpoint
            local in_nonce
            in_nonce=$(safe_call "${ENDPOINT[$dst]}" \
                "getInboundNonce(uint16,bytes)(uint64)" \
                "${LZID[$src]}" "$path" \
                --rpc-url "${RPC[$dst]}")

            if [[ "$in_nonce" == "ERROR" ]]; then
                err "$src -> $dst: failed to query inbound nonce on $dst. Cannot confirm delivery"
                has_issues=true
                continue
            fi

            info "Outbound nonce ($src): $out_nonce"
            info "Inbound nonce  ($dst): $in_nonce"

            if [[ "$out_nonce" != "$in_nonce" ]]; then
                local diff=$((out_nonce - in_nonce))
                err "$diff in-flight message(s). Wait for delivery before proceeding"
                has_issues=true
            else
                ok "All $out_nonce messages delivered"
            fi

            # 4. Check for stored payload (blocks subsequent messages)
            local stored
            stored=$(safe_call "${ENDPOINT[$dst]}" \
                "hasStoredPayload(uint16,bytes)(bool)" \
                "${LZID[$src]}" "$path" \
                --rpc-url "${RPC[$dst]}")

            case "$stored" in
                false) ok "No stored payloads" ;;
                true)
                    err "Stored payload on $dst from $src. Must retryPayload() or forceResumeReceive()"
                    has_issues=true
                    ;;
                *) warn "Could not check stored payload status" ;;
            esac
        done
    done

    echo ""
    info "Checked $routes_checked active route(s) across ${#ALL_CHAINS[@]} chains"

    # Expect 12 directed routes:
    #   ETH<>ARB, ETH<>OPT, ETH<>BASE, ARB<>OPT, ARB<>BASE (10) + ETH<>BERA (2)
    #   OPT<>BASE has never been used (outbound nonce 0)
    local expected_routes=12
    if [[ $routes_checked -lt $expected_routes ]]; then
        warn "Expected $expected_routes routes but only checked $routes_checked (RPC failure or unconfigured trustedRemote?)"
    fi

    if $has_issues; then
        echo ""
        err "BLOCKER: Resolve in-flight messages / stored payloads before proceeding"
    else
        echo ""
        ok "No in-flight messages or stored payloads found"
    fi

}

# =====================================================================
# STEP 2b: Check CrossChainBridge failedMessages mapping
#
# The old CrossChainBridge stores failed receive messages internally.
# A failed message means OHM was burned on source but NOT minted on
# destination. totalSupply on destination would be lower than actual
# bridged amount. These must be retried via retryMessage() before
# taking the bridged supply snapshot.
#
# Nonces 1..VERIFIED_NONCE have been fully checked (0 failures).
# This step only checks the delta: VERIFIED_NONCE+1 .. current inbound nonce.
# =====================================================================
ZERO_BYTES32="0x0000000000000000000000000000000000000000000000000000000000000000"
FAILED_MESSAGES_FILE="shell/failed_messages.json"

check_failed_messages() {
    section "STEP 2b: Failed Messages Check (delta from verified nonces)"

    local has_failures=false
    local total_checked=0
    local total_skipped=0
    local total_failed=0
    local failed_entries="[]"

    for dst in "${ALL_CHAINS[@]}"; do
        for src in "${ALL_CHAINS[@]}"; do
            [[ "$src" == "$dst" ]] && continue

            # Check outbound nonce to see if route was ever used
            local out_nonce
            out_nonce=$(safe_call "${ENDPOINT[$src]}" \
                "getOutboundNonce(uint16,address)(uint64)" \
                "${LZID[$dst]}" "${BRIDGE[$src]}" \
                --rpc-url "${RPC[$src]}")
            [[ "$out_nonce" == "0" ]] && continue
            if [[ "$out_nonce" == "ERROR" ]]; then
                err "$src -> $dst: failed to query outbound nonce (already flagged in Step 2)"
                has_failures=true
                continue
            fi

            # Get trusted remote path
            local path
            path=$(safe_call "${BRIDGE[$dst]}" \
                "trustedRemoteLookup(uint16)(bytes)" \
                "${LZID[$src]}" \
                --rpc-url "${RPC[$dst]}")
            [[ "$path" == "0x" || -z "$path" ]] && continue
            if [[ "$path" == "ERROR" ]]; then
                err "$src -> $dst: failed to query trustedRemoteLookup on $dst"
                has_failures=true
                continue
            fi

            # Get current inbound nonce
            local in_nonce
            in_nonce=$(safe_call "${ENDPOINT[$dst]}" \
                "getInboundNonce(uint16,bytes)(uint64)" \
                "${LZID[$src]}" "$path" \
                --rpc-url "${RPC[$dst]}")
            [[ "$in_nonce" == "0" ]] && continue
            if [[ "$in_nonce" == "ERROR" ]]; then
                err "$src -> $dst: failed to query inbound nonce on $dst"
                has_failures=true
                continue
            fi

            # Determine start nonce (skip already verified range)
            local verified="${VERIFIED_NONCE[$dst:$src]:-0}"
            local start=$((verified + 1))

            if [[ $start -gt $in_nonce ]]; then
                total_skipped=$((total_skipped + in_nonce))
                continue
            fi

            local delta=$((in_nonce - verified))
            subsection "$src -> $dst ($delta new nonce(s), verified up to $verified)"

            local route_failed=0
            for ((n = start; n <= in_nonce; n++)); do
                local result
                result=$(safe_call "${BRIDGE[$dst]}" \
                    "failedMessages(uint16,bytes,uint64)(bytes32)" \
                    "${LZID[$src]}" "$path" "$n" \
                    --rpc-url "${RPC[$dst]}")

                if [[ "$result" == "ERROR" ]]; then
                    err "$src->$dst nonce $n: failed to query failedMessages, cannot confirm clean"
                    has_failures=true
                elif [[ "$result" != "$ZERO_BYTES32" ]]; then
                    err "UNRETRIED failed message: $src->$dst nonce $n (hash: $result)"
                    route_failed=$((route_failed + 1))
                    has_failures=true

                    # Try to auto-fetch payload from LZ Scan API / on-chain event logs
                    local fetched_payload=""
                    info "  Attempting to fetch payload from LZ Scan API and on-chain logs..."
                    fetched_payload=$(fetch_failed_payload "$src" "$dst" "$n")
                    if [[ -n "$fetched_payload" ]]; then
                        ok "  Payload auto-fetched: ${fetched_payload:0:42}..."
                    else
                        warn "  Could not auto-fetch payload. Fill in manually from LZ Scan or MessageFailed event logs"
                    fi

                    # Append to JSON array for retry script
                    failed_entries=$(echo "$failed_entries" | jq \
                        --arg src "$src" \
                        --arg dst "$dst" \
                        --arg srcChainId "${LZID[$src]}" \
                        --arg trustedRemotePath "$path" \
                        --argjson nonce "$n" \
                        --arg hash "$result" \
                        --arg bridge "${BRIDGE[$dst]}" \
                        --arg rpc "${RPC[$dst]}" \
                        --arg payload "$fetched_payload" \
                        '. += [{src: $src, dst: $dst, srcChainId: ($srcChainId | tonumber), trustedRemotePath: $trustedRemotePath, nonce: $nonce, hash: $hash, bridge: $bridge, rpc: $rpc, payload: $payload}]')
                fi
            done

            total_checked=$((total_checked + delta))
            total_skipped=$((total_skipped + verified))
            total_failed=$((total_failed + route_failed))

            if [[ $route_failed -eq 0 ]]; then
                ok "$delta new nonce(s) clean"
            fi
        done
    done

    echo ""
    info "Previously verified (skipped): $total_skipped nonces"
    info "Newly checked: $total_checked nonces"

    if $has_failures; then
        if [[ "$total_failed" -gt 0 ]]; then
            echo "$failed_entries" | jq '.' > "$FAILED_MESSAGES_FILE"
            local missing_payloads
            missing_payloads=$(echo "$failed_entries" | jq '[.[] | select(.payload == "")] | length')
            info "Wrote $total_failed failed message(s) to $FAILED_MESSAGES_FILE"
            if [[ "$missing_payloads" -gt 0 ]]; then
                warn "$missing_payloads message(s) missing payload. Fill in manually from LZ Scan or MessageFailed event logs"
            else
                ok "All payloads auto-fetched"
            fi
            info "Review $FAILED_MESSAGES_FILE, then run: ./shell/retry_failed_messages.sh --account <name>"
        fi
        err "$total_failed unretried failed message(s). Run retryMessage() before snapshot"
    else
        ok "No unretried failed messages (verified: $((total_skipped + total_checked)) total)"
    fi
}

# =====================================================================
# STEP 3: Check LayerZero Scan API for pending messages (optional)
#
# Uses the LayerZero Scan API to cross-check for any inflight or
# failed messages. This is a supplementary check; on-chain nonce
# comparison in Step 2 is the definitive source of truth.
# =====================================================================
check_lz_scan() {
    section "STEP 3: LayerZero Scan API Check (supplementary)"

    if ! command -v curl &>/dev/null; then
        warn "curl not available. Skipping LayerZero Scan API check"
        return
    fi

    info "Querying LayerZero Scan for pending messages by source address..."
    info "Swagger docs: https://scan.layerzero-api.com/v1/swagger"
    echo ""

    for chain in "${ALL_CHAINS[@]}"; do
        local bridge_addr="${BRIDGE[$chain]}"
        local eid="${LZID[$chain]}"

        # Paginate through all messages via nextToken
        # GET /v1/messages/oapp/{srcEid}/{oappAddress}[?nextToken=...]
        # Response: { "data": [...], "nextToken": "..." | null }
        local base_url="https://scan.layerzero-api.com/v1/messages/oapp/${eid}/${bridge_addr}"
        local total_msgs=0
        local total_pending=0
        local -A pending_statuses=()
        local page=0
        local next_token=""
        local fetch_error=false

        while true; do
            page=$((page + 1))
            local url="$base_url"
            [[ -n "$next_token" ]] && url="${base_url}?nextToken=${next_token}"

            local response
            if ! response=$(curl -sf --max-time 20 "$url" 2>/dev/null); then
                if [[ $page -eq 1 ]]; then
                    warn "$chain: LayerZero Scan API request failed or timed out"
                    fetch_error=true
                else
                    warn "$chain: pagination stopped on page $page ($total_msgs messages fetched so far)"
                    fetch_error=true
                fi
                break
            fi

            # Parse one page: return "page_total:page_pending:status_breakdown:next_token_or_empty"
            local parsed
            parsed=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    messages = data.get('data', []) if isinstance(data, dict) else []
    next_token = data.get('nextToken') or ''
    page_total = len(messages)
    def is_delivered(m):
        dst = m.get('destination', {})
        if dst.get('status') == 'SUCCEEDED':
            return True
        tx = dst.get('tx', {})
        if isinstance(tx, dict) and tx.get('txHash'):
            return True
        return False
    pending = [m for m in messages if isinstance(m, dict) and not is_delivered(m)]
    statuses = {}
    for m in pending:
        s = m.get('destination', {}).get('status') or m.get('source', {}).get('status') or 'UNKNOWN'
        statuses[s] = statuses.get(s, 0) + 1
    breakdown = ','.join(f'{v} {k}' for k, v in statuses.items()) if statuses else ''
    print(f'{page_total}:{len(pending)}:{breakdown}:{next_token}')
except Exception as e:
    print(f'ERROR:{e}::')
" 2>/dev/null || echo "ERROR:python failed::")

            # Parse fields
            local page_total page_pending breakdown token_next
            IFS=':' read -r page_total page_pending breakdown token_next <<< "$parsed"

            if [[ "$page_total" == "ERROR" ]]; then
                warn "$chain: Could not parse LayerZero Scan response (page $page)"
                fetch_error=true
                break
            fi

            total_msgs=$((total_msgs + page_total))
            total_pending=$((total_pending + page_pending))

            # Accumulate status breakdown across pages
            if [[ -n "$breakdown" ]]; then
                IFS=',' read -ra parts <<< "$breakdown"
                for part in "${parts[@]}"; do
                    local count="${part%% *}"
                    local status="${part#* }"
                    pending_statuses[$status]=$(( ${pending_statuses[$status]:-0} + count ))
                done
            fi

            # No more pages: empty nextToken or partial page (< 100 results)
            if [[ -z "$token_next" || "$page_total" -lt 100 ]]; then
                break
            fi
            next_token="$token_next"
        done

        $fetch_error && continue

        if [[ $total_pending -gt 0 ]]; then
            local combined=""
            for s in "${!pending_statuses[@]}"; do
                [[ -n "$combined" ]] && combined+=", "
                combined+="${pending_statuses[$s]} ${s}"
            done
            # API results are supplementary, use warn not err
            warn "$chain: $total_pending/$total_msgs message(s) without SUCCEEDED status: $combined"
            info "  Cross-check with Step 2 nonce results. Verify at: https://layerzeroscan.com/address/${bridge_addr}"
        else
            ok "$chain: $total_msgs messages checked across $page page(s), all SUCCEEDED"
        fi
    done
}

# =====================================================================
# STEP 4: Query OHM totalSupply & calculate bridged supply
# =====================================================================
calculate_supply() {
    section "STEP 4: OHM Total Supply Query"

    declare -A SUPPLY
    local bridged_supply=0

    for chain in "${ALL_CHAINS[@]}"; do
        local raw
        raw=$(safe_call "${OHM[$chain]}" "totalSupply()(uint256)" --rpc-url "${RPC[$chain]}")

        if [[ "$raw" == "ERROR" ]]; then
            err "$chain: failed to query OHM totalSupply at ${OHM[$chain]}"
            continue
        fi

        SUPPLY[$chain]=$raw
        local human
        human=$(fmt_ohm "$raw")

        if [[ "$chain" == "ethereum" ]]; then
            info "$chain:   $human OHM  (canonical, not included)"
        else
            info "$chain:  $human OHM"
        fi
    done

    # --- CCIP check ---
    subsection "CCIP Bridge Verification"

    local ccip_bal
    ccip_bal=$(safe_call "${OHM[ethereum]}" \
        "balanceOf(address)(uint256)" "$CCIP_LOCK_RELEASE_POOL" \
        --rpc-url "${RPC[ethereum]}")

    if [[ "$ccip_bal" != "ERROR" ]]; then
        CCIP_POOL_BALANCE="$ccip_bal"
        info "OHM locked in CCIP LockRelease pool (ETH): $(fmt_ohm "$ccip_bal") OHM"
        info "This is Ethereum-side custody for Solana bridging. Does NOT affect L2 supply"
    else
        warn "Could not query CCIP LockRelease pool balance"
    fi

    # Check CCIP TokenAdminRegistry on each non-canonical chain for a BurnMint pool
    local ccip_ok=true
    for chain in "${BRIDGE_CHAINS[@]}"; do
        local registry="${CCIP_REGISTRY[$chain]:-}"
        [[ -z "$registry" ]] && continue

        local pool
        pool=$(safe_call "$registry" "getPool(address)(address)" "${OHM[$chain]}" --rpc-url "${RPC[$chain]}")

        if [[ "$pool" == "ERROR" ]]; then
            warn "$chain: could not query CCIP TokenAdminRegistry"
            ccip_ok=false
        elif [[ "$pool" != "0x0000000000000000000000000000000000000000" ]]; then
            err "$chain: CCIP BurnMint pool registered for OHM at $pool, totalSupply may be affected"
            ccip_ok=false
        fi
    done

    if $ccip_ok; then
        ok "No CCIP BurnMint pool registered for OHM on non-canonical chains"
    fi

    # --- Sum bridged supply ---
    for chain in "${BRIDGE_CHAINS[@]}"; do
        if [[ -n "${SUPPLY[$chain]:-}" ]]; then
            bridged_supply=$((bridged_supply + SUPPLY[$chain]))
        else
            BRIDGED_SUPPLY_COMPLETE=false
        fi
    done
    BRIDGED_SUPPLY="$bridged_supply"

    # --- Report ---
    section "RESULT: Initial Bridged Supply"

    echo ""
    printf '  %bBreakdown (OHM on non-canonical chains):%b\n' "${BOLD}" "${NC}"
    echo ""

    for chain in "${BRIDGE_CHAINS[@]}"; do
        if [[ -n "${SUPPLY[$chain]:-}" ]]; then
            printf '    %-12s %s OHM  (raw: %s)\n' "$chain:" "$(fmt_ohm "${SUPPLY[$chain]}")" "${SUPPLY[$chain]}"
        fi
    done

    printf '    ------------------------------------------------\n'

    local bridged_human
    bridged_human=$(fmt_ohm "$bridged_supply")

    printf '  %b  TOTAL:        %s OHM%b\n' "${BOLD}${GREEN}" "$bridged_human" "${NC}"
    printf '  %b  Raw (9 dec):  %s%b\n' "${BOLD}${GREEN}" "$bridged_supply" "${NC}"

    echo ""

    # Output the value to set in the args file
    printf '  %b+------------------------------------------------------------------+%b\n' "${BOLD}" "${NC}"
    printf '  %b|  Set in: src/scripts/ops/batches/args/                            |%b\n' "${BOLD}" "${NC}"
    printf '  %b|          LZBridgeGatewayBatch_initBridgedSupply.json              |%b\n' "${BOLD}" "${NC}"
    printf '  %b|                                                                  |%b\n' "${BOLD}" "${NC}"
    printf '  %b|  "initialBridgedSupply": %-40s|%b\n' "${BOLD}" "$bridged_supply" "${NC}"
    printf '  %b+------------------------------------------------------------------+%b\n' "${BOLD}" "${NC}"
}

# =====================================================================
# STEP 5: CCIP pool funding amount & Solana free-liquidity cross-check
#
# The mainnet lock/release pool releases against burns on the burn/mint
# chains from its own balance, which also holds the OHM locked for
# Solana (the Solana mint supply) and an unclaimable part: OHM locked
# against burns on Solana outside CCIP that no message will ever release
# (olympus.config.CCIP.poolUnclaimableBalance of mainnet in env.json).
# The funding amount is olympus.config.CCIP.minimumPoolBacking (the
# bridged supply above rounded up to a whole OHM) minus that unclaimable
# balance; it reads neither the pool balance nor the Solana supply, so a
# transfer in flight cannot understate it. CCIPTokenPoolBatch.fundPool
# requires that amount in its args file, reads the Solana mint supply
# itself at build time, proposes nothing when the free liquidity of the
# pool (its balance minus the Solana supply) covers the key, and requires
# the free liquidity and the raw balance after the transfer at or above
# the key. The Solana read below is a cross-check of the pool against the
# unclaimable balance: a difference warns, it does not fail.
# =====================================================================
BRIDGED_SUPPLY=0
BRIDGED_SUPPLY_COMPLETE=true
CCIP_POOL_BALANCE=""
CCIP_FUNDING_BLOCKED=false

# Read the OHM supply of the Solana mint through getTokenSupply; prints
# "<amount>:<slot>" on success or "ERROR" on any failure, a mint whose
# decimals are not 9 included.
solana_mint_supply() {
    local response
    if ! response=$(curl -sf --max-time 20 "$SOLANA_RPC_URL" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenSupply\",\"params\":[\"$SOLANA_OHM_MINT\"]}" 2>/dev/null); then
        echo "ERROR"
        return
    fi
    echo "$response" | jq -r '
        if (.result.value.decimals == 9) and (.result.value.amount | test("^[0-9]+$"))
        then "\(.result.value.amount):\(.result.context.slot)"
        else "ERROR" end' 2>/dev/null || echo "ERROR"
}

# Cross-check of the pool against the unclaimable balance: before the funding,
# the pool balance minus the Solana mint supply is the unclaimable balance once
# every Ethereum-Solana transfer has settled and no further OHM outside CCIP (a
# burn on Solana, a direct transfer) has entered the pool (after the funding
# that difference is the key, so a funded pool is reported against the key
# instead). Takes the funding amount; warns on every
# difference and on a skipped read, since the amount does not depend on either
# figure and fundPool reads the supply itself at build time. A pool state that
# fundPool refuses sets CCIP_FUNDING_BLOCKED.
check_ccip_free_liquidity() {
    local amount="$1"
    subsection "Cross-check: free liquidity of the pool against poolUnclaimableBalance"

    if ! command -v curl &>/dev/null; then
        warn "curl not available; the Solana cross-check is skipped. CCIPTokenPoolBatch.fundPool reads the Solana mint supply itself at build time and fails the build without it"
        return
    fi
    if [[ -z "$SOLANA_RPC_URL" ]]; then
        warn "No Solana RPC endpoint (set SOLANA_RPC_URL, or keep the solana alias of foundry.toml with ALCHEMY_API_KEY in the environment or .env); the cross-check is skipped. CCIPTokenPoolBatch.fundPool reads the supply through that alias at build time and fails the build without it"
        return
    fi
    if [[ -z "$CCIP_POOL_BALANCE" ]]; then
        warn "The CCIP pool balance could not be read above; the Solana cross-check is skipped"
        return
    fi

    local reading solana_supply solana_slot
    reading=$(solana_mint_supply)
    if [[ "$reading" == "ERROR" ]]; then
        warn "Could not read the supply of the Solana OHM mint $SOLANA_OHM_MINT from $SOLANA_RPC_URL; the cross-check is skipped. CCIPTokenPoolBatch.fundPool reads the supply through the solana alias of foundry.toml at build time and fails the build without it"
        return
    fi
    solana_supply="${reading%%:*}"
    solana_slot="${reading##*:}"
    info "Solana OHM mint:     $SOLANA_OHM_MINT"
    info "Solana mint supply:  $(fmt_ohm "$solana_supply") OHM  (raw: $solana_supply, slot $solana_slot)"

    # All in OHM base units (9 decimals):
    #   free       = pool balance - Solana mint supply (negative when the pool holds less than the supply)
    #   free after = free + amount, which fundPool requires at or above the key
    local free free_after
    free=$((CCIP_POOL_BALANCE - solana_supply))
    free_after=$((free + amount))

    echo ""
    printf '    %-38s %s OHM  (raw: %s)\n' "pool balance:" "$(fmt_ohm "$CCIP_POOL_BALANCE")" "$CCIP_POOL_BALANCE"
    printf '    %-38s %s OHM  (raw: %s)\n' "Solana mint supply:" "$(fmt_ohm "$solana_supply")" "$solana_supply"
    printf '    %-38s %s OHM  (raw: %s)\n' "free liquidity (balance - Solana):" "$(fmt_ohm "$free")" "$free"
    printf '    %-38s %s OHM  (raw: %s)\n' "poolUnclaimableBalance (env.json):" "$(fmt_ohm "$CCIP_POOL_UNCLAIMABLE")" "$CCIP_POOL_UNCLAIMABLE"
    echo ""

    # A funded pool: fundPool proposes nothing, and the difference to the constant is the key
    if [[ "$free" -ge "$CCIP_MIN_POOL_BACKING" ]]; then
        ok "The free liquidity already covers minimumPoolBacking; CCIPTokenPoolBatch.fundPool proposes nothing"
        if [[ "$free" -gt "$CCIP_MIN_POOL_BACKING" ]]; then
            info "The free liquidity exceeds minimumPoolBacking by $(fmt_ohm "$((free - CCIP_MIN_POOL_BACKING))") OHM: an Ethereum-Solana transfer in flight, OHM transferred to the pool directly, a further burn on Solana outside CCIP, or a funding of a pool whose free liquidity was short by less than the amount"
        fi
        return
    fi

    # Not yet funded: the balance minus the supply is the unclaimable balance on a reconciled pool
    if [[ "$free" -eq "$CCIP_POOL_UNCLAIMABLE" ]]; then
        ok "The pool balance minus the Solana mint supply equals poolUnclaimableBalance, consistent with no transfer in flight and no further OHM outside CCIP in the pool"
    elif [[ "$free" -gt "$CCIP_POOL_UNCLAIMABLE" ]]; then
        warn "The pool balance minus the Solana mint supply exceeds poolUnclaimableBalance by $(fmt_ohm "$((free - CCIP_POOL_UNCLAIMABLE))") OHM: Ethereum-Solana transfers in flight (the difference closes when they settle), OHM transferred to the pool directly, or a further burn on Solana outside CCIP (the difference settles as surplus in the pool; update poolUnclaimableBalance once the burn is confirmed)"
    else
        warn "The pool balance minus the Solana mint supply is below poolUnclaimableBalance by $(fmt_ohm "$((CCIP_POOL_UNCLAIMABLE - free))") OHM: a withdrawal by the rebalancer, or an overstated key. Re-derive poolUnclaimableBalance from the pool history and the Solana burns before funding"
    fi

    # The transfer and its post-batch check
    printf '    %-38s %s OHM  (raw: %s)\n' "pool balance after the transfer:" "$(fmt_ohm "$((CCIP_POOL_BALANCE + amount))")" "$((CCIP_POOL_BALANCE + amount))"
    printf '    %-38s %s OHM  (raw: %s)\n' "free liquidity after the transfer:" "$(fmt_ohm "$free_after")" "$free_after"
    if [[ "$free_after" -ge "$CCIP_MIN_POOL_BACKING" ]]; then
        ok "The free liquidity after the transfer covers minimumPoolBacking, which the post-batch check of CCIPTokenPoolBatch.fundPool requires"
    else
        warn "The free liquidity after the transfer is $(fmt_ohm "$((CCIP_MIN_POOL_BACKING - free_after))") OHM below minimumPoolBacking: CCIPTokenPoolBatch.fundPool refuses this pool state"
        CCIP_FUNDING_BLOCKED=true
    fi
}

report_ccip_funding() {
    section "STEP 5: CCIP Pool Funding Amount & Solana Cross-Check"

    # The key is the bridged supply rounded up to a whole OHM
    if $BRIDGED_SUPPLY_COMPLETE; then
        local expected_backing
        expected_backing=$(((BRIDGED_SUPPLY + OHM_UNIT - 1) / OHM_UNIT * OHM_UNIT))
        if [[ "$CCIP_MIN_POOL_BACKING" -eq "$expected_backing" ]]; then
            ok "minimumPoolBacking in env.json ($CCIP_MIN_POOL_BACKING) is the bridged supply rounded up to a whole OHM"
        else
            warn "minimumPoolBacking in env.json is $CCIP_MIN_POOL_BACKING; the bridged supply rounded up to a whole OHM is $expected_backing. Update the key"
        fi
    else
        err "The bridged supply is incomplete (a totalSupply query failed above); minimumPoolBacking cannot be checked against it"
    fi

    # Derivation, all in OHM base units (9 decimals):
    #   amount = key - poolUnclaimableBalance (env.json only; fundPool requires this value)
    if [[ "$CCIP_POOL_UNCLAIMABLE" -ge "$CCIP_MIN_POOL_BACKING" ]]; then
        err "poolUnclaimableBalance ($CCIP_POOL_UNCLAIMABLE) is not below minimumPoolBacking ($CCIP_MIN_POOL_BACKING); CCIPTokenPoolBatch.fundPool rejects the pair"
        return
    fi
    local amount
    amount=$((CCIP_MIN_POOL_BACKING - CCIP_POOL_UNCLAIMABLE))

    section "RESULT: CCIP Pool Funding Amount"

    echo ""
    printf '  %bDerivation (OHM base units, 9 decimals):%b\n' "${BOLD}" "${NC}"
    echo ""
    if $BRIDGED_SUPPLY_COMPLETE; then
        printf '    %-38s %s OHM  (raw: %s)\n' "bridged supply (burn/mint chains):" "$(fmt_ohm "$BRIDGED_SUPPLY")" "$BRIDGED_SUPPLY"
    fi
    printf '    %-38s %s OHM  (raw: %s)\n' "minimumPoolBacking (env.json):" "$(fmt_ohm "$CCIP_MIN_POOL_BACKING")" "$CCIP_MIN_POOL_BACKING"
    printf '    %-38s %s OHM  (raw: %s)\n' "poolUnclaimableBalance (env.json):" "$(fmt_ohm "$CCIP_POOL_UNCLAIMABLE")" "$CCIP_POOL_UNCLAIMABLE"
    printf '    ------------------------------------------------\n'
    printf '  %b  FUNDING AMOUNT (key - unclaimable):  %s OHM%b\n' "${BOLD}${GREEN}" "$(fmt_ohm "$amount")" "${NC}"
    printf '  %b  Raw (9 dec):                         %s%b\n' "${BOLD}${GREEN}" "$amount" "${NC}"
    printf '    ------------------------------------------------\n'
    echo ""
    printf '  %b+------------------------------------------------------------------+%b\n' "${BOLD}" "${NC}"
    printf '  %b|  Set in: %-56s|%b\n' "${BOLD}" "${CCIP_FUND_ARGS_FILE%/*}/" "${NC}"
    printf '  %b|          %-56s|%b\n' "${BOLD}" "${CCIP_FUND_ARGS_FILE##*/}" "${NC}"
    printf '  %b|                                                                  |%b\n' "${BOLD}" "${NC}"
    printf '  %b|  "amount": %-54s|%b\n' "${BOLD}" "\"$amount\"" "${NC}"
    printf '  %b+------------------------------------------------------------------+%b\n' "${BOLD}" "${NC}"
    info "CCIPTokenPoolBatch.fundPool requires exactly this amount in its args file, reads the Solana mint supply itself at build time and proposes nothing when the free liquidity of the pool already covers the key; build it immediately before signing"

    check_ccip_free_liquidity "$amount"
}

# =====================================================================
# MAIN
# =====================================================================

printf '\n%b' "${BOLD}${BLUE}"
printf '+===============================================================+\n'
printf '|     LZ Bridge Migration: Bridged Supply Calculator           |\n'
printf '|     Run after Step 4 (bridges stopped), before Step 5        |\n'
printf '+===============================================================+\n'
printf '%b\n' "${NC}"

# Prerequisites
if ! command -v cast &>/dev/null; then
    printf '%bError: cast (foundry) not found. Install via: curl -L https://foundry.paradigm.xyz | bash%b\n' "${RED}" "${NC}"
    exit 1
fi
if ! command -v jq &>/dev/null; then
    printf '%bError: jq not found. Required for reading env.json.%b\n' "${RED}" "${NC}"
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    printf '%bError: python3 not found. Required for number formatting.%b\n' "${RED}" "${NC}"
    exit 1
fi

check_bridge_status
check_inflight
check_failed_messages
check_lz_scan
calculate_supply
report_ccip_funding

# --- Final verdict ---
section "FINAL STATUS"

echo ""
if [[ $ERRORS -gt 0 ]]; then
    err "$ERRORS error(s) found. Resolve before proceeding with Step 5 or the CCIP pool funding"
    echo ""
    exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
    warn "$WARNINGS warning(s). Review above before proceeding"
    echo ""
fi

if $CCIP_FUNDING_BLOCKED; then
    ok "All checks passed. Ready for Step 5 (LZBridgeGatewayBatch.initBridgedSupply)"
    printf '  %b[!]%b %s\n' "${YELLOW}" "${NC}" "Not ready for the CCIP pool funding: CCIPTokenPoolBatch.fundPool refuses this pool state (see STEP 5)"
else
    ok "All checks passed. Ready for Step 5 (LZBridgeGatewayBatch.initBridgedSupply) and for the CCIP pool funding (CCIPTokenPoolBatch.fundPool)"
fi
echo ""
exit 0
