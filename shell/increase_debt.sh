# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/TreasuryCustodianDeploy.sol:TreasuryCustodianDeploy --sig "increaseDebt(address,uint256)()" $1 $2  --rpc-url $RPC_URL --private-key $GUARDIAN_PRIVATE_KEY --slow -vvv \
--broadcast \ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous call