#!/bin/bash

# Usage:
# ./write_deployment.sh <key> <value>
# Updates the env.json file with the key-value pair

# Exit on error
set -e

# Get command-line arguments
KEY=$1
VALUE=$2

# Check if KEY is set
if [ -z "$KEY" ]; then
    echo "No key specified. Provide the key after the command."
    exit 1
fi

# Check if VALUE is set
if [ -z "$VALUE" ]; then
    echo "No value specified. Provide the value after the key."
    exit 1
fi

# Write the key-value pair to the env.json file
echo "Writing key-value pair to env.json"
jq -S --indent 4 --arg contract $KEY --arg address $VALUE 'getpath($contract / ".") = $address' src/scripts/env.json > src/scripts/env.json.tmp
mv src/scripts/env.json.tmp src/scripts/env.json
