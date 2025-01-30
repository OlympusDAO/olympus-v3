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

    # Append the flag for the Etherscan API key
    VERIFY_FLAG="$VERIFY_FLAG --etherscan-api-key $2"

    # Append the flag for the verifier URL if provided
    if [ -n "$3" ]; then
        VERIFY_FLAG="$VERIFY_FLAG --verifier-url $3"
        echo "  Verifier URL: $3"
    else
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
