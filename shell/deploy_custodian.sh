# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/TreasuryCustodianDeploy.sol:TreasuryCustodianDeploy --sig "deploy(address)()" $GUARDIAN_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
--broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment