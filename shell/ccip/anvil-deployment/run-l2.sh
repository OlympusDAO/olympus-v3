#!/usr/bin/env bash
# End-to-end rollout of the CCIP triad (burn/mint pool, config policy, config
# timelock) and the periphery on a burn/mint L2, on a local Anvil fork.
#
# Flow:
#   1. Inject placeholder pools/peripheries for the other burn/mint chains.
#   2. Registry handover: transferAdminRole from the Olympus deployer EOA, then
#      acceptAdminRole from the DAO MS (the real CCIPTokenPool entry points).
#   3. Deploy ccip_full_not_mainnet.json (pool, periphery, config, timelock).
#   4. transferTokenPoolOwnershipToConfig and the periphery transferOwnership,
#      both from the deployer.
#   5. Negative checks: the readiness report is RED and the setup batch fails
#      naming a lane while the OHM fee budgets are still at the 90k default.
#   6. Mock the OHM fee entries (175k) on the live fee contracts of this chain.
#   7. Readiness GREEN; setup (and an empty re-run); finalize (and an empty
#      re-run); periphery reconcile + enable (and empty re-runs).
#   8. Print the final authority state.
#
# Usage:
#   ./run-l2.sh [--chain arbitrum|optimism|base|berachain] [--port <port>] [--keep-fork]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CHAIN="arbitrum"
while [ $# -gt 0 ]; do
    case "$1" in
        --chain)
            [ $# -ge 2 ] || die "--chain requires a value"
            CHAIN="$2"
            shift 2
            ;;
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
        *) die "unknown argument: $1" ;;
    esac
done

case "$CHAIN" in
    arbitrum | optimism | base | berachain) ;;
    *) die "the chain must be one of arbitrum|optimism|base|berachain (got '$CHAIN')" ;;
esac
HARNESS_CHAIN="$CHAIN"

cd "$REPO_ROOT"
load_dotenv
backup_tracked_files
trap cleanup EXIT

inject_placeholder_contracts "$CHAIN"

start_anvil "$CHAIN"
fund "$DEPLOYER_ADDR"

dao="$(env_addr "$CHAIN" olympus.multisig.dao)"
require_addr "$dao" "$CHAIN olympus.multisig.dao"
registry="$(env_addr "$CHAIN" external.ccip.TokenAdminRegistry)"
ohm="$(env_addr "$CHAIN" olympus.legacy.OHM)"
kernel="$(env_addr "$CHAIN" olympus.Kernel)"
roles_mod="$(env_addr "$CHAIN" olympus.modules.OlympusRoles)"
ems="$(env_addr "$CHAIN" olympus.multisig.emergency)"

step "Registry handover: deployer EOA -> DAO MS"
echo "registry.getTokenConfig(OHM) = $(cast call "$registry" 'getTokenConfig(address)((address,address,address))' "$ohm" --rpc-url "$RPC")"
run_script_fn CCIPTokenPool "transferTokenPoolAdminRoleToDaoMS()" "$OLYMPUS_DEPLOYER_EOA" "transferAdminRole-$CHAIN"
run_script_fn CCIPTokenPool "acceptAdminRole(bool)" "$dao" "acceptAdminRole-$CHAIN" true
echo "registry.getTokenConfig(OHM) = $(cast call "$registry" 'getTokenConfig(address)((address,address,address))' "$ohm" --rpc-url "$RPC")"

deploy_sequence "src/scripts/deploy/savedDeployments/ccip_full_not_mainnet.json"

pool="$(env_addr "$CHAIN" olympus.policies.CCIPBurnMintTokenPool)"
require_addr "$pool" "deployed CCIPBurnMintTokenPool"
cfg="$(env_addr "$CHAIN" olympus.policies.CCIPBridgeConfig)"
require_addr "$cfg" "deployed CCIPBridgeConfig"
tl="$(env_addr "$CHAIN" olympus.policies.CCIPBridgeConfigTimelock)"
require_addr "$tl" "deployed CCIPBridgeConfigTimelock"
per="$(env_addr "$CHAIN" olympus.periphery.CCIPCrossChainBridge)"
require_addr "$per" "deployed CCIPCrossChainBridge"
log "pool=$pool config=$cfg timelock=$tl periphery=$per"

step "Deployment checks"
echo "config.pool()                 = $(cast call "$cfg" 'pool()(address)' --rpc-url "$RPC")"
echo "timelock.config()             = $(cast call "$tl" 'config()(address)' --rpc-url "$RPC")"
echo "timelock.timelockDelay()      = $(cast call "$tl" 'timelockDelay()(uint48)' --rpc-url "$RPC")"
echo "config.gracePeriod()          = $(cast call "$cfg" 'gracePeriod()(uint32)' --rpc-url "$RPC")"
echo "config.isLiquidityContainer() = $(cast call "$cfg" 'isLiquidityContainer()(bool)' --rpc-url "$RPC")"

step "Pool and periphery ownership handover (deployer)"
run_script_fn CCIPTokenPool "transferTokenPoolOwnershipToConfig()" "$DEPLOYER_ADDR" "transferPoolOwnership-$CHAIN"
run_batch_from CCIPBridge transferOwnership "$DEPLOYER_ADDR" false "" "-deployer"
expect_non_empty_batch "$LAST_BATCH_LOG" "periphery transferOwnership"
echo "pool.owner()      = $(cast call "$pool" 'owner()(address)' --rpc-url "$RPC")  (deployer=$DEPLOYER_ADDR)"
echo "periphery.owner() = $(cast call "$per" 'owner()(address)' --rpc-url "$RPC")  (dao=$dao)"

