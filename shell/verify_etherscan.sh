#!/bin/bash

# Verifies contracts on Etherscan or custom verifier using metadata from out/ directory.
#
# Usage:
# ./verify_etherscan.sh
#   --address <contract-address>
#   --metadata <metadata-json-file>
#   [--constructor_args <constructor-args>]
#   [--compiler_version <version>]
#   [--optimizer_runs <runs>]
#   [--chain <chain-name-or-url>]
#   [--verify <true/false>]
#   [--env <env-file>]
#
# Examples:
# ./verify_etherscan.sh --address 0x123... --metadata out/Heart.sol/OlympusHeart.0.8.15.json --chain mainnet
# ./verify_etherscan.sh --address 0x123... --metadata out/Kernel.sol/Kernel.0.8.15.json --constructor_args 0x456... --chain http://localhost:8545

# Exit if any error occurs
set -e

# Load named arguments
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source $SCRIPT_DIR/lib/arguments.sh
load_named_args "$@"

# Load environment variables
load_env

# Load forge library functions
source $SCRIPT_DIR/lib/forge.sh

# Set defaults
VERIFY=${verify:-true}
CONSTRUCTOR_ARGS=${constructor_args:-}
COMPILER_VERSION_OVERRIDE=${compiler_version:-}
OPTIMIZER_RUNS_OVERRIDE=${optimizer_runs:-}

# Validate required arguments
echo ""
echo "Validating arguments"
if [ -z "$address" ]; then
    echo "ERROR: No contract address specified. Provide the contract address with --address flag."
    exit 1
fi

if [ -z "$metadata" ]; then
    echo "ERROR: No metadata file specified. Provide the metadata JSON file with --metadata flag (e.g., 'out/Heart.sol/OlympusHeart.0.8.15.json')."
    exit 1
fi

if [ -z "$chain" ]; then
    echo "ERROR: No chain specified. Provide the chain with --chain flag (e.g., 'mainnet', 'sepolia', or a custom RPC URL)."
    exit 1
fi

if [ ! -f "$metadata" ]; then
    echo "ERROR: Metadata file not found: $metadata"
    echo "Make sure the file exists and the contract has been compiled with 'forge build'"
    exit 1
fi

echo "Using metadata file: $metadata"

# Extract contract information from metadata
COMPILATION_TARGET=$(jq -r '.metadata.settings.compilationTarget' "$metadata")
CONTRACT_PATH=$(echo "$COMPILATION_TARGET" | jq -r 'to_entries[0] | "\(.key):\(.value)"')

# Extract compiler information from metadata (for reference/fallback)
# These are extracted from the broadcast files, e.g. broadcast/DeployV3.s.sol/1/deploy-latest.json
METADATA_COMPILER_VERSION=$(jq -r '.metadata.compiler.version' "$metadata")
OPTIMIZER_ENABLED=$(jq -r '.metadata.settings.optimizer.enabled' "$metadata")
METADATA_OPTIMIZER_RUNS=$(jq -r '.metadata.settings.optimizer.runs' "$metadata")

# Use overrides if provided, otherwise use metadata values
if [ -n "$COMPILER_VERSION_OVERRIDE" ]; then
    COMPILER_VERSION="$COMPILER_VERSION_OVERRIDE"
    echo "Using compiler version override: $COMPILER_VERSION"
else
    COMPILER_VERSION="$METADATA_COMPILER_VERSION"
    # Convert compiler version to forge format (add 'v' prefix if missing)
    if [[ ! "$COMPILER_VERSION" =~ ^v ]]; then
        COMPILER_VERSION="v$COMPILER_VERSION"
    fi
fi

if [ -n "$OPTIMIZER_RUNS_OVERRIDE" ]; then
    OPTIMIZER_RUNS="$OPTIMIZER_RUNS_OVERRIDE"
    echo "Using optimizer runs override: $OPTIMIZER_RUNS"
else
    OPTIMIZER_RUNS="$METADATA_OPTIMIZER_RUNS"
fi

# Validate final values (only if we're using metadata values)
if [ -z "$COMPILER_VERSION_OVERRIDE" ] && ([ "$COMPILER_VERSION" = "null" ] || [ -z "$COMPILER_VERSION" ]); then
    echo "ERROR: Could not extract compiler version from metadata and no override provided"
    exit 1
fi

if [ -z "$OPTIMIZER_RUNS_OVERRIDE" ] && ([ "$OPTIMIZER_RUNS" = "null" ] || [ -z "$OPTIMIZER_RUNS" ]); then
    echo "ERROR: Could not extract optimizer runs from metadata and no override provided"
    exit 1
fi

# Validate environment variables for verification
if [ -z "$ETHERSCAN_KEY" ]; then
    echo "ERROR: No Etherscan API key found. Set ETHERSCAN_KEY in environment file."
    exit 1
fi

echo ""
echo "Summary:"
echo "  Contract address: $address"
echo "  Contract path: $CONTRACT_PATH"
echo "  Metadata file: $metadata"
echo "  Chain: $chain"

if [ -n "$COMPILER_VERSION_OVERRIDE" ]; then
    echo "  Compiler version: $COMPILER_VERSION (override)"
else
    echo "  Compiler version: $COMPILER_VERSION (from metadata)"
fi

echo "  Optimizer enabled: $OPTIMIZER_ENABLED"

if [ -n "$OPTIMIZER_RUNS_OVERRIDE" ]; then
    echo "  Optimizer runs: $OPTIMIZER_RUNS (override)"
else
    echo "  Optimizer runs: $OPTIMIZER_RUNS (from metadata)"
fi

if [ -n "$CONSTRUCTOR_ARGS" ]; then
    echo "  Constructor args: $CONSTRUCTOR_ARGS"
else
    echo "  Constructor args: (auto-detected from cache)"
fi

if [ -n "$VERIFIER_URL" ]; then
    echo "  Verifier: custom ($VERIFIER_URL)"
else
    echo "  Verifier: etherscan"
fi

# Check if verification is disabled
if [ "$VERIFY" != "true" ]; then
    echo ""
    echo "Verification is disabled. Exiting."
    exit 0
fi

# Build verification command
VERIFY_CMD="forge verify-contract --watch"

# Always pass compiler version and optimizer runs (forge auto-detection can be unreliable)
VERIFY_CMD="$VERIFY_CMD --compiler-version $COMPILER_VERSION --num-of-optimizations $OPTIMIZER_RUNS"

# Add verifier configuration
if [ -n "$VERIFIER_URL" ]; then
    # Use custom verifier with URL and API key
    VERIFY_CMD="$VERIFY_CMD --verifier custom --verifier-url $VERIFIER_URL --verifier-api-key $ETHERSCAN_KEY"
else
    # Use etherscan verifier with API key
    VERIFY_CMD="$VERIFY_CMD --verifier etherscan --verifier-api-key $ETHERSCAN_KEY"
fi

# Add chain parameter (can be chain name or URL)
VERIFY_CMD="$VERIFY_CMD --chain $chain"

# Add constructor args if provided
if [ -n "$CONSTRUCTOR_ARGS" ]; then
    VERIFY_CMD="$VERIFY_CMD --constructor-args $CONSTRUCTOR_ARGS"
fi

# Add contract address and path
VERIFY_CMD="$VERIFY_CMD $address $CONTRACT_PATH"

echo ""
echo "Running verification command:"
echo "$VERIFY_CMD"
echo ""

# Execute verification
eval $VERIFY_CMD

echo ""
echo "Verification completed!"
