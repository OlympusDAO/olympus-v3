#!/usr/bin/env bash
# =====================================================================
# LZ Bridge Migration: Retry Failed Messages
# =====================================================================
#
# Retries failed CrossChainBridge messages from the JSON file generated
# by calc_bridged_supply.sh (shell/failed_messages.json).
#
# Before running:
#   1. Run calc_bridged_supply.sh to detect failed messages
#   2. Fill in the "payload" field for each entry in failed_messages.json
#      (from LayerZero Scan API or MessageFailed event logs)
#   3. Run this script with a cast account
#
# The payload can be found via:
#   - LZ Scan: https://layerzeroscan.com/address/<bridge_address>
#     Look for the failed message by nonce, the payload is in the tx details
#   - Event logs: search for MessageFailed(uint16,bytes,uint64,bytes) events
#     on the destination bridge contract
#
# retryMessage() is permissionless (anyone can call it), but the caller
# needs native token for gas on each destination chain.
#
# Prerequisites: cast (foundry), jq
#
# Usage:
#   ./shell/retry_failed_messages.sh --account <name> [--dry-run]
#
# Options:
#   --account <name>   cast wallet account to sign transactions (required unless --dry-run)
#   --dry-run          Print the retry commands without executing them
# =====================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ZERO_BYTES32="0x0000000000000000000000000000000000000000000000000000000000000000"
FAILED_MESSAGES_FILE="shell/failed_messages.json"
DRY_RUN=false
ACCOUNT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --account)
            ACCOUNT="$2"
            shift 2
            ;;
        *)
            printf '%bUnknown option: %s%b\n' "${RED}" "$1" "${NC}"
            exit 1
            ;;
    esac
done

if ! $DRY_RUN && [[ -z "$ACCOUNT" ]]; then
    printf '%bError: --account <name> is required (or use --dry-run).%b\n' "${RED}" "${NC}"
    printf 'Usage: ./shell/retry_failed_messages.sh --account <name> [--dry-run]\n'
    exit 1
fi

# Prerequisites
if ! command -v cast &> /dev/null; then
    printf '%bError: cast (foundry) not found.%b\n' "${RED}" "${NC}"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    printf '%bError: jq not found.%b\n' "${RED}" "${NC}"
    exit 1
fi
if [[ ! -f "$FAILED_MESSAGES_FILE" ]]; then
    printf '%bError: %s not found. Run calc_bridged_supply.sh first.%b\n' "${RED}" "$FAILED_MESSAGES_FILE" "${NC}"
    exit 1
fi

# Resolve sender address from account
if ! $DRY_RUN; then
    SENDER=$(cast wallet address --account "$ACCOUNT" 2> /dev/null) || {
        printf '%bError: could not resolve address for account "%s". Create with: cast wallet import %s --interactive%b\n' "${RED}" "$ACCOUNT" "$ACCOUNT" "${NC}"
        exit 1
    }
    printf 'Sender: %s (account: %s)\n' "$SENDER" "$ACCOUNT"
fi

# Parse entries
count=$(jq 'length' "$FAILED_MESSAGES_FILE")
if [[ "$count" -eq 0 ]]; then
    printf '%bNo failed messages to retry.%b\n' "${GREEN}" "${NC}"
    exit 0
fi

printf '\n%b=== Retrying %d failed message(s) ===%b\n\n' "${BOLD}${BLUE}" "$count" "${NC}"

if $DRY_RUN; then
    printf '%b[DRY RUN] Commands will be printed but not executed.%b\n\n' "${YELLOW}" "${NC}"
fi

# Pre-flight: check gas balance on each destination chain
if ! $DRY_RUN; then
    declare -A checked_chains
    for ((i = 0; i < count; i++)); do
        rpc=$(jq -r ".[$i].rpc" "$FAILED_MESSAGES_FILE")
        dst=$(jq -r ".[$i].dst" "$FAILED_MESSAGES_FILE")
        [[ -n "${checked_chains[$dst]:-}" ]] && continue
        checked_chains[$dst]=1

        balance=$(cast balance "$SENDER" --rpc-url "$rpc" 2> /dev/null || echo "ERROR")
        if [[ "$balance" == "ERROR" ]]; then
            printf '%b[X] %s: could not query balance on %s%b\n' "${RED}" "$dst" "$rpc" "${NC}"
            exit 1
        elif [[ "$balance" == "0" ]]; then
            printf '%b[X] %s: sender has zero balance. Fund %s with native token for gas.%b\n' "${RED}" "$dst" "$SENDER" "${NC}"
            exit 1
        else
            printf '  %b[OK]%b %s: balance %s\n' "${GREEN}" "${NC}" "$dst" "$balance"
        fi
    done
    echo ""
fi

errors=0
retried=0
skipped=0

