# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig "deploy(address,address)()" $GUARDIAN_ADDRESS $POLICY_ADDRESS -f $RPC_URL --fork-block-number $BLOCK_NUMBER --private-key $PRIVATE_KEY -vvvv