step "Negative: readiness must be RED before the fee budgets are raised"
READINESS_VAR="READINESS_RPC_$(echo "$CHAIN" | tr '[:lower:]-' '[:upper:]_')"
if env "$READINESS_VAR=$RPC" ./shell/ccip/check_rollout_readiness.sh --chains "$CHAIN" \
    > "$LOG_DIR/readiness-$CHAIN-red.log" 2>&1; then
    die "the readiness report was expected to be RED; see $LOG_DIR/readiness-$CHAIN-red.log"
fi
grep -q "READINESS RESULT $CHAIN: RED" "$LOG_DIR/readiness-$CHAIN-red.log" \
    || die "the readiness report did not print a RED verdict; see $LOG_DIR/readiness-$CHAIN-red.log"
log "OK: readiness is RED before the fee budget mock"

step "Negative: setup must fail naming a lane before the fee budgets are raised"
run_batch_expect_fail CCIPNonEthereumSetupBatch setup dao "OHM delivery gas budget of the lane" "" "-no-budget"

step "Mock the OHM fee entries of every outgoing burn/mint lane"
while read -r peer; do
    mock_ohm_fee_entry "$CHAIN" "$peer"
done < <(l2_route_peers "$CHAIN")

step "Readiness must be GREEN after the fee budget mock"
env "$READINESS_VAR=$RPC" ./shell/ccip/check_rollout_readiness.sh --chains "$CHAIN" \
    2>&1 | tee "$LOG_DIR/readiness-$CHAIN-green.log"
grep -q "READINESS RESULT $CHAIN: GREEN" "$LOG_DIR/readiness-$CHAIN-green.log" \
    || die "the readiness report was expected to be GREEN; see $LOG_DIR/readiness-$CHAIN-green.log"

step "Setup (DAO MS)"
run_batch CCIPNonEthereumSetupBatch setup dao
expect_non_empty_batch "$LAST_BATCH_LOG" "setup"
run_batch CCIPNonEthereumSetupBatch setup dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "setup re-run"

step "Pre-finalize state: the pool must be inactive and unregistered"
echo "pool.isEnabled()             = $(cast call "$pool" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "registry.getTokenConfig(OHM) = $(cast call "$registry" 'getTokenConfig(address)((address,address,address))' "$ohm" --rpc-url "$RPC")"

step "Finalize (DAO MS)"
run_batch CCIPNonEthereumSetupBatch finalize dao
expect_non_empty_batch "$LAST_BATCH_LOG" "finalize"
run_batch CCIPNonEthereumSetupBatch finalize dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "finalize re-run"

step "Periphery reconcile and enable (DAO MS)"
run_batch CCIPBridge reconcileTrustedRemotes dao
expect_non_empty_batch "$LAST_BATCH_LOG" "reconcileTrustedRemotes"
run_batch CCIPBridge reconcileTrustedRemotes dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "reconcileTrustedRemotes re-run"
run_batch CCIPBridge enable dao
expect_non_empty_batch "$LAST_BATCH_LOG" "periphery enable"
run_batch CCIPBridge enable dao "" "-rerun"
expect_empty_batch "$LAST_BATCH_LOG" "periphery enable re-run"

step "Post-run state"
mainnet_sel="$(jq -r '.current.mainnet.external.ccip.ChainSelector' "$REPO_ROOT/$ENV_JSON")"
echo "pool.owner()                  = $(cast call "$pool" 'owner()(address)' --rpc-url "$RPC")  (config=$cfg)"
echo "pool.isEnabled()              = $(cast call "$pool" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "config.isEnabled()            = $(cast call "$cfg" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "timelock.isEnabled()          = $(cast call "$tl" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "config.configOperator()       = $(cast call "$cfg" 'configOperator()(address)' --rpc-url "$RPC")  (timelock=$tl)"
echo "pool.getRateLimitAdmin()      = $(cast call "$pool" 'getRateLimitAdmin()(address)' --rpc-url "$RPC")"
echo "registry.getTokenConfig(OHM)  = $(cast call "$registry" 'getTokenConfig(address)((address,address,address))' "$ohm" --rpc-url "$RPC")"
echo "kernel legacy bridge active   = $(cast call "$kernel" 'isPolicyActive(address)(bool)' "$(env_addr "$CHAIN" olympus.policies.CrossChainBridge)" --rpc-url "$RPC")"
echo "DAO MS admin                  = $(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$dao" "$(cast format-bytes32-string admin)" --rpc-url "$RPC")"
echo "DAO MS bridge_admin           = $(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$dao" "$(cast format-bytes32-string bridge_admin)" --rpc-url "$RPC")"
echo "Emergency MS emergency        = $(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$ems" "$(cast format-bytes32-string emergency)" --rpc-url "$RPC")"
echo "pool.getSupportedChains()     = $(cast call "$pool" 'getSupportedChains()(uint64[])' --rpc-url "$RPC")"
echo "outbound bucket (mainnet)     = $(cast call "$pool" 'getCurrentOutboundRateLimiterState(uint64)((uint128,uint32,bool,uint128,uint128))' "$mainnet_sel" --rpc-url "$RPC")"
echo "inbound bucket (mainnet)      = $(cast call "$pool" 'getCurrentInboundRateLimiterState(uint64)((uint128,uint32,bool,uint128,uint128))' "$mainnet_sel" --rpc-url "$RPC")"
echo "periphery.isEnabled()         = $(cast call "$per" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "trusted remote (mainnet)      = $(cast call "$per" 'getTrustedRemoteEVM(uint64)((address,bool))' "$mainnet_sel" --rpc-url "$RPC")"
echo "gas limit (mainnet)           = $(cast call "$per" 'getGasLimit(uint64)(uint32)' "$mainnet_sel" --rpc-url "$RPC")"

step "L2 CCIP rollout complete for $CHAIN"
log "pool=$pool config=$cfg timelock=$tl periphery=$per"
