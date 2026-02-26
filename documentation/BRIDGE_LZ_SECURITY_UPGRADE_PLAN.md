# Overview

```
┌──────────────────────────── Source Chain ─────────────────────────────┐

  SENDING OHM (MSG_BRIDGE_OHM)

  User
    │ OHM.approve(LZCrossChainBridge)
    │
    ▼
  LZCrossChainBridge.sendOhm(dst, to, amount)           [onlyEnabled]
    │ OHM.transferFrom(user → Gateway)
    │
    ▼
  LZBridgeGateway.burnAndSend(dst, to, amount,         [onlyFacilitator]
                               refundAddr, params)      [onlyEnabled]
    │ trusted remote validation
    │ MINTR.burnOhm (burns OHM)
    │ if isCanonical: bridgedSupply += amount
    │                 require(bridgedSupply <= cap)
    │
    ▼
  lzEndpoint.send(...) ─────────────────────────────── LayerZero ──►


  SENDING GOVERNANCE (MSG_GOVERNANCE)

  OCG Timelock / Admin
    │
    ▼
  LZBridgeGateway.sendGovernanceMessage(dst,            [onlyAdminRole]
      targets[], values[], payloads[],
      executionReward, refund, adapterParams)
    │ trusted remote validation
    │ (OHM is not affected)
    │ adapterParams airdrops native tokens
    │   to the relay on the destination chain
    │
    ▼
  lzEndpoint.send(...) ─────────────────────────────── LayerZero ──►

└──────────────────────────────────────────────────────────────────────┘


┌─────────────────────────── Destination Chain ─────────────────────────┐

  RECEIVING (common entry point)

  ◄── LayerZero ───
    │
    ▼
  LZBridgeGateway.lzReceive(src, srcAddr, nonce,        [onlyEnabled]
                             payload)                    [msg.sender == endpoint]
    │ trusted remote validation
    │ decodes msgType from payload
    │
    ├── MSG_BRIDGE_OHM ──────────────────────────────────────────────┐
    │     if isCanonical: require(bridgedSupply >= amount)           │
    │                     bridgedSupply -= amount                    │
    │     MINTR.mintOhm(to, amount)                                  │
    │     ✓ OHM delivered to the recipient                           │
    │                                                                │
    ├── MSG_GOVERNANCE ──────────────────────────────────────────────┐
    │     │                                                          │
    │     ▼                                                          │
    │   LZTimelockGovernanceRelay.receiveAction(                     │
    │       targets[], values[], payloads[],                         │
    │       executionReward)                                         │
    │     │ proposalId = hash(targets, values, payloads,             │
    │     │                   executionReward, nonce++)              │
    │     │ readyAt = now + actionDelay                              │
    │     │ stored in _proposals                                     │
    │     │                                                          │
    │     │         ... actionDelay elapses ...                      │
    │     │                                                          │
    │     ▼                                                          │
    │   [Anyone] executeAction(proposalId)              [onlyEnabled] │
    │     │ check: state == Ready                                    │
    │     │ check: address(this).balance >= totalValue               │
    │     │        + executionReward                                  │
    │     │ readyAt = DONE_TIMESTAMP                                 │
    │     │ for each: target.call{value}(data)                       │
    │     │   └─ target checks relay's ROLES                         │
    │     │ transfer executionReward → msg.sender                    │
    │     ✓ Governance action executed, caller rewarded              │
    │                                                                │
    │   [Owner (MS)] cancelAction(proposalId)        [onlyOwner]        │
    │     └─ cancels a Pending or Ready proposal                     │
    │                                                                │
    └────────────────────────────────────────────────────────────────┘

  RETRY (on failure in any path)

  lzReceive stores hash in failedMessages
    │
    ▼
  [Anyone] LZBridgeGateway.retryMessage(...)            [onlyEnabled]
    │ trusted remote re-validation                      [trusted remote]
    │ failedMessages cleared
    │ message re-routed by msgType
    ▼

└──────────────────────────────────────────────────────────────────────┘
```

---

# LZBridgeGateway

Infrastructure Policy. Handles all communication with the LayerZero endpoint, performs OHM mint/burn via MINTR, manages trusted remotes and the bridged supply cap. Routes incoming messages by type: bridge (OHM) or governance.

## Inheritance

```
Policy, PolicyEnabler, ILayerZeroReceiver, ILayerZeroUserApplicationConfig, ILZBridgeGateway, IVersioned
```

## Kernel Dependencies

```
configureDependencies() -> [MINTR, ROLES]

requestPermissions() -> [
    MINTR.mintOhm,
    MINTR.burnOhm,
    MINTR.increaseMintApproval
]
```

## State & Constants

### New

| Variable | Type | Description |
|---|---|---|
| `isCanonical` | `bool immutable` | Canonical chain flag (mainnet). Determines whether `bridgedSupply` tracking and `bridgedSupplyCap` checks are performed. On non-canonical chains (L2), supply tracking is skipped |
| `facilitator` | `address` | Address of `LZCrossChainBridge`. Only this address may call `burnAndSend` |
| `governanceRelay` | `address` | Address of `LZTimelockGovernanceRelay`. Receives `MSG_GOVERNANCE` messages |
| `bridgedSupply` | `uint256` | Current amount of OHM sent to other chains. Only used when `isCanonical == true` |
| `bridgedSupplyCap` | `uint256` | Maximum permitted `bridgedSupply`. Only used when `isCanonical == true` |
| `MSG_BRIDGE_OHM` | `uint8 constant` | Message type: OHM transfer (= 1) |
| `MSG_GOVERNANCE` | `uint8 constant` | Message type: governance action (= 2) |

### Copied from CrossChainBridge

| Variable | Type | Description |
|---|---|---|
| `lzEndpoint` | `ILayerZeroEndpoint immutable` | LayerZero endpoint |
| `ohm` | `ERC20` | OHM token (assigned from MINTR during `configureDependencies`) |
| `trustedRemoteLookup` | `mapping(uint16 => bytes)` | Trusted remote addresses by chain ID |
| `failedMessages` | `mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32)))` | Hash storage for failed messages, used for retry |
| `precrime` | `address` | LZ precrime address (currently unused) |

### Removed

| Variable | Reason |
|---|---|
| `bridgeActive` | Replaced by `isEnabled` from `PolicyEnabler` |

## Functions

### LZ Endpoint (`msg.sender == lzEndpoint`)

| Function | Description |
|---|---|
| `lzReceive(uint16 srcChainId_, bytes srcAddress_, uint64 nonce_, bytes payload_)` | **Copied with modifications.** Checks: `onlyEnabled` (added; fix: in the current contract, `lzReceive` does not check `bridgeActive`), `msg.sender == lzEndpoint`, trusted remote validation — copied. <br><br>Calls `receiveMessage` via a low-level call for error isolation. On failure, stores the payload hash in `failedMessages`. Inside `receiveMessage`, routes by message type: `MSG_BRIDGE_OHM` → bridge processing, `MSG_GOVERNANCE` → forwarded to `governanceRelay`. <br><br>Payload format changed from `abi.encode(to, amount)` to `abi.encode(uint8 msgType, bytes data)` |

`MSG_BRIDGE_OHM` processing on receipt:
- Decodes `data` as `(address to, uint256 amount)`
- If `isCanonical`: checks `bridgedSupply >= amount` (safeguard: cannot receive more OHM than was sent), decreases `bridgedSupply -= amount`
- Executes `MINTR.increaseMintApproval(address(this), amount)` + `MINTR.mintOhm(to, amount)` — mints directly to the recipient

`MSG_GOVERNANCE` processing on receipt:
- Decodes `data` as `(address[] targets, uint256[] values, bytes[] payloads, uint256 executionReward)`
- Calls `ILZTimelockGovernanceRelay(governanceRelay).receiveAction(targets, values, payloads, executionReward)`
- Does not affect OHM or `bridgedSupply`

### Facilitator only (`msg.sender == facilitator`)

| Function | Description |
|---|---|
| `burnAndSend(uint16 dstChainId_, address to_, uint256 amount_, address payable refundAddress_, bytes adapterParams_)` | **New.** Payable. Modifiers: `onlyFacilitator`, `onlyEnabled`. Validates that a trusted remote exists for `dstChainId_`. <br><br>Approves OHM to MINTR and burns via `MINTR.burnOhm(address(this), amount_)` — by this point, OHM has already been transferred to the Gateway's balance by the facilitator. If `isCanonical`: increments `bridgedSupply += amount_`, checks `bridgedSupply <= bridgedSupplyCap`. <br><br>Encodes the payload as `abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_))` and sends via `lzEndpoint.send(...)`, passing `refundAddress_` for native token excess refund and `msg.value` as the gas fee |

### Self-call only (`msg.sender == address(this)`)

| Function | Description |
|---|---|
| `receiveMessage(uint16 srcChainId_, bytes srcAddress_, uint64 nonce_, bytes payload_)` | **Copied with modifications.** Called from `lzReceive` via a low-level call for error isolation. Checks `msg.sender == address(this)`. Performs routing by message type (MSG_BRIDGE_OHM / MSG_GOVERNANCE) |

### Public

| Function | Description |
|---|---|
| `retryMessage(uint16 srcChainId_, bytes srcAddress_, uint64 nonce_, bytes payload_)` | **Copied with modifications.** Hardening: (1) `onlyEnabled` check added, (2) trusted remote re-validation added (fix: in the current contract, retry bypasses trusted remote checks if the trusted remote was removed after the failure), (3) payload hash check — copied. <br><br>Clears the `failedMessages` entry before re-execution. Performs the same message type routing as during initial receipt |
| `estimateSendFee(uint16 dstChainId_, address to_, uint256 amount_, bytes adapterParams_)` | **Copied.** View. Constructs the payload with `MSG_BRIDGE_OHM` and calls `lzEndpoint.estimateFees(...)` |
| `estimateGovernanceFee(uint16 dstChainId_, address[] targets_, uint256[] values_, bytes[] payloads_, uint256 executionReward_, bytes adapterParams_)` | **New.** View. Constructs the payload with `MSG_GOVERNANCE` and calls `lzEndpoint.estimateFees(...)` |

### `admin` Role (`onlyAdminRole`)

| Function | Description |
|---|---|
| `sendGovernanceMessage(uint16 dstChainId_, address[] targets_, uint256[] values_, bytes[] payloads_, uint256 executionReward_, address payable refundAddress_, bytes adapterParams_)` | **New.** Payable. Validates array lengths match and that a trusted remote exists for `dstChainId_`. <br><br>Accepts an `executionReward` to incentivize `executeAction` callers on the destination chain. Native tokens required for `values_` and `executionReward` on the destination can be delivered via `adapterParams` Type 2 airdrop to the relay contract. If the airdropped amount is insufficient, the relay must be funded manually on the destination chain before `executeAction` can succeed. <br><br>Encodes the payload as `abi.encode(MSG_GOVERNANCE, abi.encode(targets_, values_, payloads_, executionReward_))` and sends via `lzEndpoint.send(...)`, passing `refundAddress_` for native token excess refund. Does not affect OHM or `bridgedSupply`. <br><br>Used by the OCG timelock on mainnet to send governance actions to L2 |
| `setFacilitator(address)` | **New.** Allows replacing the facilitator contract address |
| `setGovernanceRelay(address)` | **New.** Sets the governance relay address. May be `address(0)` if governance is not required on the given chain |
| `setBridgedSupply(uint256)` | **New.** Manual assignment of the current `bridgedSupply` value. Required during migration to set the initial value. Only when `isCanonical == true` |
| `setBridgedSupplyCap(uint256)` | **New.** Sets the cap on the maximum outflow. Only when `isCanonical == true` |
| `setTrustedRemote(uint16 srcChainId_, bytes path_)` | **Copied.** `path_ = abi.encodePacked(remoteAddress, localAddress)` |
| `setTrustedRemoteAddress(uint16 remoteChainId_, bytes remoteAddress_)` | **Copied.** Wrapper: constructs the path as `abi.encodePacked(remoteAddress_, address(this))` |
| `setPrecrime(address)` | **Copied.** |