for ((i = 0; i < count; i++)); do
    entry=$(jq ".[$i]" "$FAILED_MESSAGES_FILE")

    src=$(echo "$entry" | jq -r '.src')
    dst=$(echo "$entry" | jq -r '.dst')
    srcChainId=$(echo "$entry" | jq -r '.srcChainId')
    path=$(echo "$entry" | jq -r '.trustedRemotePath')
    nonce=$(echo "$entry" | jq -r '.nonce')
    hash=$(echo "$entry" | jq -r '.hash')
    bridge=$(echo "$entry" | jq -r '.bridge')
    rpc=$(echo "$entry" | jq -r '.rpc')
    payload=$(echo "$entry" | jq -r '.payload')

    printf '%b[%d/%d] %s -> %s nonce %s%b\n' "${BOLD}" $((i + 1)) "$count" "$src" "$dst" "$nonce" "${NC}"
    printf '  Bridge:  %s\n' "$bridge"
    printf '  Hash:    %s\n' "$hash"

    # Validate payload is filled in
    if [[ -z "$payload" || "$payload" == "null" ]]; then
        printf '  %b[X] Missing payload. Fill in the "payload" field in %s%b\n' "${RED}" "$FAILED_MESSAGES_FILE" "${NC}"
        errors=$((errors + 1))
        echo ""
        continue
    fi

    printf '  Payload: %s...\n' "${payload:0:42}"

    # Pre-check: verify the failed message still exists on-chain
    if ! $DRY_RUN; then
        current_hash=$(cast call "$bridge" \
            "failedMessages(uint16,bytes,uint64)(bytes32)" \
            "$srcChainId" "$path" "$nonce" \
            --rpc-url "$rpc" 2> /dev/null | tr -d '[:space:]') || current_hash="ERROR"

        if [[ "$current_hash" == "ERROR" ]]; then
            printf '  %b[X] Could not verify on-chain hash. Skipping.%b\n' "${RED}" "${NC}"
            errors=$((errors + 1))
            echo ""
            continue
        elif [[ "$current_hash" == "$ZERO_BYTES32" ]]; then
            printf '  %b[~] Already retried (hash cleared). Skipping.%b\n' "${YELLOW}" "${NC}"
            skipped=$((skipped + 1))
            echo ""
            continue
        elif [[ "$current_hash" != "$hash" ]]; then
            printf '  %b[!] On-chain hash changed (expected %s, got %s). Skipping.%b\n' "${YELLOW}" "$hash" "$current_hash" "${NC}"
            skipped=$((skipped + 1))
            echo ""
            continue
        fi
    fi

    if $DRY_RUN; then
        printf '  %b[DRY RUN] cast send %s retryMessage(uint16,bytes,uint64,bytes) %s %s %s %s --rpc-url %s --account %s%b\n' \
            "${YELLOW}" "$bridge" "$srcChainId" "$path" "$nonce" "$payload" "$rpc" "${ACCOUNT:-<account>}" "${NC}"
        retried=$((retried + 1))
    else
        printf '  Sending tx...\n'
        if cast send "$bridge" \
            "retryMessage(uint16,bytes,uint64,bytes)" \
            "$srcChainId" "$path" "$nonce" "$payload" \
            --rpc-url "$rpc" --account "$ACCOUNT" 2>&1; then

            # Post-check: verify hash was cleared
            post_hash=$(cast call "$bridge" \
                "failedMessages(uint16,bytes,uint64)(bytes32)" \
                "$srcChainId" "$path" "$nonce" \
                --rpc-url "$rpc" 2> /dev/null | tr -d '[:space:]') || post_hash="ERROR"

            if [[ "$post_hash" == "$ZERO_BYTES32" ]]; then
                printf '  %b[OK] Retry successful, hash cleared%b\n' "${GREEN}" "${NC}"
                retried=$((retried + 1))
            elif [[ "$post_hash" == "ERROR" ]]; then
                printf '  %b[!] Tx sent but could not verify hash clearance%b\n' "${YELLOW}" "${NC}"
                retried=$((retried + 1))
            else
                printf '  %b[X] Tx sent but hash NOT cleared (still: %s)%b\n' "${RED}" "$post_hash" "${NC}"
                errors=$((errors + 1))
            fi
        else
            printf '  %b[X] Retry tx failed%b\n' "${RED}" "${NC}"
            errors=$((errors + 1))
        fi
    fi
    echo ""
done

# Summary
printf '%b=== Summary ===%b\n' "${BOLD}${BLUE}" "${NC}"
printf '  Retried: %d/%d\n' "$retried" "$count"
[[ $skipped -gt 0 ]] && printf '  Skipped: %d (already retried)\n' "$skipped"
if [[ $errors -gt 0 ]]; then
    printf '  %bErrors:  %d%b\n' "${RED}" "$errors" "${NC}"
    exit 1
fi
printf '  %bAll messages processed successfully.%b\n' "${GREEN}" "${NC}"
