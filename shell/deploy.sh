#!/bin/bash

# Deploys a sequence of contracts.
#
# Usage:
# ./deploy.sh --sequence <sequence-file> --broadcast <false> --verify <false> --resume <false> --env <env-file>
#
# Environment variables:
# RPC_URL
# PRIVATE_KEY
# GAS_PRICE
# ETHERSCAN_KEY (only needed if verify is true)
# VERIFIER_URL (only needed for a custom verifier or on a fork)

# Exit if any error occurs
set -e

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
  declare $v="$2"
  fi

  shift
done

# Get the name of the .env file or use the default
ENV_FILE=${env:-".env"}
echo "Sourcing environment variables from $ENV_FILE"

# Load environment file
set -a  # Automatically export all variables
source $ENV_FILE
set +a  # Disable automatic export

# Set sane defaults
BROADCAST=${broadcast:-false}
VERIFY=${verify:-false}
RESUME=${resume:-false}

# Check if sequence is set
if [ -z "$sequence" ]
then
  echo "No deployment sequence specified. Provide the relative path after the --sequence flag."
  exit 1
fi

# Check if the sequence file exists
if [ ! -f "$sequence" ]
then
  echo "Deployment sequence ($sequence) not found. Provide the correct relative path after the --sequence flag."
  exit 1
fi

# Check if CHAIN is set
if [ -z "$CHAIN" ]
then
  echo "No chain specified. Specify the CHAIN in the $ENV_FILE file."
  exit 1
fi

echo "Deployment sequence: $sequence"
echo "Chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"

# Set BROADCAST_FLAG based on BROADCAST
BROADCAST_FLAG=""
if [ "$BROADCAST" = "true" ] || [ "$BROADCAST" = "TRUE" ]; then
  BROADCAST_FLAG="--broadcast"
  echo "Broadcasting is enabled"
else
  echo "Broadcasting is disabled"
fi

# Set VERIFY_FLAG based on VERIFY
VERIFY_FLAG=""
if [ "$VERIFY" = "true" ] || [ "$VERIFY" = "TRUE" ]; then

  # Check if ETHERSCAN_KEY is set
  if [ -z "$ETHERSCAN_KEY" ]
  then
    echo "No Etherscan API key found. Provide the key in $ENV_FILE or disable verification."
    exit 1
  fi

  if [ -n "$VERIFIER_URL" ]; then
    echo "Using verifier at URL: $VERIFIER_URL"
    VERIFY_FLAG="--verify --etherscan-api-key $ETHERSCAN_KEY --verifier-url $VERIFIER_URL"
  else
    echo "Using standard verififer"
    VERIFY_FLAG="--verify --etherscan-api-key $ETHERSCAN_KEY"
  fi

  echo "Verification is enabled"
else
  echo "Verification is disabled"
fi

# Set RESUME_FLAG based on RESUME
RESUME_FLAG=""
if [ "$RESUME" = "true" ] || [ "$RESUME" = "TRUE" ]; then
  RESUME_FLAG="--resume"
  echo "Resuming is enabled"
else
  echo "Resuming is disabled"
fi

# Deploy using script
forge script ./src/scripts/deploy/DeployV2.sol:OlympusDeploy \
--sig "deploy(string,string)()" $CHAIN $sequence \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv \
--with-gas-price $GAS_PRICE \
$BROADCAST_FLAG \
$VERIFY_FLAG \
$RESUME_FLAG
