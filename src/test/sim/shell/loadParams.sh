#!/bin/sh
# Script to load params from a json file into solidity, using a filter defined in the arguments passed here.

# Create filter from first arg, removing quote escapes
filter=$(echo "$1" | tr -d '\')

# Get query result from jq
params=$(jq -c "$filter" $2)

# Initialize empty array
results=()
key=0 # params must be supported by key in ascending order to match the data correctly
for row in $params; do
    key=$(echo $row | jq -r '.key')
    maxLiqRatio=$(echo "$(echo $row | jq -r '.maxLiqRatio')/1" | bc)
    reserveFactor=$(echo "$(echo $row | jq -r '.reserveFactor')/1" | bc)
    cushionFactor=$(echo "$(echo $row | jq -r '.cushionFactor')/1" | bc)
    wallSpread=$(echo "$(echo $row | jq -r '.wallSpread')/1" | bc)
    cushionSpread=$(echo "$(echo $row | jq -r '.cushionSpread')/1" | bc)
    
    result=($key $maxLiqRatio $reserveFactor $cushionFactor $wallSpread $cushionSpread)

    # Concatenate array elements into a single string with parentheses for encoding as tuple (struct)
    result="("$(echo ${result[@]} | tr ' ' ', ')")"
    results+=($result)
done

# Concatenate array elements into a single string with square brackets for encoding as an array
results="["$(echo ${results[@]} | tr ' ' ', ')"]"

# ABI encode results to pass back into Solidity
cast abi-encode "result((uint256, uint256, uint256, uint256, uint256, uint256)[])" $results