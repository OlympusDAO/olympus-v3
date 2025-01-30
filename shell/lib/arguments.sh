#!/bin/bash

# Library for parsing and validating arguments

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SCRIPT_DIR/error.sh

# Function to load named arguments
# Pass "$@" as an argument to the function to get all of the named arguments
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

# Function to load from a .env file
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

# Validate whether a file exists
# Argument 1: The file path
# Argument 2: The error message to display if the file does not exist
validate_file() {
    # Check if the file exists
    if [ ! -f "$1" ]; then
        display_error "$2"
        exit 1
    fi
}

# Validate whether a text variable is set
# Argument 1: The variable name
# Argument 2: The error message to display if the variable is not set
validate_text() {
    if [ -z "$1" ]; then
        display_error "$2"
        exit 1
    fi
}

# Validate whether a boolean variable is set
# Argument 1: The variable name
# Argument 2: The error message to display if the variable is not set
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
