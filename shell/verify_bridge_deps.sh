# Load environment variables
source .env

forge verify-contract --chain 1 --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $(cast abi-encode "constructor(address,address)" $MAINNET_KERNEL $MAINNET_LZ_ENDPOINT) \
    0x45e563c39cddba8699a90078f42353a57509543a ./src/policies/CrossChainBridge.sol:CrossChainBridge
