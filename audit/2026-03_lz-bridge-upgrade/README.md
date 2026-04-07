# Olympus LayerZero Bridge Security Upgrade Audit

## Purpose

The purpose of this audit is to review the security upgrade of the Olympus LayerZero cross-chain OHM bridge infrastructure, replacing the existing `CrossChainBridge` policy with a new two-contract architecture: `LZBridgeGateway` (infrastructure policy) and `LZCrossChainBridge` (periphery facilitator, authorized via the `bridge_facilitator` role).

These contracts will be installed in the Olympus V3 "Bophades" system, based on the [Default Framework](https://palm-cause-2bd.notion.site/Default-A-Design-Pattern-for-Better-Protocol-Development-7f8ace6d263c4303b108dc5f8c3055b1).

## Design

The existing `CrossChainBridge` policy (deployed on Ethereum mainnet and Arbitrum) combines user-facing bridging, LayerZero endpoint communication, and OHM mint/burn into a single contract. This upgrade separates concerns into two contracts and introduces several security hardening measures.

The new design splits the bridge into two contracts:

1. **LZBridgeGateway** (Policy) - Infrastructure contract that handles all LayerZero V2 endpoint communication, OHM mint/burn via MINTR, peer management, enforced options, rate limiting, bridged supply tracking, and proxying of LZ V2 endpoint configuration and message management functions for the `bridge_admin` role.
2. **LZCrossChainBridge** (Periphery) - User-facing facilitator contract authorized via the `bridge_facilitator` role. Users approve and send OHM through this contract, which transfers it to the gateway for burning and cross-chain messaging.

```text
User -> LZCrossChainBridge (bridge_facilitator role) -> LZBridgeGateway (policy) -> LZ Endpoint V2 -> [destination]
```

On receive:

```text
LZ Endpoint V2 -> LZBridgeGateway.lzReceive -> validate peer -> mint OHM to recipient
```

Additionally, an OCG proposal and multisig batch scripts handle the on-chain migration: deployment, pre-OCG gateway wiring, OCG execution (LZ V2 config + peers + options + enable gateway), old bridge disablement, bridged supply snapshot, non-canonical chain setup, and Ethereum periphery activation.

## Scope

### In-Scope Contracts

#### Core Contracts

- [src/](../../src)
    - [periphery/](../../src/periphery/)
        - [bridge/](../../src/periphery/bridge/)
            - [LZCrossChainBridge.sol](../../src/periphery/bridge/LZCrossChainBridge.sol) - Facilitator (periphery)
        - [interfaces/](../../src/periphery/interfaces/)
            - [ILZCrossChainBridge.sol](../../src/periphery/interfaces/ILZCrossChainBridge.sol) - Facilitator interface
    - [policies/](../../src/policies/)
        - [bridge/](../../src/policies/bridge/)
            - [LZBridgeGateway.sol](../../src/policies/bridge/LZBridgeGateway.sol) - Gateway infrastructure policy
        - [interfaces/](../../src/policies/interfaces/)
            - [ILZBridgeGateway.sol](../../src/policies/interfaces/ILZBridgeGateway.sol) - Gateway interface
            - [ILZEndpointV2Admin.sol](../../src/policies/interfaces/ILZEndpointV2Admin.sol) - LZ V2 endpoint admin interface

**OApp provenance:** Peer management, endpoint send/receive, and enforced-option logic are ported inline from `@lz-oapp-evm v0.4.1` (OAppCore, OAppSender, OAppReceiver, OAppOptionsType3) because those contracts assume OZ Ownable, incompatible with Bophades Kernel RBAC. `RateLimiter` is the only OApp contract inherited directly (no Ownable dependency); its integration and `_outflow`/`_inflow` overrides are in scope, the base contract itself is not.

#### Deployment & Configuration

These contracts configure and deploy the core contracts. Misconfiguration here (wrong addresses, wrong confirmation counts, incorrect role grants, wrong migration ordering) can undermine the security properties of the core contracts.

- [src/](../../src)
    - [scripts/deploy/](../../src/scripts/deploy/)
        - [DeployV3.s.sol](../../src/scripts/deploy/DeployV3.s.sol) - `deployLZCrossChainBridge()` and `deployLZBridgeGateway()` deployment functions
    - [libraries/](../../src/libraries/)
        - [LZConfigLib.sol](../../src/libraries/LZConfigLib.sol) - Shared LZ V2 constants (endpoints, SendUln302/ReceiveUln302 libraries, DVNs, executor, confirmation counts) and encoding helpers
    - [proposals/](../../src/proposals/)
        - [LZBridgeSecurityUpgradeProposal.sol](../../src/proposals/LZBridgeSecurityUpgradeProposal.sol) - OCG proposal: configures gateway on Ethereum (pins V2 libraries, sets ULN/Executor config, peers, enforced options)
        - [LZBridgeActivator.sol](../../src/proposals/LZBridgeActivator.sol) - OCG activator contract invoked by the proposal; splits LZ V2 configuration across multiple actions to stay within the governance 15-action limit, and carries per-chain DVN routing (e.g. Nethermind DVN for Berachain where Google Cloud DVN is unavailable)
    - [scripts/ops/batches/](../../src/scripts/ops/batches/)
        - [LZBridgeGatewayBatch.sol](../../src/scripts/ops/batches/LZBridgeGatewayBatch.sol) - Ethereum MS batch: `activateGateway` (install in Kernel) and `initBridgedSupply` (delta-based initial supply snapshot, canonical chain only)
        - [LZBridgeGatewayL2Batch.sol](../../src/scripts/ops/batches/LZBridgeGatewayL2Batch.sol) - L2 MS batch split into three entry points to stay within action limits: `activateGateway` (deactivate old bridge, activate new gateway), `grantRoles` (grant `bridge_admin` and related roles), and `configureAndEnable` (configure LZ V2 libraries/ULN/executor, set peers, set enforced options, enable). Each entry point has a matching post-batch `_validate*` check. Inlines the shared LZ V2 configuration helpers and per-chain DVN addresses (previously housed in separate base-class files).
        - [LZCrossChainBridgeBatch.sol](../../src/scripts/ops/batches/LZCrossChainBridgeBatch.sol) - Ethereum MS batch: `disableOldBridge` (post-OCG), `setup` (deactivate old + enable new)
        - [LZCrossChainBridgeL2Batch.sol](../../src/scripts/ops/batches/LZCrossChainBridgeL2Batch.sol) - L2 MS batch: `disableOldBridge`, `setupL2` (enable bridge)

Branch: `lz-bridge-upgrade`

### Previous Audits

You can review previous audits here:

- Spearbit (07/2022)
    - [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/2022-08%20Code4rena.pdf)
- Code4rena Olympus V3 Audit (08/2022)
    - [Repo](https://github.com/code-423n4/2022-08-olympus)
    - [Findings](https://github.com/code-423n4/2022-08-olympus-findings)
- Kebabsec Olympus V3 Remediation and Follow-up Audits (10/2022 - 11/2022)
    - [Remediation Audit Phase 1 Report](https://hackmd.io/tJdujc0gSICv06p_9GgeFQ)
    - [Remediation Audit Phase 2 Report](https://hackmd.io/@12og4u7y8i/rk5PeIiEs)
    - [Follow-on Audit Report](https://hackmd.io/@12og4u7y8i/Sk56otcBs)
- Cross-Chain Bridge by OtterSec (04/2023)
    - [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/Olympus-CrossChain-Audit.pdf)
- Cooler V2 by Electisec (03/2025)
    - [Report](https://storage.googleapis.com/olympusdao-landing-page-reports/audits/Olympus_CoolerV2-Electisec_report.pdf)
    - The PolicyEnabler and PolicyAdmin mix-ins are audited here

## Implementation

### Key Security Improvements Over CrossChainBridge

1. **Bridged supply tracking** (canonical chain only): Tracks outbound OHM (`bridgedSupply`) with an underflow check on inbound receives, preventing unlimited mints from non-canonical chains.
2. **`onlyEnabled` on `lzReceive`**: The original `CrossChainBridge` does not check `bridgeActive` on inbound messages. The new gateway checks `onlyEnabled`, meaning disabling the bridge blocks both inbound and outbound transfers. Note: disabling the bridge does **not** block recovery functions (`skip`, `nilify`, `burn`, `clear`), which are gated by `onlyBridgeAdminOrAdmin` instead of `onlyEnabled`, allowing `bridge_admin` or `admin` to retry or recover messages while the bridge is disabled.
3. **Elimination of custom retry mechanism**: The original `CrossChainBridge` stores failed message hashes in `failedMessages` and exposes a `retryMessage` function that does not re-validate the trusted remote. The new gateway removes this entirely in favour of native LayerZero V2 message delivery, which enforces peer validation on retry and eliminates the risk of replaying messages from removed peers.
4. **Separation of concerns**: The facilitator (`LZCrossChainBridge`) has no MINTR permissions and is authorized via the `bridge_facilitator` role. It merely transfers OHM to the gateway and calls `burnAndSend`. This limits the blast radius if the facilitator is compromised.
5. **Typed message encoding**: Payload format changed from `abi.encode(to, amount)` to `abi.encode(uint8 msgType, bytes data)` to support future message types.
6. **Explicit LZ V2 endpoint configuration**: Migration from default LayerZero V1 configuration to explicitly pinned V2 endpoint configuration (SendUln302/ReceiveUln302 libraries, DVN and Executor config), eliminating the drag-along vulnerability and the proof library substitution attack vector. Verification uses dual-DVN confirmation (LayerZero DVN + Google Cloud DVN).
7. **`bridge_admin` role separation**: `bridge_admin` is the primary operational role for LZ endpoint configuration and recovery. Functions guarded by `onlyBridgeAdminOrAdmin` — `setSendLibrary`, `setReceiveLibrary`, `setReceiveLibraryTimeout`, `setEndpointConfig`, `skip`, `nilify`, `burn`, `clear`, `setBridgedSupply`, `setDelegate`, `setRateLimits`, and `resetRateLimits` — are normally controlled by `bridge_admin`, while `admin` remains available as an emergency/override actor. The `setDelegate` function allows setting an LZ endpoint delegate as a fallback mechanism for future endpoint interface changes not yet proxied by the gateway; by default no delegate is set and all endpoint administration flows through the gateway's own functions.
8. **Enforced Type 3 options**: Replaces LayerZero V1 adapter parameters with enforced Type 3 options that guarantee minimum destination gas per message type. The gateway supports combining enforced options with caller-supplied options at send time.
9. **Per-endpoint rate limiting**: Opt-in rate limiting via `RateLimiter` inheritance. Outbound transfers are enforced against a per-EID limit; inbound transfers reduce the in-flight amount (enabling more outbound), but are not independently capped. The gateway overrides both `RateLimiter._outflow` and `_inflow`: `_outflow` skips unconfigured EIDs (`limit == 0 && window == 0`); `_inflow` short-circuits when `amountInFlight == 0` for the EID, covering unconfigured EIDs and fully-settled configured ones alike.
10. **V2 message recovery primitives**: Replaces the V1 `forceResumeReceive` with native V2 recovery functions (`skip`, `nilify`, `burn`, `clear`), administered by `bridge_admin` or `admin` (via `onlyBridgeAdminOrAdmin`).

### LZ V2 Receiver Callbacks

The gateway implements `ILayerZeroReceiver`:

- **`allowInitializePath(origin)`**: Returns `true` only if the peer for `origin.srcEid` is non-zero and equals `origin.sender`. The explicit zero check prevents a cleared or unset peer from matching a zero sender. Controls which communication paths the LZ V2 endpoint can initialize for this contract.
- **`nextNonce(_, _)`**: Returns `0` — unordered (nonce-independent) delivery, the default per `OAppReceiver` (`@lz-oapp-evm-0.4.1`). Matches the original V1 CrossChainBridge, which also does not enforce message ordering.

### Bridged Supply Tracking

On the canonical chain (Ethereum, `IS_CANONICAL == true`):

- **Outbound** (`burnAndSend`): `bridgedSupply += amount`
- **Inbound** (`_receiveBridgeOhm`): `bridgedSupply -= amount`; reverts if underflow

On non-canonical chains: supply tracking is skipped entirely.

`increaseBridgedSupply` and `decreaseBridgedSupply` are available to `bridge_admin` or `admin` (via `onlyBridgeAdminOrAdmin`) for migration bootstrapping and error recovery. These delta-based functions replaced an earlier absolute `setBridgedSupply` setter to remove the risk of accidentally overwriting live supply state with a stale value.

### Message Flow

#### Sending OHM (Source Chain)

```mermaid
sequenceDiagram
    participant User
    participant LZCrossChainBridge
    participant LZBridgeGateway
    participant MINTR
    participant LZEndpointV2

    User->>LZCrossChainBridge: sendOhm(dstEid, to, amount) + native fee
    LZCrossChainBridge->>LZBridgeGateway: OHM.safeTransferFrom(user, gateway, amount)
    LZCrossChainBridge->>LZBridgeGateway: burnAndSend{value}(dstEid, to, amount, refund, extraOptions)
    LZBridgeGateway->>LZBridgeGateway: validate peer exists for dstEid
    LZBridgeGateway->>LZBridgeGateway: rate limit outflow
    LZBridgeGateway->>LZBridgeGateway: [canonical] bridgedSupply += amount, increaseMintApproval
    LZBridgeGateway->>MINTR: approve + burnOhm(gateway, amount)
    LZBridgeGateway->>LZBridgeGateway: combine enforced + extra options
    LZBridgeGateway->>LZEndpointV2: send(MessagingParams, refundAddr)
    LZBridgeGateway-->>LZBridgeGateway: emit Sent(sender, amount, dstEid, guid)
```

#### Receiving OHM (Destination Chain)

```mermaid
sequenceDiagram
    participant LZEndpointV2
    participant LZBridgeGateway
    participant MINTR
    participant Recipient

    LZEndpointV2->>LZBridgeGateway: lzReceive(origin, guid, message, executor, extraData)
    LZBridgeGateway->>LZBridgeGateway: validate onlyEnabled, endpoint, peer
    LZBridgeGateway->>LZBridgeGateway: decode msgType, route to _receiveBridgeOhm
    LZBridgeGateway->>LZBridgeGateway: [canonical] bridgedSupply -= amount (revert on underflow)
    LZBridgeGateway->>LZBridgeGateway: rate limit inflow
    LZBridgeGateway->>MINTR: [non-canonical] increaseMintApproval + mintOhm(to, amount)
    MINTR->>Recipient: OHM minted
```

### Access Control Summary

#### LZBridgeGateway (Policy)

| Function                   | Access                                                   | Description                                  |
| -------------------------- | -------------------------------------------------------- | -------------------------------------------- |
| `burnAndSend`              | `onlyRole("bridge_facilitator")` + `onlyEnabled`         | Burn OHM and send cross-chain                |
| `lzReceive`                | `onlyEnabled` + `msg.sender == LZ_ENDPOINT` + peer check | Receive LZ V2 messages                       |
| `setPeer`                  | `onlyAdminRole`                                          | Set/clear peer gateway for a remote EID      |
| `setDelegate`              | `onlyBridgeAdminOrAdmin`                                 | Set delegate on LZ endpoint                  |
| `increaseBridgedSupply`    | `onlyBridgeAdminOrAdmin`                                 | Increase bridged supply by delta (canonical) |
| `decreaseBridgedSupply`    | `onlyBridgeAdminOrAdmin`                                 | Decrease bridged supply by delta (canonical) |
| `setEnforcedOptions`       | `onlyAdminRole`                                          | Set enforced Type 3 options per EID/msgType  |
| `setRateLimits`            | `onlyBridgeAdminOrAdmin`                                 | Set rate limit configs per EID               |
| `resetRateLimits`          | `onlyBridgeAdminOrAdmin`                                 | Reset rate limit state (amountInFlight)      |
| `setSendLibrary`           | `onlyBridgeAdminOrAdmin`                                 | Pin send library on LZ endpoint              |
| `setReceiveLibrary`        | `onlyBridgeAdminOrAdmin`                                 | Pin receive library on LZ endpoint           |
| `setReceiveLibraryTimeout` | `onlyBridgeAdminOrAdmin`                                 | Set receive library migration timeout        |
| `setEndpointConfig`        | `onlyBridgeAdminOrAdmin`                                 | Set ULN/Executor config on a message library |
| `skip`                     | `onlyBridgeAdminOrAdmin`                                 | Skip a nonce on the LZ endpoint              |
| `nilify`                   | `onlyBridgeAdminOrAdmin`                                 | Nilify a payload on the LZ endpoint          |
| `burn`                     | `onlyBridgeAdminOrAdmin`                                 | Burn a payload on the LZ endpoint            |
| `clear`                    | `onlyBridgeAdminOrAdmin`                                 | Clear a message on the LZ endpoint           |
| `enable` / `disable`       | `onlyAdminRole` / `onlyEmergencyOrAdminRole`             | PolicyEnabler                                |

#### LZCrossChainBridge (Periphery)

| Function             | Access                 | Description                       |
| -------------------- | ---------------------- | --------------------------------- |
| `sendOhm`            | `onlyEnabled` (public) | User-facing: send OHM cross-chain |
| `setGateway`         | `onlyOwner`            | Set gateway address               |
| `enable` / `disable` | `onlyOwner`            | PeripheryEnabler                  |
