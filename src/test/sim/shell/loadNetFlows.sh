#!/bin/sh
# Script to load netflows from a json file into solidity, using a filter defined in the arguments passed here.

# Create filter from first arg, removing quote escapes
filter=$(echo "$1" | tr -d '\')

# Get query result from jq
netflows=$(jq -c "$filter" $2)

# Initialize empty array
results=()
key=0 # params must be supported by key in ascending order to match the data correctly
for row in $params; do
    key=$(echo $row | jq -r '.key' | )
    epoch=$(echo $row | jq -r '.epoch' | )
    netflow=$(echo $row | jq -r '.netflow' | )
    
    result=($key $epoch $netflow)
    results+=result
done

# ABI encode results to pass back into Solidity
cast abi-encode "result((uint32, uint32, int256)[])" $results