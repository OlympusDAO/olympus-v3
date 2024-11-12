# mint_ohm.sh - Script to mint testnet OHM for testing Bophades Range System on Testnet
# Load environment variables
source .env

# User-provided input ($1) is an Ethereum address and ($2) is the amount of DAI to mint
echo "Minting $2 Testnet OHM to $1 on Testnet.";
echo "";

cast send --private-key=$GOV_PRIVATE_KEY --rpc-url=$RPC_URL --from=$GOV_ADDRESS --chain=$CHAIN $OHM_ADDRESS "mint(address,uint256)()" $1 $2;

echo "Complete.";