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
#
# Bridged supply = totalSupply(OHM_Arb) + totalSupply(OHM_Opt) + totalSupply(OHM_Base) + totalSupply(OHM_Bera)
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
# Prerequisites: cast (foundry), python3
#
# Usage:
#   ./shell/calc_bridged_supply.sh
#
# Override RPC endpoints via env vars:
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

# --- OHM token addresses (9 decimals) ---
declare -A OHM=(
    [ethereum]="0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5"
    [arbitrum]="0xf0cb2dc0db5e6c66B9a70Ac27B06b878da017028"
    [optimism]="0x060cb087a9730E13aa191f31A6d86bFF8DfcdCC0"
    [base]="0x060cb087a9730E13aa191f31A6d86bFF8DfcdCC0"
    [berachain]="0x18878Df23e2a36f81e820e4b47b4A40576D3159C"
)

# --- Old CrossChainBridge policy addresses ---
declare -A BRIDGE=(
    [ethereum]="0x45e563c39cDdbA8699A90078F42353A57509543a"
    [arbitrum]="0x20B3834091f038Ce04D8686FAC99CA44A0FB285c"
    [optimism]="0x22AE99D07584A2AE1af748De573c83f1B9Cdb4c0"
    [base]="0x6CA1a916e883c7ce2BFBcF59dc70F2c1EF9dac6e"
    [berachain]="0xBA42BE149e5260EbA4B82418A6306f55D532eA47"
)

# --- LZ V1 Endpoint addresses ---
declare -A ENDPOINT=(
    [ethereum]="0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675"
    [arbitrum]="0x3c2269811836af69497E5F486A85D7316753cf62"
    [optimism]="0x3c2269811836af69497E5F486A85D7316753cf62"
    [base]="0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7"
    [berachain]="0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7"
)

# --- LZ V1 chain IDs ---
declare -A LZID=(
    [ethereum]=101
    [arbitrum]=110
    [optimism]=111
    [base]=184
    [berachain]=362
)

# --- RPC URLs (public endpoints as defaults) ---
declare -A RPC=(
    [ethereum]="${ETH_RPC_URL:-https://ethereum-rpc.publicnode.com}"
    [arbitrum]="${ARB_RPC_URL:-https://arbitrum-one-rpc.publicnode.com}"
    [optimism]="${OPT_RPC_URL:-https://optimism-rpc.publicnode.com}"
    [base]="${BASE_RPC_URL:-https://base-rpc.publicnode.com}"
    [berachain]="${BERA_RPC_URL:-https://berachain-rpc.publicnode.com}"
)

# --- CCIP LockRelease pool (Ethereum, for Solana bridge) ---
CCIP_LOCK_RELEASE_POOL="0xa5588e518CE5ee0e4628C005E4edAbD5e87de3aD"

# --- CCIP TokenAdminRegistry addresses (to check for BurnMint pools) ---
declare -A CCIP_REGISTRY=(
    [arbitrum]="0x39AE1032cF4B334a1Ed41cdD0833bdD7c7E7751E"
    [optimism]="0x657c42abE4CD8aa731Aec322f871B5b90cf6274F"
    [base]="0x6f6C373d09C07425BaAE72317863d7F6bb731e37"
    [berachain]="0x0944C3Fb1dB7D165336569221995B31cBE6c8A55"
)

# --- Verified failedMessages nonces (2026-03-24) ---
# All nonces from 1 to these values have been checked: 0 unretried failures.
# Format: VERIFIED_<dst>_FROM_<src>=<last_verified_nonce>
# Total verified: 9416 nonces across 12 routes.
declare -A VERIFIED_NONCE=(
    # Ethereum bridge (receiving from):
    [ethereum:arbitrum]=1154
    [ethereum:optimism]=2
    [ethereum:base]=406
    [ethereum:berachain]=1095
    # Arbitrum bridge (receiving from):
    [arbitrum:ethereum]=1495
    [arbitrum:optimism]=2
    [arbitrum:base]=1505
    # Optimism bridge (receiving from):
    [optimism:ethereum]=1
    [optimism:arbitrum]=1
    # Base bridge (receiving from):
    [base:ethereum]=436
    [base:arbitrum]=1593
    # Berachain bridge (receiving from):
    [berachain:ethereum]=1726
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

check_failed_messages() {
    section "STEP 2b: Failed Messages Check (delta from verified nonces)"

    local has_failures=false
    local total_checked=0
    local total_skipped=0
    local total_failed=0

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
                    warn "$src->$dst nonce $n: failed to query failedMessages, cannot confirm clean"
                elif [[ "$result" != "$ZERO_BYTES32" ]]; then
                    err "UNRETRIED failed message: $src->$dst nonce $n (hash: $result)"
                    route_failed=$((route_failed + 1))
                    has_failures=true
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
        fi
    done

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
    printf '  %b|          LZBridgeGatewayBatch_setBridgedSupply.json               |%b\n' "${BOLD}" "${NC}"
    printf '  %b|                                                                  |%b\n' "${BOLD}" "${NC}"
    printf '  %b|  "initialBridgedSupply": %-40s|%b\n' "${BOLD}" "$bridged_supply" "${NC}"
    printf '  %b+------------------------------------------------------------------+%b\n' "${BOLD}" "${NC}"
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
if ! command -v python3 &>/dev/null; then
    printf '%bError: python3 not found. Required for number formatting.%b\n' "${RED}" "${NC}"
    exit 1
fi

check_bridge_status
check_inflight
check_failed_messages
check_lz_scan
calculate_supply

# --- Final verdict ---
section "FINAL STATUS"

echo ""
if [[ $ERRORS -gt 0 ]]; then
    err "$ERRORS error(s) found. Resolve before proceeding with Step 5"
    echo ""
    exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
    warn "$WARNINGS warning(s). Review above before proceeding"
    echo ""
fi

ok "All checks passed. Ready for Step 5: LZBridgeGatewayBatch.setBridgedSupply()"
echo ""
exit 0
