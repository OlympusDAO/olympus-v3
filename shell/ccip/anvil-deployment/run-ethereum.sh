#!/usr/bin/env bash
# End-to-end Ethereum (canonical) rollout of the CCIP config policies on a
# mainnet Anvil fork.
#
# Flow:
#   1. Inject placeholder pools/peripheries for the four burn/mint chains, then
#      deploy CCIPBridgeConfig and CCIPBridgeConfigTimelock
#      (ccip_config_mainnet.json) and sync their addresses into the OCG
#      proposal registry.
#   2. Phase B (DAO MS): CCIPBridgeConfigBatch.prepareHandover, then a second
#      run that must propose nothing; then CCIPTokenPool.fundPool up to the
#      env.json minimum backing (with an empty re-run).
#   3. Negative checks: the mainnet readiness report is RED and the proposal
#      build fails while the OHM fee budgets are still at the 90k default; then
#      the four mainnet lanes are mocked to 175k and readiness turns GREEN.
#   4. Phase C (OCG): executeOnAnvilFork.sh replays CCIPBridgeConfigProposal
#      (12 actions: the handover plus the four addChain route actions) from
#      the timelock; the four routes must exist on the pool afterwards.
#   5. Post-OCG (DAO MS): CCIPRouteReconcileBatch.reconcileRoutes must propose
#      nothing on the converged routes; the timelock path is then exercised by
#      changing the desired outbound rate in env.json, reconciling (queues),
#      warping past the delay, executing, and reconciling again (empty). The
#      periphery reconciler adds the four EVM trusted remotes (nothing for
#      solana) and proposes nothing on a re-run.
#   6. Containment (Emergency MS): CCIPBridgeConfigBatch.disableChain, then the
#      declarative recovery through the timelock, then a second disableChain
#      that must propose nothing.
#   7. Print the final authority state.
#
# Usage:
#   ./run-ethereum.sh [--port <port>] [--keep-fork] [--use-deployed]
#
# --use-deployed: skip step 1 and rehearse against the config addresses already
#   in env.json / addresses.json (the real on-chain deployment).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CHAIN="mainnet"
SOLANA_SELECTOR="124615329519749607"
DISABLE_ARGS="src/scripts/ops/batches/args/CCIPBridgeConfigBatch_disableChain.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            [ $# -ge 2 ] || die "--port requires a value"
            PORT="$2"
            RPC="http://localhost:${PORT}"
            shift 2
            ;;
        --keep-fork)
            KEEP_FORK="true"
            shift
            ;;
        --use-deployed)
            USE_DEPLOYED="true"
            shift
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

cd "$REPO_ROOT"
load_dotenv
backup_tracked_files
trap cleanup EXIT

TIMELOCK="$(env_addr "$CHAIN" olympus.governance.Timelock)"
require_addr "$TIMELOCK" "$CHAIN olympus.governance.Timelock"

# The proposal resolves the remote pools of its four addChain actions from
# env.json; the burn/mint chains are not deployed on this single-chain fork.
inject_placeholder_contracts "$CHAIN"

start_anvil "$CHAIN"
fund "$DEPLOYER_ADDR"
fund "$TIMELOCK"

if [ "$USE_DEPLOYED" = "true" ]; then
    step "Using already-deployed config addresses from env.json (skipping deploy)"
else
    deploy_sequence "src/scripts/deploy/savedDeployments/ccip_config_mainnet.json"
fi

cfg="$(env_addr mainnet olympus.policies.CCIPBridgeConfig)"
require_addr "$cfg" "CCIPBridgeConfig"
tl="$(env_addr mainnet olympus.policies.CCIPBridgeConfigTimelock)"
require_addr "$tl" "CCIPBridgeConfigTimelock"
pool="$(env_addr mainnet olympus.periphery.CCIPLockReleaseTokenPool)"
require_addr "$pool" "CCIPLockReleaseTokenPool"
registry="$(env_addr mainnet external.ccip.TokenAdminRegistry)"
ohm="$(env_addr mainnet olympus.legacy.OHM)"
dao="$(env_addr mainnet olympus.multisig.dao)"
log "config=$cfg timelock=$tl pool=$pool"

