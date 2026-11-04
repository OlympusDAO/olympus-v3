#!/bin/bash

# Library for forge script commands

source $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/error.sh

# @description Sets the broadcast flag based on the value of the variable
# @param {boolean} $1 The variable holding the boolean value
# @sideEffects Sets the BROADCAST_FLAG global variable
set_broadcast_flag() {
    # If the variable is true (case insensitive)
    local lowercase=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [ "$lowercase" = "true" ]; then
        BROADCAST_FLAG="--broadcast"
        echo "  Broadcast: enabled"
    else
        BROADCAST_FLAG=""
        echo "  Broadcast: disabled"
    fi
}

# Configure source verification before any deployment transactions are sent.
# --verify true defaults to all providers; --verifier selects a targeted retry.
configure_verification() {
    VERIFY_ENABLED=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local provider=${2:-all}
    case "$provider" in
        both) VERIFICATION_PROVIDERS=(etherscan sourcify) ;;
        all) VERIFICATION_PROVIDERS=(etherscan sourcify blockscout) ;;
        etherscan | sourcify | blockscout) VERIFICATION_PROVIDERS=("$provider") ;;
        *)
            display_error "Provide --verifier both, all, etherscan, sourcify, or blockscout."
            return 1
            ;;
    esac

    if [ "$VERIFY_ENABLED" != "true" ]; then
        echo "  Verification: disabled"
        return
    fi
    if [ -z "$BROADCAST_FLAG" ]; then
        display_error "Verification requires --broadcast true. Use --resume true for a saved deployment."
        return 1
    fi
    case "$provider" in
        both | all | etherscan)
            export ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-${ETHERSCAN_KEY:-}}
            if [ -z "$ETHERSCAN_API_KEY" ]; then
                display_error "Set ETHERSCAN_API_KEY (or ETHERSCAN_KEY) for Etherscan verification."
                return 1
            fi
            ;;
    esac
    case "$provider" in
        all | blockscout)
            if [ -z "$BLOCKSCOUT_API_KEY" ]; then
                display_error "Set BLOCKSCOUT_API_KEY for Blockscout verification (https://dev.blockscout.com)."
                return 1
            fi
            ;;
    esac
    VERIFICATION_CHAIN_ID=$(cast chain-id --rpc-url "$3")
    echo "  Verification: ${VERIFICATION_PROVIDERS[*]}"
}

# Format the timestamped artifact kept in Git; latest aliases stay transient.
format_broadcast() {
    local script=${1%%:*}
    local manifest="broadcast/${script##*/}/$2/deploy-latest.json"
    local timestamp
    timestamp=$(jq -er '.timestamp' "$manifest")
    pnpm exec prettier --cache --cache-strategy content --write "${manifest%/*}/run-$timestamp.json" src/scripts/env.json
    pnpm exec prettier --cache --cache-strategy content --check "${manifest%/*}/run-$timestamp.json" src/scripts/env.json
}

# Verify saved receipts after deployment and registry recording have succeeded.
# Attempt every selected provider, then report failure if any provider failed.
verify_deployment() {
    if [ "$VERIFY_ENABLED" != "true" ]; then return; fi
    local provider api_key status=0
    local verifier_args=()
    for provider in "${VERIFICATION_PROVIDERS[@]}"; do
        verifier_args=(--resume --verify --verifier "$provider" --chain "$VERIFICATION_CHAIN_ID")
        api_key=${ETHERSCAN_API_KEY:-}
        if [ "$provider" == "blockscout" ]; then
            verifier_args+=(--verifier-url "https://api.blockscout.com/v2/api?chain_id=$VERIFICATION_CHAIN_ID")
            # Forge uses ETHERSCAN_API_KEY for Etherscan-compatible providers.
            # Scope the Blockscout key to this subprocess; keep credentials out of argv.
            api_key=$BLOCKSCOUT_API_KEY
        fi
        echo ""
        echo "Verifying saved deployment with $provider"
        if ETHERSCAN_API_KEY="$api_key" forge script "$@" "${verifier_args[@]}"; then
            echo "[PASS] $provider verification"
        else
            echo "[FAIL] $provider verification; retry with --resume true --verify true --verifier $provider"
            status=1
        fi
        format_broadcast "$1" "$VERIFICATION_CHAIN_ID" || status=1
    done
    return "$status"
}

# @description Sets the resume flag based on the value of the variable
# @param {boolean} $1 The resume boolean
# @sideEffects Sets the RESUME_FLAG global variable
set_resume_flag() {
    local lowercase=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [ "$lowercase" = "true" ]; then
        RESUME_FLAG="--resume"
        echo "  Resume: enabled"
    else
        RESUME_FLAG=""
        echo "  Resume: disabled"
    fi
}

# @description Gets the wallet address from cast wallet
# @param {string} $1 The cast wallet account
# @sideEffects Sets the ACCOUNT_ADDRESS global variable
set_account_address() {
    echo ""
    echo "  Getting wallet address for account: $1"
    ACCOUNT_ADDRESS=$(cast wallet address --account $1)
    echo "  Wallet address: $ACCOUNT_ADDRESS"
}

# @description Gets the wallet address from cast wallet for a Ledger
# @param {string} $1 The mnemonic index
# @sideEffects Sets the ACCOUNT_ADDRESS global variable
set_account_address_ledger() {
    echo ""
    echo "  Getting wallet address from Ledger with mnemonic index: $1"
    ACCOUNT_ADDRESS=$(cast wallet address --ledger --mnemonic-index $1)
    echo "  Wallet address: $ACCOUNT_ADDRESS"
}

# @description Validates account parameters and sets account flags
# @param {string} $1 The cast wallet account (optional)
# @param {string} $2 The ledger mnemonic index (optional)
# @sideEffects Sets ACCOUNT_FLAG, LEDGER_FLAGS, and ACCOUNT_ADDRESS global variables
validate_and_set_account() {
    local account="$1"
    local ledger="$2"

    # Validate that either account or ledger is specified (but not both)
    if [ -n "$account" ] && [ -n "$ledger" ]; then
        display_error "Cannot specify both --account and --ledger. Choose one."
        exit 1
    elif [ -z "$account" ] && [ -z "$ledger" ]; then
        display_error "Must specify either --account or --ledger."
        exit 1
    fi

    if [ -n "$account" ]; then
        # Using cast wallet account
        set_account_address "$account"
        ACCOUNT_FLAG="--account $account"
        LEDGER_FLAGS=""
        echo "  Using account: $account"
    else
        # Using Ledger
        set_account_address_ledger "$ledger"
        ACCOUNT_FLAG=""
        LEDGER_FLAGS="--ledger --mnemonic-indexes $ledger"
        echo "  Using Ledger with mnemonic index: $ledger"
    fi
}
