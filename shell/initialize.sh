# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig "initialize()()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \ 
# --broadcast \ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous call