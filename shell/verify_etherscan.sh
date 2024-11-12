# Load environment variables
source .env

CONTRACT_ADDRESS=$1
CONTRACT_PATH=$2
CONSTRUCTOR_ARGS=$3

# Check if input variables are set
if [ -z "$CONTRACT_ADDRESS" ]
then
  echo "No target contract specified. Provide the contract address to verify."
  exit 1
fi
if [ -z "$CONTRACT_PATH" ]
then
  echo "No contract path. Provide the contract source (i.e. 'src/policies/Heart.sol:OlympusHeart')."
  exit 1
fi
if [ -z "$CONSTRUCTOR_ARGS" ]
then
  echo "No constructor args specified."
  exit 1
fi

forge verify-contract --watch \
--etherscan-api-key $ETHERSCAN_KEY \
--compiler-version v0.8.15+commit.e14f2714 \
--chain-id $CHAIN --num-of-optimizations 10 \
--constructor-args $CONSTRUCTOR_ARGS \
$CONTRACT_ADDRESS $CONTRACT_PATH
