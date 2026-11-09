# LZ Bridge Migration Flow

Step-by-step operational sequence for replacing `CrossChainBridge` (LZ V1) with `LZBridgeGateway` + `LZEndpointDelegate` + `LZCrossChainBridge` + `LZBridgeAndDelegateConfig` (LZ V2).

The `LZBridgeAndDelegateConfig` policy is expected to hold the `bridge_configurator` role on the gateway and the LZ endpoint delegate, and to be pinned as the `configurator` of the periphery bridge. After bootstrap, every `bridge_configurator`-gated mutator on the gateway / delegate and every configurator-gated setter on the periphery bridge is reached only through the policy's timelock queue.

Chains: Ethereum, Arbitrum, Optimism, Base, Berachain.

## Prerequisites

- All contracts (`LZBridgeGateway`, `LZEndpointDelegate`, `LZCrossChainBridge`, `LZBridgeAndDelegateConfig`, and on Ethereum `LZBridgeActivator`) deployed and addresses recorded in env.json (remote gateway addresses are set as immutables in `LZBridgeActivator` at deployment time).
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

Deploy `LZBridgeGateway`, `LZEndpointDelegate`, and `LZCrossChainBridge` on Ethereum, Arbitrum, Optimism, Base, and Berachain. The gateway and the periphery bridge both take a `graceSeconds` argument (default `86400` in `lz_bridge_canonical.json` / `lz_bridge_noncanonical.json`) that defines the maximum window after a `disable` during which `reEnable()` may be called — i.e. an upper bound on the re-enable window, not a minimum wait. The `LZCrossChainBridge` constructor additionally takes the gateway address and the re-enabler address (set to the DAO MS by `DeployV3.deployLZCrossChainBridge()`). `LZEndpointDelegate` takes the gateway address and the LayerZero V2 endpoint address as immutables; its sequence entry has no args (see `deployLZEndpointDelegate()`). Record deployed addresses in env.json and OCG proposal constants.

### 2\. Ethereum pre-OCG setup (MS batch)

**`LZBridgeGatewayBatch.activateGateway()`** — activate `LZBridgeGateway`, `LZEndpointDelegate`, and `LZBridgeAndDelegateConfig` in the Kernel. The old `CrossChainBridge` remains active, users can continue bridging via the old bridge.

### 3\. OCG Proposal

Execute `LZBridgeSecurityUpgradeProposal`:

1. Grant `bridge_admin` and `bridge_rate_limiter` roles to the DAO MS.
2. Grant `manager` role to the DAO MS — required so the DAO MS can call `LZBridgeGateway.reEnable()` after a disable, within the grace window.
3. Grant `bridge_facilitator` role to the LZCrossChainBridge periphery contract.
4. Grant temporary `admin`, `bridge_admin`, and `bridge_configurator` roles to the LZBridgeActivator contract. `bridge_configurator` is required to drive the `bridge_configurator`-gated setters on the gateway and the LZ endpoint delegate during setup without going through the (not-yet-installed) config policy timelock.
5. Enable the `LZEndpointDelegate` policy so the OApp-authorized endpoint setters reached by the activator (`setSendLibrary`, `setReceiveLibrary`, `setEndpointConfig`) pass the policy's `givenEnabled` gate.
6. Execute `LZBridgeActivator.activate()` which:
   - Sets the `LZEndpointDelegate` policy as the gateway's LayerZero endpoint delegate. This is the steady-state delegate, not revoked after activation; subsequent OApp-authorized endpoint operations (libraries, ULN/Executor config, message recovery) are forwarded through `LZEndpointDelegate`.
   - Pins SendUln302/ReceiveUln302 libraries and sets ULN/Executor config for all remote chains, forwarded through `LZEndpointDelegate`. Every route requires four DVNs: LayerZero Labs, Canary, Nethermind, plus Google Cloud for non-Berachain routes or Horizen for routes that touch Berachain (where Google Cloud is unavailable). No optional DVNs (explicit NIL sentinel, `optionalDVNCount == type(uint8).max`) so the OApp config does not inherit LayerZero's EID-level default.
   - Sets peers for all remote chains on the gateway.
   - Sets enforced options on the gateway: 200,000 gas minimum for lzReceive on each destination.
   - Sets bidirectional rate limits per remote on the gateway (100,000 OHM outbound, 55,000 OHM inbound, 24-hour window) so traffic is throttled from the moment the gateway is enabled.
   - Enables the `LZBridgeGateway` policy.
7. Revoke the temporary `admin`, `bridge_admin`, and `bridge_configurator` roles from the `LZBridgeActivator` contract.
8. Enable the `LZBridgeAndDelegateConfig` policy so subsequent `queue` / `queueSet*` and `executeQueuedAction` calls are accepted.
9. Grant the permanent `bridge_configurator` role to the `LZBridgeAndDelegateConfig` policy. From this point on, every `bridge_configurator`-gated mutator on the gateway and the LZ endpoint delegate is reached only through the policy's timelock queue.

After execution the Ethereum gateway is fully configured and enabled, but the periphery `LZCrossChainBridge` is still disabled on all chains — no user traffic flows through the new bridge yet. Old bridges continue operating normally.

### 4\. Stop old bridge traffic

> Note: this guide documents the full migration flow including stopping the old bridge. The old `CrossChainBridge` is already disabled, so this step is a no-op in the current rollout and is kept here for completeness.

**`LZCrossChainBridgeBatch.disableOldBridge()`** on Ethereum. **`LZCrossChainBridgeL2Batch.disableOldBridge()`** on each non-canonical chain.

This sets `bridgeActive=false` on each old `CrossChainBridge`, which blocks new `sendOhm()` calls. However, `lzReceive()`/`receiveMessage()` remains functional — in-flight messages sent before disable will still be delivered.

Even if users send messages while disableOldBridge is being executed across chains, those messages will still be received on the destination (only sending is blocked, not receiving).

**Wait approximately 3-15 minutes for all in-flight LayerZero V1 messages to be delivered.** This ensures the bridged supply snapshot in step 5 is accurate. Running `calc_bridged_supply.sh` immediately is safe — the script will fail if in-flight messages are detected.

At this point: users cannot bridge via old bridges (send blocked) and cannot bridge via new bridges (LZCrossChainBridge still disabled). This is the migration downtime window.

### 5\. Calculate and set bridged supply on Ethereum

1. **`shell/calc_bridged_supply.sh`** — verifies all old bridges are disabled, checks for in-flight LZ V1 messages and unretried failed messages, cross-checks via LayerZero Scan API, and computes the initial bridged supply (sum of OHM totalSupply across non-canonical chains). Fill the output value into the `LZBridgeGatewayBatch` args file.
2. If the script reports unretried failed messages: **`shell/retry_failed_messages.sh \--account \<name\>`** — retries failed LZ V1 messages by calling `retryMessage()` on each destination bridge. Reads `shell/failed_messages.json` generated in step 1 (payloads are auto-fetched where possible; fill in missing ones from LayerZero Scan or `MessageFailed` event logs). `retryMessage()` is permissionless. After retrying, re-run `calc_bridged_supply.sh` to confirm a clean state.
3. **`LZBridgeGatewayBatch.initBridgedSupply()`** — writes the bridged supply to the new gateway via the one-shot `initializeBridgedSupply()` bootstrap. Must be done before non-canonical bridges go live.

### 6\. Configure and activate non-canonical bridges

On each non-canonical chain (Arbitrum, Optimism, Base, Berachain), run in order:

1. **`LZBridgeGatewayL2Batch.activateGateway()`** — deactivate old `CrossChainBridge` in Kernel, activate new `LZBridgeGateway`, `LZEndpointDelegate`, and `LZBridgeAndDelegateConfig`.
2. **`LZBridgeGatewayL2Batch.grantRoles()`** — grant `bridge_admin`, `bridge_rate_limiter`, `manager`, `admin`, `bridge_facilitator`, and a temporary `bridge_configurator` (handed off to the config policy in step 4) to the DAO MS. Note whether the script reports that `admin` was granted (vs. already present) — this determines whether step 5 is needed.
3. **`LZBridgeGatewayL2Batch.configureAndEnable()`** — enable the `LZEndpointDelegate` policy, point the gateway's LZ endpoint delegate at it, pin LZ V2 libraries, set ULN/Executor config via `LZEndpointDelegate`, set peers, set enforced options, set bidirectional rate limits per remote (50,000 OHM outbound to Ethereum and 100,000 OHM outbound to each other non-canonical peer, 110,000 OHM inbound from every peer, 24-hour window), and enable the gateway.
4. **`LZBridgeGatewayL2Batch.wireConfig()`** — revoke the temporary `bridge_configurator` role from the DAO MS, grant the permanent `bridge_configurator` role to the `LZBridgeAndDelegateConfig` policy, and enable the policy so subsequent `queue` / `queueSet*` and `executeQueuedAction` calls are accepted. After this step every `bridge_configurator`-gated mutator on the gateway and the LZ endpoint delegate is reached only through the config's timelock queue.
5. **`LZBridgeGatewayL2Batch.revokeSetupRoles()`** _(optional)_ — revoke the `admin` role from the DAO MS. Only run on chains where step 2 granted the role (i.e. the DAO MS did not already have it).
6. **`LZCrossChainBridgeL2Batch.initializeConfigurator()`** — one-shot owner call pinning the periphery bridge's `configurator` variable at the `LZBridgeAndDelegateConfig` policy. After this, the configurator-gated setters (`setGateway`, `setReEnabler`, `setGracePeriod`) on the periphery bridge only accept the policy, so the calls go through the config's timelock queue.
7. **`LZCrossChainBridgeL2Batch.setupL2()`** — enable the periphery bridge (gateway was set in the constructor at deployment).

After this step, non-canonical bridges are live. Users can bridge to/from non-canonical chains. Ethereum bridge periphery is still disabled — users on Ethereum cannot send yet, but Ethereum can receive from non-canonical chains.

### 7\. Initialize the configurator and activate Ethereum bridge

1. **`LZCrossChainBridgeBatch.initializeConfigurator()`** — one-shot owner call pinning the Ethereum periphery bridge's `configurator` variable at the `LZBridgeAndDelegateConfig` policy. Required for the same reason as on L2: future configurator-gated setters (`setGateway`, `setReEnabler`, `setGracePeriod`) on the periphery bridge only accept the policy, so the calls go through the config's timelock queue.
2. **`LZCrossChainBridgeBatch.setup()`** — deactivate old `CrossChainBridge` in the Kernel and enable `LZCrossChainBridge`. `LZCrossChainBridge` is a peripheral contract controlled by the DAO MS (its owner).

Migration complete. All bridge traffic now flows through the new LZ V2 contracts.
