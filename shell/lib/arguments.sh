#!/bin/bash

# Library for parsing and validating arguments

source $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/error.sh

# @description Loads named arguments
# @param {string} $@ The named arguments
# @sideEffects Sets the named arguments as global variables
load_named_args() {
    echo ""
    echo "Loading named arguments"

    while [ $# -gt 0 ]; do
        if [[ $1 == *"--"* ]]; then
            # Strip "--" and assign the value
            local v="${1/--/}"
            echo "  Found argument: $v"
            eval "$v=\"$2\""
        fi

        shift
    done
}

# @description Loads environment variables from a .env file
# @param {string} $1 The .env file name (optional)
# @sideEffects Sets the environment variables as global variables
load_env() {
    # Get the name of the .env file or use the default
    ENV_FILE=${env:-".env"}
    echo ""
    echo "Sourcing environment variables from $ENV_FILE"

    # Load environment file
    set -a # Automatically export all variables
    source $ENV_FILE
    set +a # Disable automatic export
}

# @description Validates whether a file exists
# @param {string} $1 The file path
# @param {string} $2 The error message to display if the file does not exist
validate_file() {
    # Check if the file exists
    if [ ! -f "$1" ]; then
        display_error "$2"
        exit 1
    fi
}

# @description Validates whether a text variable is set
# @param {string} $1 The variable name
# @param {string} $2 The error message to display if the variable is not set
validate_text() {
    if [ -z "$1" ]; then
        display_error "$2"
        exit 1
    fi
}

# @description Validates whether a boolean variable is set
# @param {string} $1 The variable name
# @param {boolean} $2 The error message to display if the variable is not set
validate_boolean() {
    if [ -z "$1" ]; then
        display_error "$2"
        exit 1
    fi

    # Check if the variable is "true" or "false" (case insensitive)
    local lowercase=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [ "$lowercase" != "true" ] && [ "$lowercase" != "false" ]; then
        display_error "$2"
        exit 1
    fi
}