step "Deployment checks"
echo "config.pool()                 = $(cast call "$cfg" 'pool()(address)' --rpc-url "$RPC")"
echo "timelock.config()             = $(cast call "$tl" 'config()(address)' --rpc-url "$RPC")"
echo "timelock.timelockDelay()      = $(cast call "$tl" 'timelockDelay()(uint48)' --rpc-url "$RPC")"
echo "config.gracePeriod()          = $(cast call "$cfg" 'gracePeriod()(uint32)' --rpc-url "$RPC")"
echo "timelock.gracePeriod()        = $(cast call "$tl" 'gracePeriod()(uint32)' --rpc-url "$RPC")"
echo "config.isLiquidityContainer() = $(cast call "$cfg" 'isLiquidityContainer()(bool)' --rpc-url "$RPC")"

step "Sync addresses.json (proposal registry)"
set_registry_addr olympus-policy-ccip-bridge-config "$cfg"
set_registry_addr olympus-policy-ccip-bridge-config-timelock "$tl"

step "Phase B: prepareHandover (DAO MS)"
run_batch CCIPBridgeConfigBatch prepareHandover dao
expect_non_empty_batch "$LAST_BATCH_LOG" "prepareHandover"
run_batch CCIPBridgeConfigBatch prepareHandover dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "prepareHandover re-run"

step "Fund the pool to the minimum backing (DAO MS)"
min_backing="$(jq -r '.current.mainnet.olympus.config.CCIP.minimumPoolBacking' "$REPO_ROOT/$ENV_JSON")"
pool_balance="$(cast call "$ohm" 'balanceOf(address)(uint256)' "$pool" --rpc-url "$RPC" | awk '{print $1}')"
dao_balance="$(cast call "$ohm" 'balanceOf(address)(uint256)' "$dao" --rpc-url "$RPC" | awk '{print $1}')"
log "target=$min_backing pool=$pool_balance dao=$dao_balance"
if [ "$pool_balance" -lt "$min_backing" ] && [ "$dao_balance" -lt "$((min_backing - pool_balance))" ]; then
    # The live DAO MS balance covers the shortfall today; this branch keeps the
    # rehearsal green if it ever does not, by minting from the OHM vault (the
    # MINTR module, resolved through the token's authority rather than assumed).
    ohm_authority="$(cast call "$ohm" 'authority()(address)' --rpc-url "$RPC")"
    ohm_vault="$(cast call "$ohm_authority" 'vault()(address)' --rpc-url "$RPC")"
    top_up="$((min_backing - pool_balance - dao_balance))"
    log "minting $top_up OHM to the DAO MS from the OHM vault $ohm_vault"
    cast_send_impersonated "$ohm_vault" "$ohm" "mint(address,uint256)" "$dao" "$top_up"
fi
run_batch CCIPTokenPool fundPool dao
expect_non_empty_batch "$LAST_BATCH_LOG" "fundPool"
run_batch CCIPTokenPool fundPool dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "fundPool re-run"
echo "pool OHM balance = $(cast call "$ohm" 'balanceOf(address)(uint256)' "$pool" --rpc-url "$RPC")  (target=$min_backing)"

step "Negative: mainnet readiness must be RED before the fee budgets are raised"
if READINESS_RPC_MAINNET="$RPC" ./shell/ccip/check_rollout_readiness.sh --chains mainnet \
    > "$LOG_DIR/readiness-mainnet-red.log" 2>&1; then
    die "the readiness report was expected to be RED; see $LOG_DIR/readiness-mainnet-red.log"
fi
grep -q "READINESS RESULT mainnet: RED" "$LOG_DIR/readiness-mainnet-red.log" \
    || die "the readiness report did not print a RED verdict; see $LOG_DIR/readiness-mainnet-red.log"
log "OK: readiness is RED before the fee budget mock"

step "Negative: the proposal build must fail before the fee budgets are raised"
if RPC_URL="$RPC" src/scripts/proposals/executeOnAnvilFork.sh \
    --file src/proposals/CCIPBridgeConfigProposal.sol \
    --contract CCIPBridgeConfigProposalScript \
    > "$LOG_DIR/proposal-no-budget.log" 2>&1; then
    die "the proposal build was expected to fail; see $LOG_DIR/proposal-no-budget.log"
