# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig $INITIALIZE_CALLDATA --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow --broadcast -vvvv