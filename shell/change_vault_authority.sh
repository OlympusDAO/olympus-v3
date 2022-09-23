# change_price.sh - Script to force update the OlympusAuthority Vault address for testing Bophades Range System on Testnet
# Load environment variables
source .env

# User-provided input ($1) is an Ethereum address
echo "Setting OlympusAuthority Vault to $1 on Testnet.";
echo "";

cast send --private-key=$GOV_PRIVATE_KEY --rpc-url=$RPC_URL --from=$GOV_ADDRESS --chain=$CHAIN $AUTHORITY_ADDRESS "pushVault(address,bool)()" $1 1;

echo "Complete.";