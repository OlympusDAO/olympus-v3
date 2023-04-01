# Load environment variables
source .env

forge verify-contract --watch --chain $ARB_GOERLI_CHAIN_ID --verifier-url https://api-goerli.arbiscan.io/api --etherscan-api-key $ARBISCAN_KEY \
    --constructor-args $(cast abi-encode "constructor(address,address)" $ARB_GOERLI_KERNEL $ARB_GOERLI_LZ_ENDPOINT) \
    0xB01432c01A9128e3d1d70583eA873477B2a1f5e1 ./src/policies/CrossChainBridge.sol:CrossChainBridge
