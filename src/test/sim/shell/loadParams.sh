#!/bin/sh

# Create filter from first arg, removing quote escapes
filter=$(echo "$1" | tr -d '\')

# Get query result from jq
params=$(jq -c "$filter" $2)

# Initialize empty array
results=()
key=0 # params must be supported by key in ascending order to match the data correctly
for row in $params; do
    key=$(echo $row | jq -r '.key' | )
    maxLiqRatio=$(echo $row | jq -r '.maxLiqRatio')
    reserveFactor=$(echo $row | jq -r '.askFactor')
    cushionFactor=$(echo $row | jq -r '.cushionFactor')
    wallSpread=$(echo $row | jq -r '.wallSpread')
    cushionSpread=$(echo $row | jq -r '.cushionSpread')
    
    result=($key $maxLiqRatio $askFactor $cushionFactor $wallSpread $cushionSpread)
    results+=result
done

# ABI encode results to pass back into Solidity
cast abi-encode "result((uint32, uint32, uint32, uint32, uint32, uint32)[])" $results