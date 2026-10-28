#!/bin/bash

# Deploys an L2 installation of the Olympus protocol, including the four CCIP contracts.
# Requires external.ccip.RMN and external.ccip.Router in src/scripts/env.json.
# Also requires olympus.config.CCIPTokenPoolConfig.gracePeriod and timelockDelay.
#
# Usage:
# ./deploy.sh
#   --account <cast wallet> OR --ledger <mnemonic-index>
#   --chain <foundry-rpc-alias>
#   --ohm <true|false>
#   --broadcast <false>
#   --verify <false>
#   --verifier <all|both|etherscan|sourcify|blockscout> (default: all)
#   --resume <false>
#   --env <env-file> (optional; defaults to .env if present)
#
# Environment variables:
# RPC_URL, CHAIN (legacy alternative to --chain)
# Source verification uses Etherscan, Sourcify and Blockscout by default.
# Etherscan requires ETHERSCAN_API_KEY; Blockscout requires BLOCKSCOUT_API_KEY.

# Exit if any error occurs
set -eo pipefail

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/arguments.sh"
load_named_args "$@"

# Load environment variables
if [ -z "$env" ] && [ -f .env ]; then env=.env; fi
load_env

# Set sane defaults
BROADCAST=${broadcast:-false}
VERIFY=${verify:-false}
RESUME=${resume:-false}
CHAIN=${chain:-$CHAIN}
RPC_URL=${chain:-$RPC_URL}

# Validate named arguments
echo ""
echo "Validating arguments"
validate_boolean "$ohm" "No ohm flag specified. Provide true or false after the --ohm flag."
validate_boolean "$BROADCAST" "Provide true or false after --broadcast."
validate_boolean "$VERIFY" "Provide true or false after --verify."
validate_boolean "$RESUME" "Provide true or false after --resume."

# Validate environment variables
echo ""
echo "Validating environment variables"
validate_text "$CHAIN" "Provide --chain <foundry-rpc-alias>, or CHAIN and RPC_URL in the environment."
validate_text "$RPC_URL" "No RPC URL or alias specified."

echo ""
echo "Summary:"
echo "  Chain: $CHAIN"
echo "  Deploying OHM: $ohm"

# Validate and set forge script flags
source "$SCRIPT_DIR/../lib/forge.sh"
set_broadcast_flag "$BROADCAST"
configure_verification "$VERIFY" "${verifier:-all}" "$RPC_URL"
set_resume_flag "$RESUME"
validate_and_set_account "$account" "$ledger"

if [ "$BROADCAST" == "true" ]; then
    # Check the local artifact tooling before submitting deployment transactions.
    command -v jq > /dev/null
    pnpm exec prettier --version > /dev/null
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
fi

# Deploy using script
echo ""
echo "Running forge script"
FORGE_ARGS=(./src/scripts/deploy/L2Deploy.s.sol:L2Deploy
    --sig "deploy(string,bool)(string)" "$CHAIN" "$ohm"
    --rpc-url "$RPC_URL" $ACCOUNT_FLAG $LEDGER_FLAGS --slow -vvv
    --sender "$ACCOUNT_ADDRESS" $BROADCAST_FLAG)
FOUNDRY_PROFILE=deploy forge script "${FORGE_ARGS[@]}" $RESUME_FLAG \
    |
    # The address map is saved in the broadcast for the registry writer; individual
    # deployments are already logged. Flush progress output immediately.
    awk '/^== Return ==$/ || /^addresses: string / {next} {print; fflush()}'

if [ "$BROADCAST" == "true" ]; then
    DEPLOYMENT="broadcast/L2Deploy.s.sol/$CHAIN_ID/deploy-latest.json"
    validate_file "$DEPLOYMENT" "Missing confirmed L2 deployment manifest: $DEPLOYMENT"
    # Solidity records registry keys alongside each deployment. Resume retains these return values.
    # Forge escapes quotation marks in string return values.
    DEPLOYMENTS=$(jq -er '
        .returns.addresses.value | gsub("\\\\\""; "\"") | fromjson
        | to_entries[] | [.key, .value] | @tsv
    ' "$DEPLOYMENT")
    while IFS=$'\t' read -r key address; do
        ./src/scripts/deploy/write_deployment.sh "current.$CHAIN.$key" "$address"
    done <<< "$DEPLOYMENTS"

    format_broadcast "${FORGE_ARGS[0]}" "$CHAIN_ID"
fi

echo ""
echo "Deployment transactions complete"
FOUNDRY_PROFILE=deploy verify_deployment "${FORGE_ARGS[@]}"
