# force_beat.sh - Script to force beat the Heart contract
# Load environment variables
source .env

# Reset heart and call heart.beat()
echo "Resetting the heart...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $HEART "resetBeat()" > /dev/null;
echo "Complete.";
echo "";

echo "Calling heart.beat()...";
cast send --private-key=$POLICY_PRIVATE_KEY --from=$POLICY_ADDRESS --rpc-url=$RPC_URL --chain=$CHAIN $HEART "beat()" > /dev/null;
echo "Complete.";
echo "";