fi
grep -q "OHM delivery gas budget of the lane" "$LOG_DIR/proposal-no-budget.log" \
    || die "the proposal did not fail on the fee budgets; see $LOG_DIR/proposal-no-budget.log"
log "OK: the proposal build fails on the fee budgets before the mock"

step "Mock the OHM fee entries of the four mainnet lanes"
for peer in arbitrum optimism base berachain; do
    mock_ohm_fee_entry mainnet "$peer"
done

step "Readiness must be GREEN after the fee budget mock"
READINESS_RPC_MAINNET="$RPC" ./shell/ccip/check_rollout_readiness.sh --chains mainnet \
    2>&1 | tee "$LOG_DIR/readiness-mainnet-green.log"
grep -q "READINESS RESULT mainnet: GREEN" "$LOG_DIR/readiness-mainnet-green.log" \
    || die "the readiness report was expected to be GREEN; see $LOG_DIR/readiness-mainnet-green.log"

step "Phase C: execute CCIPBridgeConfigProposal from the timelock"
RPC_URL="$RPC" src/scripts/proposals/executeOnAnvilFork.sh \
    --file src/proposals/CCIPBridgeConfigProposal.sol \
    --contract CCIPBridgeConfigProposalScript \
    2>&1 | tee "$LOG_DIR/proposal.log"
grep -q "Proposal executed successfully" "$LOG_DIR/proposal.log" || die "proposal replay failed; see $LOG_DIR/proposal.log"

step "The four routes must exist on the pool after the proposal"
for peer in arbitrum optimism base berachain; do
    peer_sel="$(jq -r --arg c "$peer" '.current[$c].external.ccip.ChainSelector' "$REPO_ROOT/$ENV_JSON")"
    supported="$(cast call "$pool" 'isSupportedChain(uint64)(bool)' "$peer_sel" --rpc-url "$RPC")"
    [ "$supported" = "true" ] || die "the $peer route is missing on the pool after the proposal"
    log "route $peer (selector $peer_sel) is configured"
done

step "Post-OCG: reconcileRoutes on the converged routes (DAO MS)"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-converged"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes (converged: the proposal added the four routes)"

step "Periphery reconcile (DAO MS): four EVM trusted remotes, nothing for solana"
run_batch CCIPBridge reconcileTrustedRemotes dao
expect_non_empty_batch "$LAST_BATCH_LOG" "reconcileTrustedRemotes"
if grep -q "Added: setTrustedRemoteSVM\|Added: unsetTrustedRemoteSVM" "$LAST_BATCH_LOG"; then
    die "the periphery reconciler proposed a solana change on the migrated env; see $LAST_BATCH_LOG"
fi
run_batch CCIPBridge reconcileTrustedRemotes dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileTrustedRemotes re-run"

step "Timelock path: change the desired Solana outbound rate, reconcile, execute, reconcile"
orig_rate="$(jq -r '.current.mainnet.olympus.config.CCIP.routes.solana.outboundRateLimit.rate' "$REPO_ROOT/$ENV_JSON")"
new_rate="$((orig_rate + 1))"
set_env_value mainnet "olympus.config.CCIP.routes.solana.outboundRateLimit.rate" "\"$new_rate\""
log "desired outbound rate: $orig_rate -> $new_rate"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-queue"
expect_non_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes (queue setChainRateLimits)"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-queue-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes re-run (already queued)"
run_batch CCIPRouteReconcileBatch executeReadyActions dao "" "-early"
expect_empty_batch "$LAST_BATCH_LOG" "executeReadyActions before the delay"
# cast appends a scientific-notation hint to large numbers; keep the first token only
delay="$(cast call "$tl" 'timelockDelay()(uint48)' --rpc-url "$RPC" | awk '{print $1}')"
warp "$((delay + 1))"
run_batch CCIPRouteReconcileBatch executeReadyActions dao "" "-ready"
expect_non_empty_batch "$LAST_BATCH_LOG" "executeReadyActions after the delay"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-after-execute"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes after execution"
echo "outbound bucket = $(cast call "$pool" 'getCurrentOutboundRateLimiterState(uint64)((uint128,uint32,bool,uint128,uint128))' "$SOLANA_SELECTOR" --rpc-url "$RPC")"

