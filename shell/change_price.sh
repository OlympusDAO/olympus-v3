# change_price.sh - Script to alter the state of the Bophades Range System on Testnet to mock different scenarios
# Load environment variables
source .env

# User-provided input ($1) is the dollar price of OHM
echo "Setting OHM price to \$$1 on Testnet.";
echo "";

# Convert dollar price of OHM into price feed value (using ETH = $1500)
OHM_ETH_PRICE=$(echo "$1*1000000000000000000/1500" | bc);

# DAI price feed value is fixed using ETH = $1500
DAI_ETH_PRICE=666666666666667

# Timestamp
TIMESTAMP=$(date +%s)

# Set price feed values
echo "Updating the OHM price feed...";
cast send --private-key=$POLICY_PRIVATE_KEY --rpc-url=$RPC_URL --from=$POLICY_ADDRESS --chain=$CHAIN $OHM_ETH_FEED "setLatestAnswer(int256)()" $OHM_ETH_PRICE > /dev/null;
cast send --private-key=$POLICY_PRIVATE_KEY --rpc-url=$RPC_URL --from=$POLICY_ADDRESS --chain=$CHAIN $OHM_ETH_FEED "setTimestamp(uint256)()" $TIMESTAMP > /dev/null;
echo "Complete.";
echo "";

echo "Updating the DAI price feed...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $DAI_ETH_FEED "setLatestAnswer(int256)" $DAI_ETH_PRICE > /dev/null;
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $DAI_ETH_FEED "setTimestamp(uint256)" $TIMESTAMP > /dev/null;
echo "Complete.";
echo "";

# Reset heart and call heart.beat()
echo "Resetting the heart...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $HEART "resetBeat()" > /dev/null;
echo "Complete.";
echo "";

echo "Calling heart.beat()...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $HEART "beat()" > /dev/null;
echo "Complete.";
echo "";

echo "Price update complete and Operator state updated.";