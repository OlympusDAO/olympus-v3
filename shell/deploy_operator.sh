# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/OperatorDeploy.sol:OperatorDeploy --sig "deploy()()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
--broadcast --verify --etherscan-api-key $ETHERSCAN_KEY \
# --resume