### `bridge_admin` Role (`onlyRole("bridge_admin")`)

| Function | Description |
|---|---|
| `setConfig(uint16 version_, uint16 chainId_, uint256 configType_, bytes config_)` | **Copied.** LZ endpoint configuration |
| `setSendVersion(uint16 version_)` | **Copied.** LZ send version |
| `setReceiveVersion(uint16 version_)` | **Copied.** LZ receive version |
| `forceResumeReceive(uint16 srcChainId_, bytes srcAddress_)` | **Copied.** Unblocks the LZ receive queue. Destroys the transaction permanently — extreme measure |

### Enable/Disable (`PolicyEnabler`)

- `enable(bytes)` — `onlyAdminRole`
- `disable(bytes)` — `onlyEmergencyOrAdminRole`

When disabled: `lzReceive` reverts (inbound mints are blocked), `burnAndSend` reverts (outbound transfers are blocked), `retryMessage` reverts (retry is blocked). This is a fix: disable does not block inbound transfers in the current contract.

### View

| Function | Description |
|---|---|
| `getConfig(uint16, uint16, address, uint256)` | **Copied.** LZ endpoint configuration |
| `getTrustedRemoteAddress(uint16 remoteChainId_)` | **Copied.** |
| `isTrustedRemote(uint16 srcChainId_, bytes srcAddress_)` | **Copied.** |
| `VERSION()` | **New.** `IVersioned`. Returns `(1, 0)` |
| `supportsInterface(bytes4)` | **New.** ERC-165. Supports `ILZBridgeGateway`, `ILayerZeroReceiver`, `IEnabler`, `IVersioned` |

---

# LZCrossChainBridge

Facilitator Periphery. User-facing entry point for sending OHM to other chains. Has no privileged access to the Olympus protocol — operates through `LZBridgeGateway` and ERC20 operations with OHM.

## Inheritance

```
Owned, PeripheryEnabler, IVersioned, ILZCrossChainBridge
```

## Constructor

```
constructor(address ohm_, address owner_) Owned(owner_)
```

Validates both addresses are non-zero. Disabled by default.

## Immutables

| Variable | Type | Description |
|---|---|---|
| `OHM` | `address immutable` | OHM token address. Set in constructor |

## State

| Variable | Type | Description |
|---|---|---|
| `gateway` | `address` | Address of the `LZBridgeGateway` infrastructure contract |

## Functions

### Public

| Function | Description |
|---|---|
| `sendOhm(uint16 dstChainId_, address to_, uint256 amount_)` | **Based on the existing `CrossChainBridge.sendOhm`, with significant modifications.** Payable. Modifier: `onlyEnabled`. The user must have previously approved OHM for this contract. Checks: `amount_ > 0`. <br><br>Instead of a direct burn via MINTR: (1) executes `IERC20(OHM).safeTransferFrom(msg.sender, gateway, amount_)` — transfers OHM from the user to the Gateway, (2) calls `ILZBridgeGateway(gateway).burnAndSend{value: msg.value}(dstChainId_, to_, amount_, payable(msg.sender), bytes(""))` — passes `msg.sender` as `refundAddress_` for native token excess refund to the user |

### Owner only (`onlyOwner`)

| Function | Description |
|---|---|
| `setGateway(address)` | **New.** Sets the `LZBridgeGateway` address. Validates non-zero |

