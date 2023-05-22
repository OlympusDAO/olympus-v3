#!/bin/bash

# Create filter from first arg, removing quote escapes
filter=$(echo "$1" | tr -d '\')

# Get query result from jq
result=$(jq -c "$filter" $2)

# Pass result into a bash array for easier processing
array=(`echo $result | tr -d '"[]' | tr ',' ' ' `)

# Concatenate array elements into a single string for encoding
result="["$(echo ${array[@]} | tr ' ' ', ')"]"

# ABI encode string array to pass back into Solidity
cast abi-encode "result(string[])" $result