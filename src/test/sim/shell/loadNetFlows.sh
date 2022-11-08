#!/bin/sh
# Script to load netflows from a json file into solidity, using a filter defined in the arguments passed here.

# Create filter from passed in seed
# filter=$(echo "$1" | tr -d '\')
filter=".[] | if .seed==\"${1}\" then { key: (.key | ltrimstr(\"${1}_\") | tonumber), day: (.day | tonumber), netflow: (.netflow | tonumber)} else empty end"

# Get query result from provided json file
netflows=$(jq -c "$filter" $2)

# Initialize empty array
results=()
for count in {0..2}; do
    for row in $netflows; do
        key=$(echo $row | jq -r '.key')
        epoch=$(echo "($(echo $row | jq -r '.day')-1) * 3 + $count" | bc)
        netflow=$(echo "$(echo $row | jq -r '.netflow') * 10^18 / 3" | bc)
        
        result=($key $epoch $netflow)
        # Concatenate array elements into a single string with parentheses for encoding as tuple (struct)
        result="("$(echo ${result[@]} | tr ' ' ', ')")"
        results+=($result)
    done
done

# Concatenate array elements into a single string with square brackets for encoding as an array
results="["$(echo ${results[@]} | tr ' ' ', ')"]"

# ABI encode results to pass back into Solidity
cast abi-encode "result((uint32, uint32, int256)[])" $results