#!/bin/bash

# Library for accessing deployment addresses

source $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/error.sh

# @description Gets an address from the deployment variables
# The result will be echoed to stdout
#
# @param {string} $1 the chain name
# @param {string} $2 the address key (e.g. "olympus.Kernel")
get_address() {
    local chain=$1
    local key=$2

    # Get the address from the deployment variables
    # Use string literals for chain name to handle hyphens
    local address=$(jq -r ".current.[\"$chain\"].$key // \"0x0000000000000000000000000000000000000000\"" src/scripts/env.json)
    echo "$address"
}

# @description Gets an address from the deployment variables and checks that it is not zero
# The result will be echoed to stdout
#
# @param {string} $1 the chain name
# @param {string} $2 the address key (e.g. "olympus.Kernel")
get_address_not_zero() {
    local chain=$1
    local key=$2

    local address=$(get_address "$chain" "$key")
    if [ "$address" = "0x0000000000000000000000000000000000000000" ]; then
        error "$chain.$key is zero or not set"
    fi
    echo "$address"
}
