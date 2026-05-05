# LZ Bridge Migration Flow

Step-by-step operational sequence for replacing `CrossChainBridge` (LZ V1) with `LZBridgeGateway` + `LZCrossChainBridge` (LZ V2).

Chains: Ethereum, Arbitrum, Optimism, Base, Berachain.

## Prerequisites

- All contracts deployed and addresses recorded in env.json (remote gateway addresses are set as immutables in `LZBridgeActivator` at deployment time).
- Proposal ID set in `LZBridgeSecurityUpgradeProposal.id()` before submission.
- `initialBridgedSupply` filled in `LZBridgeGatewayBatch` args file before step 5.

## Bridge state during migration

| Phase                                          | Old bridge (sendOhm)                   | Old bridge (receive)                       | New bridge (sendOhm)            | New bridge (receive)     |
| ---------------------------------------------- | -------------------------------------- | ------------------------------------------ | ------------------------------- | ------------------------ |
| Before OCG                                     | Active                                 | Active                                     | Disabled                        | Disabled                 |
| After OCG (step 3\)                            | Active                                 | Active                                     | Disabled                        | Enabled, but unreachable |
| During disableOldBridge (step 4\)              | Blocking in progress                   | Still delivers in-flight messages          | Disabled                        | Enabled, but unreachable |
| After initBridgedSupply (step 5\)              | Blocked                                | Still can deliver, but unreachable         | Disabled                        | Enabled, but unreachable |
| After setup for non-canonical chains (step 6\) | L2: Deactivated (Kernel), Eth: Blocked | L2: Deactivated (Kernel), Eth: unreachable | Enabled on non-canonical chains | Enabled                  |
| After Ethereum setup (step 7\)                 | Blocked + Deactivated (Kernel)        | Deactivated (Kernel)                       | Enabled everywhere              | Enabled                  |

Key: `bridgeActive=false` blocks `sendOhm()` but not `lzReceive()`/`receiveMessage()`, so in-flight messages continue to be delivered when `bridgeActive==false`.

## Migration Steps

### 1\. Deploy contracts

Deploy `LZBridgeGateway` and `LZCrossChainBridge` on Ethereum, Arbitrum, Optimism, Base, and Berachain. The `LZCrossChainBridge` constructor takes the gateway address as an argument. Record deployed addresses in env.json and OCG proposal constants.

### 2\. Ethereum pre-OCG setup (MS batch)

**`LZBridgeGatewayBatch.activateGateway()`** — activate `LZBridgeGateway` in the Kernel. The old `CrossChainBridge` remains active, users can continue bridging via the old bridge.

### 3\. OCG Proposal

Execute `LZBridgeSecurityUpgradeProposal`:

1. Grant `bridge_admin` and `bridge_rate_limiter` roles to DAO MS.
2. Grant `bridge_facilitator` role to the LZCrossChainBridge periphery contract.
3. Grant temporary `admin` and `bridge_admin` roles to the LZBridgeActivator contract.
4. Execute `LZBridgeActivator.activate()` which:
   - Pins SendUln302/ReceiveUln302 libraries and sets ULN/Executor config for all remote chains. Dual-DVN verification: LayerZero Labs + Google Cloud for non-Berachain routes, LayerZero Labs + Nethermind for Berachain routes.
   - Sets peers for all remote chains.
   - Sets enforced options: 200,000 gas minimum for lzReceive on each destination.
   - Sets bidirectional rate limits per remote (100,000 OHM outbound, 55,000 OHM inbound, 24-hour window) so traffic is throttled from the moment the gateway is enabled.
   - Enables the LZBridgeGateway policy.
5. Revoke temporary roles from the LZBridgeActivator contract.

After execution the Ethereum gateway is fully configured and enabled, but the periphery `LZCrossChainBridge` is still disabled on all chains — no user traffic flows through the new bridge yet. Old bridges continue operating normally.

### 4\. Stop old bridge traffic

**`LZCrossChainBridgeBatch.disableOldBridge()`** on Ethereum. **`LZCrossChainBridgeL2Batch.disableOldBridge()`** on each non-canonical chain.

This sets `bridgeActive=false` on each old `CrossChainBridge`, which blocks new `sendOhm()` calls. However, `lzReceive()`/`receiveMessage()` remains functional — in-flight messages sent before disable will still be delivered.

Even if users send messages while disableOldBridge is being executed across chains, those messages will still be received on the destination (only sending is blocked, not receiving).

**Wait approximately 3-15 minutes for all in-flight LayerZero V1 messages to be delivered.** This ensures the bridged supply snapshot in step 5 is accurate. Running `calc_bridged_supply.sh` immediately is safe — the script will fail if in-flight messages are detected.

At this point: users cannot bridge via old bridges (send blocked) and cannot bridge via new bridges (LZCrossChainBridge still disabled). This is the migration downtime window.

### 5\. Calculate and set bridged supply on Ethereum

1. **`shell/calc_bridged_supply.sh`** — verifies all old bridges are disabled, checks for in-flight LZ V1 messages and unretried failed messages, cross-checks via LayerZero Scan API, and computes the initial bridged supply (sum of OHM totalSupply across non-canonical chains). Fill the output value into the `LZBridgeGatewayBatch` args file.
2. If the script reports unretried failed messages: **`shell/retry_failed_messages.sh \--account \<name\>`** — retries failed LZ V1 messages by calling `retryMessage()` on each destination bridge. Reads `shell/failed_messages.json` generated in step 1 (payloads are auto-fetched where possible; fill in missing ones from LayerZero Scan or `MessageFailed` event logs). `retryMessage()` is permissionless. After retrying, re-run `calc_bridged_supply.sh` to confirm a clean state.
3. **`LZBridgeGatewayBatch.initBridgedSupply()`** — writes the bridged supply to the new gateway via `increaseBridgedSupply()`. Must be done before non-canonical bridges go live.

### 6\. Configure and activate non-canonical bridges

On each non-canonical chain (Arbitrum, Optimism, Base, Berachain), run in order:

1. **`LZBridgeGatewayL2Batch.activateGateway()`** — deactivate old `CrossChainBridge` in Kernel, activate new `LZBridgeGateway`.
2. **`LZBridgeGatewayL2Batch.grantRoles()`** — grant `bridge_admin`, `bridge_rate_limiter`, `admin`, and `bridge_facilitator` roles. Note whether the script reports that `admin` was granted (vs. already present) — this determines whether step 4 is needed.
3. **`LZBridgeGatewayL2Batch.configureAndEnable()`** — pin LZ V2 libraries, set ULN/Executor config, set peers, set enforced options, set bidirectional rate limits per remote (50,000 OHM outbound to Ethereum and 100,000 OHM outbound to each other non-canonical peer, 110,000 OHM inbound from every peer, 24-hour window), and enable the gateway.
4. **`LZBridgeGatewayL2Batch.revokeSetupRoles()`** _(optional)_ — revoke the `admin` role from the DAO MS. Only run on chains where step 2 granted the role (i.e. the DAO MS did not already have it).
5. **`LZCrossChainBridgeL2Batch.setupL2()`** — enable the periphery bridge (gateway was set in the constructor at deployment).

After this step, non-canonical bridges are live. Users can bridge to/from non-canonical chains. Ethereum bridge periphery is still disabled — users on Ethereum cannot send yet, but Ethereum can receive from non-canonical chains.

### 7\. Activate Ethereum bridge

**`LZCrossChainBridgeBatch.setup()`** — deactivate old `CrossChainBridge` in the Kernel and enable `LZCrossChainBridge`. `LZCrossChainBridge` is a peripheral contract controlled by the DAO MS (its owner).

Migration complete. All bridge traffic now flows through the new LZ V2 contracts.
