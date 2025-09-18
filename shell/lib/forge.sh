#!/bin/bash

# Library for forge script commands

source $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/error.sh

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

# @description Sets the verify flag based on the value of the variable
# @param {boolean} $1 The verification boolean
# @param {string} $2 The Etherscan API key
# @param {string} $3 The verifier URL (optional)
# @sideEffects Sets the VERIFY_FLAG global variable
set_verify_flag() {
    # If the variable is true (case insensitive)
    local lowercase=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [ "$lowercase" = "true" ]; then
        VERIFY_FLAG="--verify"
        echo "  Verification: enabled"
    else
        VERIFY_FLAG=""
        echo "  Verification: disabled"
        return 0
    fi

    # Check if ETHERSCAN_KEY is set
    if [ -z "$2" ]; then
        display_error "No Etherscan API key found. Provide the key in the environment file or disable verification."
        exit 1
    fi

    # Append the flag for the verifier URL if provided
    if [ -n "$3" ]; then
        # Append the API key and verifier URL
        VERIFY_FLAG="$VERIFY_FLAG --verifier custom --verifier-api-key $2 --verifier-url $3"
        echo "  Verifier URL: $3"
    else
        # Append the API key
        VERIFY_FLAG="$VERIFY_FLAG --etherscan-api-key $2"
        echo "  Verifier URL: standard"
    fi
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
