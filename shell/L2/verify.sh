#!/bin/bash

# Reports L2 ownership and checks that the deployment wallet retains no administrative access.
# This command is read-only. No wallet, Ledger, Safe proposal or broadcast is required.
#
# Usage:
# ./verify.sh --chain robinhood [--deployment <broadcast-file>] [--env <env-file>]
# Addresses come from env.json; the broadcast supplies the deployer and ROLES creation block.

set -eo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../lib/arguments.sh"
load_named_args "$@"
if [ -z "$env" ] && [ -f .env ]; then env=.env; fi
load_env

CHAIN=${chain:-$CHAIN}
RPC_URL=${chain:-$RPC_URL}
validate_text "$CHAIN" "Provide --chain <foundry-rpc-alias>."
validate_text "$RPC_URL" "No RPC URL or alias specified."
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
DEPLOYMENT=${deployment:-"broadcast/L2Deploy.s.sol/$CHAIN_ID/deploy-latest.json"}
validate_file "$DEPLOYMENT" "Provide --deployment <confirmed L2 deployment broadcast>."
ROLES_ADDRESS=$(jq -er --arg chain "$CHAIN" '.current[$chain].olympus.modules.OlympusRoles' src/scripts/env.json)

# Read only the deployment metadata; all contract addresses are loaded from env.json by Solidity.
read -r DEPLOYER ROLES_CREATION_BLOCK < <(jq -er --arg roles "$ROLES_ADDRESS" --arg chainId "$CHAIN_ID" '
    if (.chain | tostring) != $chainId then error("Broadcast does not match the RPC chain") else . end
    | . as $run
    | [.transactions[] | select(.transactionType == "CREATE" and .contractName == "OlympusRoles"
        and (.contractAddress | ascii_downcase) == ($roles | ascii_downcase))]
    | if length == 1 then .[0] else error("Expected the env.json ROLES deployment") end as $tx
    | [$run.receipts[] | select(.transactionHash == $tx.hash and (.status == "0x1" or .status == 1))]
    | if length == 1 then [ $tx.transaction.from, .[0].blockNumber ] | @tsv
      else error("Missing successful ROLES creation receipt") end
' "$DEPLOYMENT")

VERIFY_LOG=$(mktemp /tmp/l2-ownership.XXXXXX)
echo "Ownership verification log: $VERIFY_LOG"
FOUNDRY_PROFILE=deploy forge script ./src/scripts/deploy/L2Deploy.s.sol:L2Deploy \
    --sig "verifyOwnership(string,address,uint256)()" "$CHAIN" "$DEPLOYER" "$ROLES_CREATION_BLOCK" \
    --rpc-url "$RPC_URL" -vv | tee "$VERIFY_LOG"

if ! grep -Fq "OWNERSHIP VERIFICATION: PASS" "$VERIFY_LOG"; then
    display_error "Ownership verification failed. Complete the DAO acceptance calls and remove all retained deployer access."
    exit 1
fi