step "Restore the desired rate and converge again"
set_env_value mainnet "olympus.config.CCIP.routes.solana.outboundRateLimit.rate" "\"$orig_rate\""
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-restore-queue"
expect_non_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes (queue restore)"
warp "$((delay + 1))"
run_batch CCIPRouteReconcileBatch executeReadyActions dao "" "-restore-execute"
expect_non_empty_batch "$LAST_BATCH_LOG" "executeReadyActions (restore)"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-restored"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes after restore"

step "Containment (Emergency MS) and declarative recovery"
run_batch CCIPBridgeConfigBatch disableChain emergency "$DISABLE_ARGS"
expect_non_empty_batch "$LAST_BATCH_LOG" "disableChain"
echo "config.isChainDisabled(solana) = $(cast call "$cfg" 'isChainDisabled(uint64)(bool)' "$SOLANA_SELECTOR" --rpc-url "$RPC")"
run_batch CCIPBridgeConfigBatch disableChain emergency "$DISABLE_ARGS" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "disableChain re-run"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-recovery-queue"
expect_non_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes (queue the limit restore)"
warp "$((delay + 1))"
run_batch CCIPRouteReconcileBatch executeReadyActions dao "" "-recovery-execute"
expect_non_empty_batch "$LAST_BATCH_LOG" "executeReadyActions (recovery)"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-recovered"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes after recovery"
echo "config.isChainDisabled(solana) = $(cast call "$cfg" 'isChainDisabled(uint64)(bool)' "$SOLANA_SELECTOR" --rpc-url "$RPC")"

step "Post-run state"
roles_mod="$(env_addr mainnet olympus.modules.OlympusRoles)"
echo "pool.owner()                  = $(cast call "$pool" 'owner()(address)' --rpc-url "$RPC")  (config=$cfg)"
echo "pool pending owner (slot 0)   = $(cast storage "$pool" 0 --rpc-url "$RPC")"
echo "pool.getRebalancer()          = $(cast call "$pool" 'getRebalancer()(address)' --rpc-url "$RPC")  (timelock=$TIMELOCK)"
echo "pool.getRateLimitAdmin()      = $(cast call "$pool" 'getRateLimitAdmin()(address)' --rpc-url "$RPC")"
echo "config.configOperator()       = $(cast call "$cfg" 'configOperator()(address)' --rpc-url "$RPC")  (timelock policy=$tl)"
echo "config.isEnabled()            = $(cast call "$cfg" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "timelock.isEnabled()          = $(cast call "$tl" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "registry.getTokenConfig(OHM)  = $(cast call "$registry" 'getTokenConfig(address)((address,address,address))' "$ohm" --rpc-url "$RPC")"
echo "DAO MS bridge_admin           = $(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$dao" "$(cast format-bytes32-string bridge_admin)" --rpc-url "$RPC")"
echo "DAO MS bridge_rate_limiter    = $(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$dao" "$(cast format-bytes32-string bridge_rate_limiter)" --rpc-url "$RPC")"
echo "pool.getSupportedChains()     = $(cast call "$pool" 'getSupportedChains()(uint64[])' --rpc-url "$RPC")"
echo "outbound bucket (solana)      = $(cast call "$pool" 'getCurrentOutboundRateLimiterState(uint64)((uint128,uint32,bool,uint128,uint128))' "$SOLANA_SELECTOR" --rpc-url "$RPC")"
echo "inbound bucket (solana)       = $(cast call "$pool" 'getCurrentInboundRateLimiterState(uint64)((uint128,uint32,bool,uint128,uint128))' "$SOLANA_SELECTOR" --rpc-url "$RPC")"
echo "timelock.nextActionId()       = $(cast call "$tl" 'nextActionId()(uint64)' --rpc-url "$RPC")"

step "Ethereum CCIP config rollout complete"
log "config=$cfg timelock=$tl pool=$pool"
