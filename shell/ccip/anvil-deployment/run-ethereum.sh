#!/usr/bin/env bash
# End-to-end Ethereum (canonical) rollout of the CCIP config policies on a
# mainnet Anvil fork.
#
# Flow:
#   1. Deploy CCIPBridgeConfig and CCIPBridgeConfigTimelock (ccip_config_mainnet.json)
#      and sync their addresses into the OCG proposal registry.
#   2. Phase B (DAO MS): CCIPBridgeConfigBatch.prepareHandover, then a second
#      run that must propose nothing.
#   3. Phase C (OCG): executeOnAnvilFork.sh replays CCIPBridgeConfigProposal
#      from the timelock (the proposal also simulates the governance path and
#      runs its own _validate before the replay).
#   4. Post-OCG (DAO MS): CCIPRouteReconcileBatch.reconcileRoutes must propose
#      nothing on the converged route; the timelock path is then exercised by
#      changing the desired outbound rate in env.json, reconciling (queues),
#      warping past the delay, executing, and reconciling again (empty).
#   5. Containment (Emergency MS): CCIPBridgeConfigBatch.disableChain, then the
#      declarative recovery through the timelock, then a second disableChain
#      that must propose nothing.
#   6. Print the final authority state.
#
# Usage:
#   ./run-ethereum.sh [--port 8545] [--keep-fork] [--use-deployed]
#
# --use-deployed: skip step 1 and rehearse against the config addresses already
#   in env.json / addresses.json (the real on-chain deployment).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CHAIN="mainnet"
TIMELOCK="0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39"
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

# executeOnAnvilFork.sh health-checks http://localhost:8545 explicitly.
[ "$PORT" = "8545" ] || die "the OCG proposal step requires --port 8545"

cd "$REPO_ROOT"
load_dotenv
backup_tracked_files
trap cleanup EXIT

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

step "Phase C: execute CCIPBridgeConfigProposal from the timelock"
RPC_URL="$RPC" src/scripts/proposals/executeOnAnvilFork.sh \
    --file src/proposals/CCIPBridgeConfigProposal.sol \
    --contract CCIPBridgeConfigProposalScript \
    2>&1 | tee "$LOG_DIR/proposal.log"
grep -q "Proposal executed successfully" "$LOG_DIR/proposal.log" || die "proposal replay failed; see $LOG_DIR/proposal.log"

step "Post-OCG: reconcileRoutes on the converged route (DAO MS)"
run_batch CCIPRouteReconcileBatch reconcileRoutes dao "" "-converged"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileRoutes (converged)"

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
