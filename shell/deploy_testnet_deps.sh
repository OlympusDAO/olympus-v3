# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:DependencyDeploy --sig "deploy()()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow --broadcast -vv