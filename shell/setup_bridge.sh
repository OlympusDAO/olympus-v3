# Load environment variables
source .env

# Setup bridge to connect with mainnet
forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address,address)()" $OP_BRIDGE $MAINNET_BRIDGE $MAINNET_LZ_CHAIN_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast \ # uncomment to broadcast to the network