### View

| Function | Description |
|---|---|
| `estimateSendFee(uint16 dstChainId_, address to_, uint256 amount_)` | **Proxy.** Proxies the call to `ILZBridgeGateway(gateway).estimateSendFee(...)` with empty adapter params |
| `VERSION()` | **New.** `IVersioned`. Returns `(1, 0)` |
| `supportsInterface(bytes4)` | **New.** ERC-165. Supports `ILZCrossChainBridge`, `IEnabler`, `IVersioned` |

### Enable/Disable (`PeripheryEnabler`)

- `enable(bytes)` — `onlyOwner`
- `disable(bytes)` — `onlyOwner`

`_onlyOwner()` override checks `msg.sender == owner` (Solmate `Owned`).

When disabled: `sendOhm` reverts. Does not affect the Gateway — inbound messages (`lzReceive`) and retry are handled by the Gateway independently. This allows outbound sending to be paused without blocking receipt.

---

# LZTimelockGovernanceRelay

Periphery contract for executing cross-chain governance actions with a built-in delay (timelock). Receives `MSG_GOVERNANCE` messages from `LZBridgeGateway` and queues them. Once the delay has elapsed, the action may be executed within the execution window. The delay creates a response window in the event of a bridge compromise — the owner (MS) can cancel a suspicious action before it is executed.

Scope is restricted to the roles assigned to this contract's address via the ROLES module. Revoking a role instantly disables the corresponding capability — the next `executeAction` targeting that Policy reverts.

Mechanism: the OCG timelock on mainnet calls `LZBridgeGateway.sendGovernanceMessage(...)`. On L2, `LZBridgeGateway.lzReceive` routes `MSG_GOVERNANCE` to `receiveAction(targets, values, payloads, executionReward)`, where the action is queued with a delay. Once the delay has elapsed, `executeAction(proposalId)` executes each `targets[i].call{value: values[i]}(payloads[i])` on behalf of the relay and transfers `executionReward` to the caller.

## Inheritance

```
PeripheryEnabler, Owned, ILZTimelockGovernanceRelay, IVersioned
```

## Constructor

```
constructor(address owner_, uint256 minDelay_, uint256 maxDelay_) Owned(owner_)
```

`owner_` = DAO Multisig on L2. Authorisation on target Policies is provided through roles assigned to this contract's address in the ROLES module.

## Constants

| Variable | Type | Description |
|---|---|---|
| `DONE_TIMESTAMP` | `uint256 constant` | Sentinel value for completed actions (= 1). Distinguishes Done from Unset (= 0) |
| `MIN_ACTION_DELAY` | `uint256 immutable` | Minimum permitted delay. Set in the constructor |
| `MAX_ACTION_DELAY` | `uint256 immutable` | Maximum permitted delay. Set in the constructor |

## State

All new.

### Configuration

| Variable | Type | Description |
|---|---|---|
| `gateway` | `address` | Address of `LZBridgeGateway`. Only this address may call `receiveAction` |
| `actionDelay` | `uint256` | Delay (seconds) before execution becomes possible. Bounded by `MIN_ACTION_DELAY` .. `MAX_ACTION_DELAY` |
| `executionWindow` | `uint256` | Duration of the execution window (seconds) after the delay has elapsed. Once it expires, the action is considered expired |

### Storage

| Variable | Type | Description |
|---|---|---|
| `_proposals` | `mapping(bytes32 => Proposal)` | Scheduled actions by `proposalId` |
| `_nonce` | `uint256` | Auto-incrementing counter for `proposalId` uniqueness. Allows identical payloads to be queued repeatedly |

## Types

```
struct Proposal {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
    uint256 executionReward;
    uint256 readyAt;    // 0 = Unset, 1 = Done, >1 = readiness timestamp
}
```

```
enum ProposalState { Unset, Pending, Ready, Expired, Done }
```

State determination by `readyAt`:

