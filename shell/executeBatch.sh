# Arguments required for this script
# 1. String: File/Contract Name (should be the same)
# 2. String: Batch Function Signature (e.g. "Integrative1(bool,int32)"), should always start with a bool since that determines simulate or send
# 3. Bool: Whether to send to STS or not (if false, just simulates the batch)
# 4+. Additional arguments to pass to the script, needs to be included in the function signature

# Load environment variables
source .env

# Set key variables from inputs
CONTRACT_NAME=$1
shift
BATCH_FUNCTION_SIG=$1
shift

# Execute the batch
forge script --slow -vvv --sender $SIGNER_ADDRESS --rpc-url $RPC_URL ./src/scripts/ops/batches/$CONTRACT_NAME.sol:$CONTRACT_NAME --sig "$BATCH_FUNCTION_SIG" "$@"