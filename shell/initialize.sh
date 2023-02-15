# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig "initializeOperator()()" --rpc-url $RPC_URL --private-key $GUARDIAN_PRIVATE_KEY --froms $GUARDIAN_ADDRESS --slow -vvv \
--broadcast \ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous call