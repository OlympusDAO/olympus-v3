# Load environment variables
source .env

# Step 1: Deploy
#forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "deployBridge(address,address)()" $ARB_GOERLI_KERNEL $ARB_GOERLI_LZ_ENDPOINT --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ARBISCAN_KEY #--etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment

# Step 2: Install 
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "installBridge(address,address,address)()" $ARB_GOERLI_KERNEL "0xeac3eC0CC130f4826715187805d1B50e861F2DaC" $ARB_GOERLI_BRIDGE --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network

# Step 3: Setup paths to other bridges
# for arb goerli
forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address,uint16)()" $ARB_GOERLI_BRIDGE $GOERLI_BRIDGE $GOERLI_LZ_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast

# for goerli
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address, uint16)()" $GOERLI_BRIDGE $ARB_GOERLI_BRIDGE $ARB_GOERLI_LZ_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast