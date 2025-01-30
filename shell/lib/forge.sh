#!/bin/bash

# Library for forge script commands

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SCRIPT_DIR/error.sh

# Function to set the broadcast flag based on the value of the variable
# The BROADCAST_FLAG variable will be set
# Argument 1: The variable name holding the boolean value
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

# Function to set the verify flag based on the value of the variable
# The VERIFY_FLAG variable will be set
# Argument 1: The verification boolean
# Argument 2: The Etherscan API key
# Argument 3: The verifier URL (optional)
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

# Function to set the resume flag based on the value of the variable
# The RESUME_FLAG variable will be set
# Argument 1: The resume boolean
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
