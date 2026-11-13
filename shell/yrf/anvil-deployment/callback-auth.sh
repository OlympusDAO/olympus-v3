#!/bin/bash
# Rehearses YieldRepurchaseFacilityV2SetupBatch.setCallbackAuthStatus on the fork of the
# harness: the batch whose owner is the Safe that owns the Bond Protocol auctioneer.
#
# shell/safeBatchV2.sh impersonates only the DAO MS and the Emergency MS in fork mode, so this
# script runs forge script directly, with the settings of safeBatchV2.sh and the live owner of
# the auctioneer as the sender.
#
# Usage:
#   ./shell/yrf/anvil-deployment/callback-auth.sh [--port <port>]
#
# Requires a fork on which the facility is deployed and recorded in env.json. On mainnet the
# same entry point runs through safeBatchV2.sh with a signer of that Safe:
#   ./shell/safeBatchV2.sh --contract YieldRepurchaseFacilityV2SetupBatch \
#       --function setCallbackAuthStatus --chain mainnet --multisig true --ledger <index> \
#       --broadcast true

set -euo pipefail

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            # Read by lib/common.sh
            # shellcheck disable=SC2034
            PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

AUCTIONEER="$(env_value external.bond-protocol.BondFixedTermAuctioneer)"
FACILITY="$(env_value olympus.policies.YieldRepurchaseFacilityV2)"
require_addr "$AUCTIONEER" "external.bond-protocol.BondFixedTermAuctioneer"
require_addr "$FACILITY" "olympus.policies.YieldRepurchaseFacilityV2"

# The owner is read live: the batch proposes to whichever Safe owns the auctioneer.
AUCTIONEER_OWNER="$(call "$AUCTIONEER" 'owner()(address)')"
require_addr "$AUCTIONEER_OWNER" "the owner of the bond auctioneer"
log "Bond auctioneer $AUCTIONEER is owned by $AUCTIONEER_OWNER"

mkdir -p "$LOG_DIR"
run_batch YieldRepurchaseFacilityV2SetupBatch setCallbackAuthStatus "$AUCTIONEER_OWNER"
expect "auctioneer.callbackAuthorized(facility)" \
    "$(call "$AUCTIONEER" 'callbackAuthorized(address)(bool)' "$FACILITY")" true
