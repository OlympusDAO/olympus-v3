# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/TestnetSim.sol:WeightedPoolDeploy --sig "deploy()()" --rpc-url $RPC_URL --private-key $GOV_PRIVATE_KEY --froms $GOV_ADDRESS --slow -vvv \
--broadcast --verify --etherscan-api-key $ETHERSCAN_KEY \ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment