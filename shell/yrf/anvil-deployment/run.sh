#!/bin/bash
# Rehearses the deployment of the YieldRepurchaseFacilityV2 stack and its multisig batches on a
# local Anvil fork of Ethereum mainnet.
#
# Deployment:
#   1. Back up src/scripts/env.json and src/proposals/addresses.json, start an Anvil fork of
#      mainnet, fund the deployer (Anvil dev account #0) and carry the answers of the price
#      feeds over to mocks whose update time the harness controls.
#   2. Deploy backing_oracle.json (the oracle and its config timelock) through DeployV3.
#   3. Deploy yieldRepo_v2.json through DeployYieldRepurchaseFacilityV2: the configuration
#      policy, its config timelock, the facility, the lens and the activator of the launch.
#      Forge deploys the six linked libraries of the facility through the CREATE2 factory
#      before the script runs.
#   4. Check the libraries: the six addresses the run linked, the olympus.libraries keys of
#      env.json and the code at each address.
#   5. Check the deployed contracts against env.json: bindings, parameters and the
#      disabled, not yet activated state.
#   6. Sync the seven deployed addresses and the USDe and sUSDe tokens into addresses.json.
#
# Batches (lib/batches.sh), every entry point with a state change, again on the converged
# state, and with its precondition failures:
#   7. Kernel activation: BackingOracleSetupBatch.setupKernel and
#      YieldRepurchaseFacilityV2SetupBatch.setupKernel from the DAO MS.
#   8. The readiness report, red before and green after
#      YieldRepurchaseFacilityV2SetupBatch.setCallbackAuthStatus from the Safe that owns the
#      bond auctioneer (callback-auth.sh), and the build of the launch proposal, which fails
#      before the authorization.
#   9. The launch: src/scripts/proposals/executeOnAnvilFork.sh replays
#      YieldRepurchaseFacilityV2Proposal from the impersonated OCG timelock, and a second
#      build fails on the used activator.
#  10. YieldRepurchaseFacilityV2SetupBatch.deactivateV1 from the DAO MS.
#  11. YieldRepurchaseFacilityV2ConfigTimelockBatch: reconcile, a run of cancellations, a
#      warp past the delay and executeReadyActions.
#  12. Asset status changes, queueDecreaseNextYield, cancelQueuedAction and
#      cancelQueuedActionEmergency.
#  13. YieldRepurchaseFacilityV2Batch: reconcileStepGasLimit, rescue, the four emergency
#      levers of the Emergency MS and reEnable from the DAO MS.
#  14. BackingOracleConfigTimelockBatch and BackingOracleBatch: the backing through the
#      timelock, cancellations, the emergency levers and reEnable.
#  15. Print the final state.
#
# Usage:
#   ./shell/yrf/anvil-deployment/run.sh [--port <port>] [--fork-block-number <n>]
#       [--keep-fork] [--deploy-only]
#
# Without --keep-fork, env.json and addresses.json are restored on exit, the deployment
# records the run wrote under deployments/ and broadcast/ and the forge script state it wrote
# under cache/ are removed and Anvil is stopped. --deploy-only stops after step 6.

set -euo pipefail

FORK_BLOCK=""
KEEP_FORK=false
DEPLOY_ONLY=false
while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            # Read by lib/common.sh
            # shellcheck disable=SC2034
            PORT="$2"
            shift 2
            ;;
        --fork-block-number)
            FORK_BLOCK="$2"
            shift 2
            ;;
        --keep-fork)
            KEEP_FORK=true
            shift
            ;;
        --deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source-path=SCRIPTDIR source=lib/batches.sh
source "$HERE/lib/batches.sh"

DEPLOY_V3="src/scripts/deploy/DeployV3.s.sol:DeployV3"
DEPLOY_YRF="src/scripts/deploy/DeployYieldRepurchaseFacilityV2.s.sol:DeployYieldRepurchaseFacilityV2"
SEQ_ORACLE="src/scripts/deploy/savedDeployments/backing_oracle.json"
SEQ_YRF="src/scripts/deploy/savedDeployments/yieldRepo_v2.json"
YRF_BROADCAST="broadcast/DeployYieldRepurchaseFacilityV2.s.sol/1/deploy-latest.json"
CREATE2_FACTORY="0x4e59b44847b379578588920ca78fbf26c0b4956c"

LIBRARIES=(
    YieldRepurchaseFacilityV2AssetRegistryLib
    YieldRepurchaseFacilityV2BondMarketLib
    YieldRepurchaseFacilityV2BuybackPoolLib
    YieldRepurchaseFacilityV2ClearinghouseLib
    YieldRepurchaseFacilityV2DependenciesLib
    YieldRepurchaseFacilityV2YieldLib
)

# The scripts whose forge records the run removes on exit: the two deployment scripts, the
# launch proposal and the six batches.
RECORDED_SCRIPTS=(
    DeployV3.s.sol
    DeployYieldRepurchaseFacilityV2.s.sol
    YieldRepurchaseFacilityV2Proposal.sol
    "${SETUP_BATCH}.sol"
    "${YRF_BATCH}.sol"
    "${YRF_TIMELOCK_BATCH}.sol"
    "${ORACLE_SETUP_BATCH}.sol"
    "${ORACLE_BATCH}.sol"
    "${ORACLE_TIMELOCK_BATCH}.sol"
)

# ========== FILES ========== #

backup_tracked_files() {
    mkdir -p "$BACKUP_DIR"
    cp "$REPO_ROOT/$ENV_JSON" "$BACKUP_DIR/env.json.bak"
    cp "$REPO_ROOT/$ADDR_JSON" "$BACKUP_DIR/addresses.json.bak"
}

cleanup() {
    local code=$?
    if [ "$KEEP_FORK" = "true" ]; then
        log "--keep-fork: Anvil (pid ${ANVIL_PID:-?}) left running on $RPC; env.json and addresses.json left modified."
        log "Stop it with: kill ${ANVIL_PID:-<pid>}"
    else
        [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2> /dev/null || true
        if [ -f "$BACKUP_DIR/env.json.bak" ]; then
            cp "$BACKUP_DIR/env.json.bak" "$REPO_ROOT/$ENV_JSON"
            cp "$BACKUP_DIR/addresses.json.bak" "$REPO_ROOT/$ADDR_JSON"
            # The deployment records and the generated args files of this run are newer than the
            # backup; older records are kept.
            find "$REPO_ROOT/deployments" -maxdepth 1 -name '.*-*.json' \
                -newer "$BACKUP_DIR/env.json.bak" -delete 2> /dev/null || true
            # The run-*.json records of both deployment scripts are tracked for real deployments.
            # The fork runs under chain id 1, so its *-latest.json sequence and the recovery
            # snapshot that forge keeps under cache/ share the paths of a mainnet run: an
            # interrupted rehearsal would leave unfinished operations that a later mainnet
            # broadcast from this checkout refuses to start over. The lock files are left in
            # place.
            local dir
            for dir in "${RECORDED_SCRIPTS[@]}"; do
                [ -d "$REPO_ROOT/broadcast/$dir" ] && find "$REPO_ROOT/broadcast/$dir" \
                    \( -name 'run-*.json' -o -name '*-latest.json' \) \
                    -newer "$BACKUP_DIR/env.json.bak" -delete 2> /dev/null || true
                [ -d "$REPO_ROOT/cache/$dir" ] && find "$REPO_ROOT/cache/$dir" -type f \
                    ! -name '*.lock' -newer "$BACKUP_DIR/env.json.bak" -delete 2> /dev/null || true
            done
        fi
        log "Anvil stopped; env.json and addresses.json restored; the records of the fork run removed."
    fi
    exit "$code"
}

# deploy_sequence <script> <sequence> <log-name>: the forge invocation of shell/deployV3.sh,
# signed with the dev key.
deploy_sequence() {
    step "Deploy $2 through ${1##*:}"
    (
        cd "$REPO_ROOT" || exit
        set -o pipefail
        FOUNDRY_PROFILE=deploy forge script "$1" --sig "deploy(string)()" "$2" \
            --rpc-url "$RPC" --private-key "$DEPLOYER_KEY" --sender "$DEPLOYER_ADDR" \
            --slow "${TX_FLAG_ARGS[@]}" --broadcast -vvv 2>&1 | tee "$LOG_DIR/deploy-$3.log"
    ) || die "deployment of $2 failed; see $LOG_DIR/deploy-$3.log"
}

# ========== RUN ========== #

cd "$REPO_ROOT"
for tool in anvil forge cast jq git curl; do
    command -v "$tool" > /dev/null || die "$tool not found in PATH"
done
load_dotenv
# The deployment bytecode, and the MockPriceFeed artifact the feed refresh places on the fork.
step "Build (deploy profile)"
FOUNDRY_PROFILE=deploy forge build -q || die "the build failed"
trap cleanup EXIT
backup_tracked_files

start_anvil "$FORK_BLOCK"
fund "$DEPLOYER_ADDR"
# The simulation of the launch proposal rolls far ahead; see the function.
prefill_block_hash_history
# The launch registers the USDe/USD feed, which the PRICE module does not read before it.
EXTRA_PRICE_FEEDS=("$(env_value external.chainlink.usdeUsdPriceFeed)")
require_addr "${EXTRA_PRICE_FEEDS[0]}" "external.chainlink.usdeUsdPriceFeed"
# The answers of the feeds are carried over while every feed still reports one.
refresh_price_feeds

deploy_sequence "$DEPLOY_V3" "$SEQ_ORACLE" oracle
deploy_sequence "$DEPLOY_YRF" "$SEQ_YRF" yrf

load_stack

GRACE="$(env_value "$YRF_KEY.gracePeriod")"
STEP_GAS="$(env_value "$YRF_KEY.stepGasLimit")"
DELAY="$(env_value "$YRF_KEY.timelockDelay")"

step "Linked libraries"
[ -f "$REPO_ROOT/$YRF_BROADCAST" ] || die "$YRF_BROADCAST not found"
expect "linked library count" "$(jq '.libraries | length' "$REPO_ROOT/$YRF_BROADCAST")" \
    "${#LIBRARIES[@]}"
printf '  CREATE2 transactions to the factory in this run: %s\n' "$(jq --arg f "$CREATE2_FACTORY" \
    '[.transactions[] | select(.transactionType == "CREATE2" and
    (.transaction.to | ascii_downcase) == $f)] | length' "$REPO_ROOT/$YRF_BROADCAST")"
for lib in "${LIBRARIES[@]}"; do
    recorded="$(env_value "olympus.libraries.$lib")"
    require_addr "$recorded" "olympus.libraries.$lib"
    linked="$(jq -r --arg n "$lib" \
        '.libraries[] | select(split(":")[1] == $n) | split(":")[2]' "$REPO_ROOT/$YRF_BROADCAST")"
    expect "$lib linked = recorded" "$linked" "$recorded"
    [ "$(cast codesize "$recorded" --rpc-url "$RPC")" -gt 0 ] || die "$lib has no code at $recorded"
done

step "Deployment checks"
expect "oracle.kernel()" "$(call "$ORACLE" 'kernel()(address)')" "$KERNEL"
expect "oracle.decimals()" "$(call "$ORACLE" 'decimals()(uint8)')" 18
expect "oracle.gracePeriod()" "$(call "$ORACLE" 'gracePeriod()(uint32)')" 604800
expect "oracle.configOperator()" "$(call "$ORACLE" 'configOperator()(address)')" "$ZERO_ADDRESS"
expect "oracle.isEnabled()" "$(call "$ORACLE" 'isEnabled()(bool)')" false

expect "oracleTimelock.kernel()" "$(call "$ORACLE_TIMELOCK" 'kernel()(address)')" "$KERNEL"
expect "oracleTimelock.backingOracle()" \
    "$(call "$ORACLE_TIMELOCK" 'backingOracle()(address)')" "$ORACLE"
expect "oracleTimelock.timelockDelay()" \
    "$(call "$ORACLE_TIMELOCK" 'timelockDelay()(uint48)')" 86400
expect "oracleTimelock.gracePeriod()" "$(call "$ORACLE_TIMELOCK" 'gracePeriod()(uint32)')" 604800
expect "oracleTimelock.isEnabled()" "$(call "$ORACLE_TIMELOCK" 'isEnabled()(bool)')" false

expect "config.kernel()" "$(call "$CONFIG" 'kernel()(address)')" "$KERNEL"
expect "config.facility()" "$(call "$CONFIG" 'facility()(address)')" "$ZERO_ADDRESS"
expect "config.gracePeriod()" "$(call "$CONFIG" 'gracePeriod()(uint32)')" "$GRACE"
expect "config.isEnabled()" "$(call "$CONFIG" 'isEnabled()(bool)')" false

expect "timelock.kernel()" "$(call "$TIMELOCK" 'kernel()(address)')" "$KERNEL"
expect "timelock.config()" "$(call "$TIMELOCK" 'config()(address)')" "$CONFIG"
expect "timelock.timelockDelay()" "$(call "$TIMELOCK" 'timelockDelay()(uint48)')" "$DELAY"
expect "timelock.gracePeriod()" "$(call "$TIMELOCK" 'gracePeriod()(uint32)')" "$GRACE"
expect "timelock.isEnabled()" "$(call "$TIMELOCK" 'isEnabled()(bool)')" false

expect "facility.kernel()" "$(call "$FACILITY" 'kernel()(address)')" "$KERNEL"
expect "facility.backingOracle()" "$(call "$FACILITY" 'backingOracle()(address)')" "$ORACLE"
expect "facility.bondAuctioneer()" "$(call "$FACILITY" 'bondAuctioneer()(address)')" "$AUCTIONEER"
expect "facility.bondTeller()" "$(call "$FACILITY" 'bondTeller()(address)')" \
    "$(env_value external.bond-protocol.BondFixedTermTeller)"
expect "facility.stepGasLimit()" "$(call "$FACILITY" 'stepGasLimit()(uint32)')" "$STEP_GAS"
expect "facility.gracePeriod()" "$(call "$FACILITY" 'gracePeriod()(uint32)')" "$GRACE"
expect "facility.configurator()" "$(call "$FACILITY" 'configurator()(address)')" "$ZERO_ADDRESS"
expect "facility.isEnabled()" "$(call "$FACILITY" 'isEnabled()(bool)')" false

expect "lens.facility()" "$(call "$LENS" 'facility()(address)')" "$FACILITY"

# The readiness report compares every binding and launch value of the activator with env.json.
expect "activator.timelock()" "$(call "$ACTIVATOR" 'timelock()(address)')" "$OCG_TIMELOCK"
expect "activator.isActivated()" "$(call "$ACTIVATOR" 'isActivated()(bool)')" false
expect "activator.deployment().facility" "$(cast call "$ACTIVATOR" \
    'deployment()((address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address))' \
    --rpc-url "$RPC" | tr -d '()' | awk -F', ' '{print $6}')" "$FACILITY"
expect "activator code size fits EIP-170" \
    "$([ "$(cast codesize "$ACTIVATOR" --rpc-url "$RPC")" -le 24576 ] && echo true || echo false)" true

for pair in "oracle:$ORACLE" "oracleTimelock:$ORACLE_TIMELOCK" "config:$CONFIG" \
    "timelock:$TIMELOCK" "facility:$FACILITY"; do
    expect "kernel.isPolicyActive(${pair%%:*})" \
        "$(call "$KERNEL" 'isPolicyActive(address)(bool)' "${pair#*:}")" false
done

step "Sync addresses.json (proposal registry)"
set_registry_addr olympus-policy-backing-oracle "$ORACLE"
set_registry_addr olympus-policy-backing-oracle-config-timelock "$ORACLE_TIMELOCK"
set_registry_addr olympus-policy-yieldrepurchasefacility-config-1_0 "$CONFIG"
set_registry_addr olympus-policy-yieldrepurchasefacility-config-timelock-1_0 "$TIMELOCK"
set_registry_addr olympus-policy-yieldrepurchasefacility-2_0 "$FACILITY"
set_registry_addr olympus-periphery-yieldrepurchasefacility-lens "$LENS"
set_registry_addr olympus-proposal-yieldrepurchasefacility-v2-activator "$ACTIVATOR"
set_registry_addr external-tokens-usde "$USDE"
set_registry_addr external-tokens-susde "$SUSDE"

if [ "$DEPLOY_ONLY" = "true" ]; then
    log "Deployment rehearsal passed (--deploy-only)."
    exit 0
fi

rehearse_kernel_setup
rehearse_readiness
rehearse_launch
rehearse_deactivate_v1
rehearse_reconcile
rehearse_asset_status
rehearse_facility_lifecycle
rehearse_oracle
print_final_state

log "Rehearsal passed."
