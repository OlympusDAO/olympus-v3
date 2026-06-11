#!/usr/bin/env bash
# End-to-end L2 rollout of the LayerZero bridge on a local Anvil fork.
#
# Forks the target L2, deploys the non-canonical contract set, then runs the
# real gateway and periphery batch scripts in migration order:
#   LZBridgeGatewayL2Batch:    activateGateway, grantRoles, configureAndEnable,
#                              wireConfig, revokeSetupRoles
#   LZCrossChainBridgeL2Batch: initializeConfigurator, setupL2
#
# Usage:
#   ./run-l2.sh [--chain arbitrum|optimism|base|berachain] [--port 8545] [--keep-fork]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CHAIN="arbitrum"
while [ $# -gt 0 ]; do
  case "$1" in
    --chain) CHAIN="$2"; shift 2;;
    --port) PORT="$2"; RPC="http://localhost:${PORT}"; shift 2;;
    --keep-fork) KEEP_FORK="true"; shift;;
    *) die "unknown argument: $1";;
  esac
done

case "$CHAIN" in
  arbitrum|optimism|base|berachain) ;;
  *) die "L2 chain must be one of arbitrum|optimism|base|berachain (got '$CHAIN')";;
esac

cd "$REPO_ROOT"
load_dotenv
backup_tracked_files
trap cleanup EXIT

# Stand-in gateways for the four remote chains so configureAndEnable peer wiring
# resolves; the tested chain gets its real address from the deploy below.
step "Inject placeholder remote gateways"
for ch in mainnet arbitrum optimism base berachain; do
  [ "$ch" = "$CHAIN" ] && continue
  set_env_addr "$ch" "olympus.policies.LZBridgeGateway" "${PLACEHOLDER_GATEWAY[$ch]}"
  log "  $ch -> ${PLACEHOLDER_GATEWAY[$ch]}"
done

start_anvil "$CHAIN"
fund "$DEPLOYER_ADDR"

deploy_sequence "src/scripts/deploy/savedDeployments/lz_bridge_noncanonical.json"

gw="$(env_addr "$CHAIN" olympus.policies.LZBridgeGateway)";            require_addr "$gw" "deployed gateway"
dl="$(env_addr "$CHAIN" olympus.policies.LZEndpointDelegate)";        require_addr "$dl" "deployed delegate"
cf="$(env_addr "$CHAIN" olympus.policies.LZBridgeAndDelegateConfig)"; require_addr "$cf" "deployed config"
pb="$(env_addr "$CHAIN" olympus.periphery.LZCrossChainBridge)";       require_addr "$pb" "deployed periphery bridge"
log "Deployed gateway=$gw delegate=$dl config=$cf periphery=$pb"

# activateGateway deactivates the old bridge in the Kernel without an
# isPolicyActive guard, so it reverts if the old bridge is already inactive.
step "Check old bridge Kernel state"
kernel="$(env_addr "$CHAIN" olympus.Kernel)"
old_bridge="$(env_addr "$CHAIN" olympus.policies.CrossChainBridge)"
old_active="$(cast call "$kernel" 'isPolicyActive(address)(bool)' "$old_bridge" --rpc-url "$RPC")"
log "old CrossChainBridge isPolicyActive=$old_active"
[ "$old_active" = "true" ] || log "WARNING: activateGateway will revert on DeactivatePolicy (old bridge already inactive in Kernel)."

step "Gateway batch (LZBridgeGatewayL2Batch)"
run_batch LZBridgeGatewayL2Batch activateGateway    "$CHAIN"
run_batch LZBridgeGatewayL2Batch grantRoles         "$CHAIN"
run_batch LZBridgeGatewayL2Batch configureAndEnable "$CHAIN"
run_batch LZBridgeGatewayL2Batch wireConfig         "$CHAIN"
run_batch LZBridgeGatewayL2Batch revokeSetupRoles   "$CHAIN"

step "Periphery batch (LZCrossChainBridgeL2Batch)"
run_batch LZCrossChainBridgeL2Batch initializeConfigurator "$CHAIN"
run_batch LZCrossChainBridgeL2Batch setupL2               "$CHAIN"

step "Post-run state"
echo "gateway.isEnabled   = $(cast call "$gw" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "delegate.isEnabled  = $(cast call "$dl" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "config.isEnabled    = $(cast call "$cf" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "periphery.isEnabled = $(cast call "$pb" 'isEnabled()(bool)' --rpc-url "$RPC")"

step "L2 rollout complete for $CHAIN"
log "gateway=$gw delegate=$dl config=$cf periphery=$pb"
