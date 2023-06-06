# Arguments required for this script
# 1. String: File/Contract Name (should be the same)
# 2. String: Batch Function Signature (e.g. "Integrative1(int32)")
# 3. Bool: Whether to send to STS or not (if false, just simulates the batch)

# TODO how do we allow providing arbitrary arguments to the batch function?

# Load environment variables
source .env

# Execute the batch
forge script --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL ./src/scripts/ops/batches/$1.sol:$1 --sig "$2(bool)()" $3