#!/usr/bin/env bash
# End-to-end Ethereum (canonical) rollout of the LayerZero bridge on a mainnet
# Anvil fork.
#
# Flow:
#   1. Deploy the canonical set (gateway, delegate, periphery bridge, config,
#      activator) and sync addresses into the OCG proposal registry.
#   2. Pre-OCG (DAO MS as Kernel executor): activate gateway + delegate via the
#      real batch, then activate the config policy.
#   3. Grant the timelock the admin + bridge_admin roles the proposal expects.
#   4. OCG: replay LZBridgeSecurityUpgradeProposal actions from the timelock
#      (roles, delegate enable, LZBridgeActivator.activate, role rewire, config
#      enable). The proposal actions are executed directly from the timelock via
#      impersonation; no governance vote is simulated and no OHM is minted.
#   5. Post-OCG (DAO MS): initBridgedSupply, periphery initializeConfigurator,
#      periphery setup.
#
# Usage:
#   ./run-ethereum.sh [--port 8545] [--supply <uint>] [--keep-fork]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

CHAIN="mainnet"
TIMELOCK="0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39"
INITIAL_BRIDGED_SUPPLY="1000000000000" # 1000 OHM at 9 decimals; any positive test value

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; RPC="http://localhost:${PORT}"; shift 2;;
    --supply) INITIAL_BRIDGED_SUPPLY="$2"; shift 2;;
    --keep-fork) KEEP_FORK="true"; shift;;
    *) die "unknown argument: $1";;
  esac
done

# executeOnAnvilFork.sh health-checks http://localhost:8545 explicitly.
[ "$PORT" = "8545" ] || die "the OCG proposal step requires --port 8545"

cd "$REPO_ROOT"
load_dotenv
backup_tracked_files
trap cleanup EXIT

# Stand-in L2 gateways consumed by the activator constructor and stored as peers.
step "Inject placeholder L2 gateways"
for ch in arbitrum optimism base berachain; do
  set_env_addr "$ch" "olympus.policies.LZBridgeGateway" "${PLACEHOLDER_GATEWAY[$ch]}"
  log "  $ch -> ${PLACEHOLDER_GATEWAY[$ch]}"
done

step "Set initialBridgedSupply=$INITIAL_BRIDGED_SUPPLY"
tmp="$(mktemp)"
jq --argjson v "$INITIAL_BRIDGED_SUPPLY" \
  '(.functions[] | select(.name == "initBridgedSupply").args.initialBridgedSupply) = $v' \
  "$REPO_ROOT/$SUPPLY_ARGS" > "$tmp"
mv "$tmp" "$REPO_ROOT/$SUPPLY_ARGS"

start_anvil "$CHAIN"
fund "$DEPLOYER_ADDR"
fund "$TIMELOCK"

deploy_sequence "src/scripts/deploy/savedDeployments/lz_bridge_canonical.json"

gw="$(env_addr mainnet olympus.policies.LZBridgeGateway)";            require_addr "$gw" gateway
dl="$(env_addr mainnet olympus.policies.LZEndpointDelegate)";        require_addr "$dl" delegate
cf="$(env_addr mainnet olympus.policies.LZBridgeAndDelegateConfig)"; require_addr "$cf" config
pb="$(env_addr mainnet olympus.periphery.LZCrossChainBridge)";       require_addr "$pb" periphery
ac="$(env_addr mainnet olympus.periphery.LZBridgeActivator)";        require_addr "$ac" activator
log "Deployed gateway=$gw delegate=$dl config=$cf periphery=$pb activator=$ac"

step "Sync addresses.json (proposal registry)"
set_registry_addr olympus-policy-lz-bridge-gateway             "$gw"
set_registry_addr olympus-policy-lz-endpoint-delegate          "$dl"
set_registry_addr olympus-policy-lz-bridge-and-delegate-config "$cf"
set_registry_addr olympus-periphery-lz-cross-chain-bridge      "$pb"
set_registry_addr olympus-lz-bridge-activator                  "$ac"

step "Pre-OCG: activate policies in the Kernel (DAO MS)"
run_batch LZBridgeGatewayBatch activateGateway mainnet
activate_policy mainnet "$cf"

# Grant the timelock the roles the proposal assumes are already present. The
# grant is sent from the current RolesAdmin admin; if that is not the timelock,
# hand the RolesAdmin admin to the timelock first so the proposal's own role
# grants (sent from the timelock) are accepted.
step "Grant admin + bridge_admin to the timelock"
roles_mod="$(env_addr mainnet olympus.modules.OlympusRoles)"
roles_admin="$(env_addr mainnet olympus.policies.RolesAdmin)"
admin_role="$(cast format-bytes32-string admin)"
bridge_admin_role="$(cast format-bytes32-string bridge_admin)"
radmin="$(cast call "$roles_admin" 'admin()(address)' --rpc-url "$RPC")"
log "RolesAdmin.admin = $radmin ; timelock = $TIMELOCK"
if [ "${radmin,,}" != "${TIMELOCK,,}" ]; then
  log "Handing RolesAdmin admin to the timelock"
  cast_send_impersonated "$radmin" "$roles_admin" "pushNewAdmin(address)" "$TIMELOCK"
  cast_send_impersonated "$TIMELOCK" "$roles_admin" "pullNewAdmin()"
  radmin="$TIMELOCK"
fi
for role in "$admin_role" "$bridge_admin_role"; do
  has="$(cast call "$roles_mod" 'hasRole(address,bytes32)(bool)' "$TIMELOCK" "$role" --rpc-url "$RPC")"
  if [ "$has" != "true" ]; then
    cast_send_impersonated "$radmin" "$roles_admin" "grantRole(bytes32,address)" "$role" "$TIMELOCK"
    log "  granted $role to the timelock"
  fi
done

step "OCG: execute LZBridgeSecurityUpgradeProposal from the timelock"
RPC_URL="$RPC" src/scripts/proposals/executeOnAnvilFork.sh \
  --file src/proposals/LZBridgeSecurityUpgradeProposal.sol \
  --contract LZBridgeSecurityUpgradeProposalScript \
  2>&1 | tee "$LOG_DIR/proposal.log"

step "Post-OCG: bridged supply + periphery (DAO MS)"
run_batch LZBridgeGatewayBatch initBridgedSupply mainnet "$SUPPLY_ARGS"
run_batch LZCrossChainBridgeBatch initializeConfigurator mainnet
run_batch LZCrossChainBridgeBatch setup mainnet

step "Post-run state"
echo "gateway.isEnabled     = $(cast call "$gw" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "delegate.isEnabled    = $(cast call "$dl" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "config.isEnabled      = $(cast call "$cf" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "periphery.isEnabled   = $(cast call "$pb" 'isEnabled()(bool)' --rpc-url "$RPC")"
echo "activator.isActivated = $(cast call "$ac" 'isActivated()(bool)' --rpc-url "$RPC")"
echo "gateway.bridgedSupply = $(cast call "$gw" 'bridgedSupply()(uint256)' --rpc-url "$RPC")"

step "Ethereum rollout complete"
log "gateway=$gw delegate=$dl config=$cf periphery=$pb activator=$ac"