| State | Condition | Description |
|---|---|---|
| **Unset** | `readyAt == 0` | Proposal does not exist |
| **Pending** | `readyAt > 1 && block.timestamp < readyAt` | Awaiting delay expiry. May be cancelled |
| **Ready** | `block.timestamp >= readyAt && block.timestamp < readyAt + executionWindow` | May be executed or cancelled |
| **Expired** | `block.timestamp >= readyAt + executionWindow` | Expired. Must be re-sent from mainnet |
| **Done** | `readyAt == DONE_TIMESTAMP` | Executed |

## Functions

### LZBridgeGateway only (`msg.sender == gateway`)

| Function | Description |
|---|---|
| `receiveAction(address[] targets_, uint256[] values_, bytes[] payloads_, uint256 executionReward_)` | **New.** Modifiers: `onlyGateway`, `onlyEnabled`. Validates array lengths match. Generates `proposalId = keccak256(abi.encode(targets_, values_, payloads_, executionReward_, _nonce++))`. Stores a `Proposal` with `readyAt = block.timestamp + actionDelay`. <br><br>On revert (relay disabled), the message is stored in `failedMessages` on the Gateway for retry. <br><br>Native tokens needed for `values_` and `executionReward` are expected on the relay's balance at execution time (delivered via `adapterParams` Type 2 airdrop or manual transfer) |

### Public

| Function | Description |
|---|---|
| `executeAction(bytes32 proposalId_)` | **New.** Modifier: `onlyEnabled`. Checks state == Ready. Checks `address(this).balance >= totalValue + executionReward` — if the relay is underfunded, reverts; the relay must be funded (via airdrop or manual transfer) before retrying. Sets `readyAt = DONE_TIMESTAMP` before the calls (checks-effects-interactions: prevents reentrancy). <br><br>Executes each `targets[i].call{value: values[i]}(payloads[i])` on behalf of the relay. Reverts on any call failure — the proposal rolls back to Ready, and the caller may retry within the window. The relay address must hold the required role for the called function on each target. <br><br>On success, transfers `executionReward` to `msg.sender` as compensation for gas costs |

### Owner only (`onlyOwner`)

| Function | Description |
|---|---|
| `cancelAction(bytes32 proposalId_)` | **New.** Cancels a scheduled action. Checks: state == Pending or Ready. Deletes the proposal from `_proposals` |
| `setGateway(address)` | **New.** Sets the `LZBridgeGateway` address |
| `setActionDelay(uint256)` | **New.** Sets the delay. Checks: `>= MIN_ACTION_DELAY` and `<= MAX_ACTION_DELAY`. Does not affect actions already queued |
| `setExecutionWindow(uint256)` | **New.** Sets the execution window |

### Enable/Disable (`PeripheryEnabler`)

- `enable(bytes)` — `onlyOwner`
- `disable(bytes)` — `onlyOwner`

`_onlyOwner()` override checks `msg.sender == owner` (Solmate `Owned`).

When disabled: `receiveAction` reverts (governance messages will be stored in `failedMessages` on the Gateway for retry after re-enable), `executeAction` reverts (Ready proposals cannot be executed; if the window expires during the disable period, they become expired and mainnet must re-send).

### Receive

```
receive() external payable {}
```

Required to accept native token airdrop from LayerZero's `adapterParams` Type 2 delivery and manual funding.

### View

| Function | Description |
|---|---|
| `getProposal(bytes32 proposalId_)` | **New.** Returns the `Proposal` (targets, values, payloads, executionReward, readyAt) |
| `getProposalState(bytes32 proposalId_)` | **New.** Returns the `ProposalState` based on the current `block.timestamp` |
| `VERSION()` | **New.** `IVersioned`. Returns `(1, 0)` |
| `supportsInterface(bytes4)` | **New.** ERC-165. Supports `ILZTimelockGovernanceRelay`, `IEnabler`, `IVersioned` |
