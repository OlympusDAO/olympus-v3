# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "deploy(address)()" $GOERLI_LZ_ENDPOINT --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment