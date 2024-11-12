# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "deployDependencies()()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ARBISCAN_KEY # $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment