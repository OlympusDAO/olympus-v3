# change_price.sh - Script to alter the state of the Bophades Range System on Testnet to mock different scenarios
# Load environment variables
source .env

# User-provided input ($1) is the dollar price of OHM
echo "Setting OHM price to \$$1 on Testnet.";
echo "Setting ETH price to \$$2 on Testnet.";
echo "";

# Convert dollar price of OHM into price feed value
OHM_ETH_PRICE=$(echo "$1*1000000000000000000/$2" | bc);

# DAI price feed value is assumed to be $1
DAI_ETH_PRICE=$(echo "1000000000000000000/$2" | bc);

# ETH price is as provided
ETH_USD_PRICE=$(echo "$2*1000000000000000000" | bc);

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

echo "Updating the ETH price feed...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $ETH_USD_FEED "setLatestAnswer(int256)" $ETH_USD_PRICE > /dev/null;
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $ETH_USD_FEED "setTimestamp(uint256)" $TIMESTAMP > /dev/null;
echo "Complete.";
echo "";

echo "Mock Price update complete.";