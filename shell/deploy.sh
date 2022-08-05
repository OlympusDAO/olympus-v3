# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig "deploy(address,address)()" $GUARDIAN_ADDRESS $POLICY_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY \ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment