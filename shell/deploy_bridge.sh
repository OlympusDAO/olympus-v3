# Load environment variables
source .env

# Step 1: Deploy and setup dependencies + bridge
forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "deploy(address,address)()" $OP_LZ_ENDPOINT $OP_MULTISIG --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ARBISCAN_API_KEY #--etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network

# Use Alt steps for when kernel is already deployed
# Step 1.1: Deploy bridge
#forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "deployBridge(address,address)()" $MAINNET_KERNEL $MAINNET_LZ_ENDPOINT --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY #--etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment

# Step 1.2: Install into kernel
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "installBridge(address,address,address)()" $ARB_GOERLI_KERNEL "0xeac3eC0CC130f4826715187805d1B50e861F2DaC" $ARB_GOERLI_BRIDGE --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network

# Step 2: Setup paths to other bridges. Repeat n times.
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address,uint16)()" $ARB_BRIDGE $MAINNET_BRIDGE $MAINNET_LZ_CHAIN_ID --rpc-url $ARB_RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast

# for goerli
# forge script ./src/scripts/BridgeDeploy.s.sol:BridgeDeploy --sig "setupBridge(address,address, uint16)()" $GOERLI_BRIDGE $ARB_GOERLI_BRIDGE $ARB_GOERLI_LZ_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvvvv \
#--broadcast

# Step 3: If new chain, pass executor and roles to MS