#!/bin/bash

# Arguments required for this script
# 1. String: File/Contract Name (should be the same)
# 2. String: Batch Name
# 3. Bool: Whether to send to STS or not (if false, just simulates the batch)

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

CONTRACT_NAME=$1
BATCH_NAME=$2
BROADCAST=$3

echo "Contract name: $CONTRACT_NAME"

echo "Batch name: $BATCH_NAME"

echo "Broadcasting: $BROADCAST"

echo "Using RPC at URL: $RPC_URL"

# Execute the batch
forge script ./src/scripts/ops/batches/$CONTRACT_NAME.sol:$CONTRACT_NAME --sig "$BATCH_NAME(bool)()" $BROADCAST --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL
