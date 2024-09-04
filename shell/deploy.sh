# Load environment variables
source .env

DEPLOY_FILE=$1

# Check if DEPLOY_FILE is set
if [ -z "$DEPLOY_FILE" ]
then
  echo "No deploy file specified. Provide the relative path after the command."
  exit 1
fi

# Check if DEPLOY_FILE exists
if [ ! -f "$DEPLOY_FILE" ]
then
  echo "Deploy file ($DEPLOY_FILE) not found. Provide the correct relative path after the command."
  exit 1
fi

# Deploy using script
forge script ./src/scripts/deploy/DeployV2.sol:OlympusDeploy \
--sig "deploy(string,string)()" $CHAIN $DEPLOY_FILE \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
--with-gas-price $GAS_PRICE \
# --broadcast --verify --etherscan-api-key $ETHERSCAN_KEY #\ # uncomment to broadcast to the network
# --resume # uncomment to resume from a previous deployment