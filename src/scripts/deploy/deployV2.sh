#!/bin/bash

# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/deploy/DeployV2.sol:OlympusDeploy --sig "deploy(string)()" $CHAIN \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY --froms $DEPLOYER --slow -vvv \
# --broadcast # uncomment to broadcast to the network