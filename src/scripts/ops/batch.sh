#!/bin/bash

# Arguments required for this script
# 1. String: File/Contract Name (should be the same)
# 2. String: Batch Name
# 3. Bool: Whether to send to STS or not (if false, just simulates the batch)

# Load environment variables
source .env

# Execute the batch
forge script ./src/scripts/ops/batches/$1.sol:$1 --sig "$2(bool)()" $3 --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL
