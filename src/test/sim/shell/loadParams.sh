#!/bin/sh
# Script to load params from a json file into solidity, using a filter defined in the arguments passed here.

# Create filter with passed in seed
filter=".[] | if .seed==\"${1}\" then { key: (.key | ltrimstr(\"${1}_\") | tonumber), maxLiqRatio: ((.maxLiqRatio | tonumber) * 10000), reserveFactor: ((.askFactor | tonumber) * 10000), cushionFactor: ((.cushionFactor | tonumber) * 10000), wallSpread: ((.wall | tonumber) * 10000), cushionSpread: ((.cushion | tonumber) * 10000), dynamicRR: (.withDynamicRR == \"Yes\") } else empty end"

# Get query result from provided json file
params=$(jq -c "$filter" $2)

# Initialize empty array
results=()
for row in $params; do
    key=$(echo $row | jq -r '.key')
    maxLiqRatio=$(echo "$(echo $row | jq -r '.maxLiqRatio')/1" | bc)
    reserveFactor=$(echo "$(echo $row | jq -r '.reserveFactor')/1" | bc)
    cushionFactor=$(echo "$(echo $row | jq -r '.cushionFactor')/1" | bc)
    wallSpread=$(echo "$(echo $row | jq -r '.wallSpread')/1" | bc)
    cushionSpread=$(echo "$(echo $row | jq -r '.cushionSpread')/1" | bc)
    dynamicRR=$(echo $row | jq -r '.dynamicRR')
    
    result=($key $maxLiqRatio $reserveFactor $cushionFactor $wallSpread $cushionSpread $dynamicRR)

    # Concatenate array elements into a single string with parentheses for encoding as tuple (struct)
    result="("$(echo ${result[@]} | tr ' ' ', ')")"
    results+=($result)
done

# Concatenate array elements into a single string with square brackets for encoding as an array
results="["$(echo ${results[@]} | tr ' ' ', ')"]"

# ABI encode results to pass back into Solidity
cast abi-encode "result((uint256, uint256, uint256, uint256, uint256, uint256, bool)[])" $results