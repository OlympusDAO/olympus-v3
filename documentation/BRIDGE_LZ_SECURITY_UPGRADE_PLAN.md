# Overview

```
┌──────────────────────────── Source Chain ─────────────────────────────┐

  SENDING OHM (MSG_BRIDGE_OHM)

  User
    │ OHM.approve(LZCrossChainBridge)
    │
    ▼
  LZCrossChainBridge.sendOhm(dstEid, to, amount)              [onlyEnabled]
    │ OHM.transferFrom(user → Gateway)
    │
    ▼
  LZBridgeGateway.burnAndSend(dstEid, to, amount,            [onlyFacilitator]
                               refundAddr, extraOptions)       [onlyEnabled]
    │ peer validation
    │ rate limit outflow
    │ if IS_CANONICAL: bridgedSupply += amount
    │                  require(bridgedSupply <= cap)
    │ MINTR.burnOhm (burns OHM)
    │ combine enforced + extra options (Type 3)
    │
    ▼
  LZ Endpoint V2.send(MessagingParams) ──────────────────── LayerZero V2 ──►

└──────────────────────────────────────────────────────────────────────┘


┌─────────────────────────── Destination Chain ─────────────────────────┐

  RECEIVING

  ◄── LayerZero V2 ───
    │
    ▼
  LZBridgeGateway.lzReceive(origin, guid,                     [onlyEnabled]
                             message, executor, extraData)     [msg.sender == LZ_ENDPOINT]
    │ peer validation (origin.sender == peers[origin.srcEid])
    │ decodes msgType from payload
    │
    ├── MSG_BRIDGE_OHM ──────────────────────────────────────────────┐
    │     if IS_CANONICAL: require(bridgedSupply >= amount)          │
    │                      bridgedSupply -= amount                   │
    │     rate limit inflow                                          │
    │     MINTR.increaseMintApproval + mintOhm(to, amount)           │
    │     ✓ OHM delivered to the recipient                           │
    └────────────────────────────────────────────────────────────────┘

  FAILED MESSAGE RECOVERY (LZ V2 Native)

  The gateway does not implement custom retry logic. Failed messages
  are handled by the LayerZero V2 endpoint natively. The bridge_admin
  role has access to recovery primitives:

  - skip(srcEid, sender, nonce)              Skip a nonce
  - nilify(srcEid, sender, nonce, hash)      Invalidate a payload
  - burn(srcEid, sender, nonce, hash)        Destroy a payload permanently
  - clear(origin, guid, message)             Clear a verified but unexecuted message

└──────────────────────────────────────────────────────────────────────┘
```

---

# LZBridgeGateway

Infrastructure Policy. Handles all communication with the LayerZero V2 endpoint, performs OHM mint/burn via MINTR, manages peers, enforces Type 3 options, rate limits transfers, and tracks bridged supply on the canonical chain. Implements `ILayerZeroReceiver` for V2 endpoint callbacks.

## Inheritance

```
Policy, PolicyEnabler, RateLimiter, ILayerZeroReceiver, ILZEndpointV2Admin, ILZBridgeGateway, IVersioned
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

### Constants

| Variable | Type | Description |
|---|---|---|
| `MSG_BRIDGE_OHM` | `uint8 constant` | Message type: OHM transfer (= 1) |
| `_BRIDGE_OHM_DATA_LENGTH` | `uint256 constant` | Expected byte length of ABI-encoded (address, uint256) bridge payload (= 64) |
| `_OPTION_TYPE_3` | `uint16 constant` | Type 3 option type identifier (= 3) |
| `_BRIDGE_ADMIN_ROLE` | `bytes32 constant` | Role keycode for bridge admin operations (= "bridge_admin") |

### Immutables

| Variable | Type | Description |
|---|---|---|
| `LZ_ENDPOINT` | `address immutable` | LayerZero V2 endpoint address |
| `IS_CANONICAL` | `bool immutable` | Canonical chain flag (Ethereum). Determines whether `bridgedSupply` tracking and `bridgedSupplyCap` checks are performed |

### State

| Variable | Type | Description |
|---|---|---|
| `MINTR` | `MINTRv1` | Bophades module for minting and burning OHM (set in `configureDependencies`) |
| `ohm` | `address` | OHM token address (set from MINTR during `configureDependencies`) |
| `facilitator` | `address` | Address of `LZCrossChainBridge`. Only this address may call `burnAndSend` |
| `bridgedSupply` | `uint256` | Current amount of OHM sent to other chains (canonical only) |
| `bridgedSupplyCap` | `uint256` | Maximum permitted `bridgedSupply` (canonical only) |
| `peers` | `mapping(uint32 => bytes32)` | Peer gateway addresses by endpoint ID |
| `enforcedOptions` | `mapping(uint32 => mapping(uint16 => bytes))` | Enforced Type 3 options by EID and message type |

### Removed (vs CrossChainBridge)

| Variable | Reason |
|---|---|
| `bridgeActive` | Replaced by `isEnabled` from `PolicyEnabler` |
| `trustedRemoteLookup` | Replaced by `peers` mapping (V2 uses bytes32 peer addressing) |
| `failedMessages` | Removed; LZ V2 handles message retry natively |
| `precrime` | Removed; not used in V2 architecture |
| `lzEndpoint` (V1) | Replaced by `LZ_ENDPOINT` immutable (V2 endpoint) |

## Functions

### LZ Endpoint V2 (`ILayerZeroReceiver`)

| Function | Description |
|---|---|
| `lzReceive(Origin origin_, bytes32 guid_, bytes message_, address, bytes)` | Entry point for inbound LZ V2 messages. Checks: `onlyEnabled`, `msg.sender == LZ_ENDPOINT`, peer validation (`peers[origin_.srcEid] == origin_.sender`). Calls `_decodeAndRoute` which decodes the message type and routes to the appropriate handler. Currently only `MSG_BRIDGE_OHM` is supported; unknown types revert. |
| `allowInitializePath(Origin origin_)` | Returns `true` if `origin_.sender` matches the peer for `origin_.srcEid`. Used by the LZ V2 endpoint to determine if a path should be initialized. |
| `nextNonce(uint32, bytes32)` | Returns 0 (unordered delivery). |

`MSG_BRIDGE_OHM` processing on receipt (`_receiveBridgeOhm`):
- Validates payload length equals `_BRIDGE_OHM_DATA_LENGTH` (64 bytes)
- Decodes `data` as `(address to, uint256 amount)`
- If `IS_CANONICAL`: checks `bridgedSupply >= amount` (safeguard: cannot receive more OHM than was sent), decreases `bridgedSupply -= amount` (unchecked, underflow guarded by the preceding check)
- Rate limits inflow via `_inflow(srcEid_, amount)`
- Executes `MINTR.increaseMintApproval(address(this), amount)` + `MINTR.mintOhm(to, amount)` — mints directly to the recipient

### Facilitator only (`msg.sender == facilitator`)

| Function | Description |
|---|---|
| `burnAndSend(uint32 dstEid_, address to_, uint256 amount_, address payable refundAddress_, bytes extraOptions_)` | Payable. Modifiers: `onlyFacilitator`, `onlyEnabled`. Validates `to_` is non-zero and that a peer exists for `dstEid_`. Rate limits outflow. If `IS_CANONICAL`: increments `bridgedSupply += amount_`, checks `bridgedSupply <= bridgedSupplyCap`. Approves OHM to MINTR and burns via `MINTR.burnOhm(address(this), amount_)`. Encodes the payload as `abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_))`, combines enforced + extra options, and sends via `LZ_ENDPOINT.send(MessagingParams(...), refundAddress_)`. Zero-amount validation is the facilitator's responsibility. |

### `admin` Role (`onlyAdminRole`)

| Function | Description |
|---|---|
| `setPeer(uint32 eid_, bytes32 peer_)` | Sets the peer gateway address for a remote EID. Pass `bytes32(0)` to clear. |
| `setFacilitator(address)` | Sets the facilitator contract address. Reverts on zero address. |
| `setBridgedSupplyCap(uint256)` | Sets the cap on maximum outflow. Only when `IS_CANONICAL == true`. |
| `setEnforcedOptions(EnforcedOptionParam[])` | Sets enforced Type 3 options for specific EID/msgType combinations. Each option must begin with the Type 3 prefix. |
| `setRateLimits(RateLimitConfig[])` | Sets rate limit configurations per destination EID. |

### `bridge_admin` Role (`onlyRole("bridge_admin")`)

| Function | Description |
|---|---|
| `setBridgedSupply(uint256)` | Manual assignment of the current `bridgedSupply` value. Required during migration to set the initial value and for error-recovery scenarios. Only when `IS_CANONICAL == true`. |
| `setDelegate(address)` | Sets the delegate on the LZ endpoint, authorizing it to configure endpoint settings on behalf of this contract. Pass `address(0)` to clear. |
| `resetRateLimits(uint32[])` | Resets rate limit state (amountInFlight) for given EIDs without modifying limit or window. |
| `setSendLibrary(uint32 eid_, address lib_)` | Pins send library for a destination EID on the LZ endpoint. |
| `setReceiveLibrary(uint32 eid_, address lib_, uint256 gracePeriod_)` | Pins receive library for a source EID on the LZ endpoint. |
| `setReceiveLibraryTimeout(uint32 eid_, address lib_, uint256 expiry_)` | Sets receive library timeout for migration. |
| `setEndpointConfig(address lib_, SetConfigParam[] params_)` | Sets ULN/Executor config on a message library. |
| `skip(uint32 srcEid_, bytes32 sender_, uint64 nonce_)` | Skips a nonce for a source path. |
| `nilify(uint32 srcEid_, bytes32 sender_, uint64 nonce_, bytes32 payloadHash_)` | Invalidates a specific payload. |
| `burn(uint32 srcEid_, bytes32 sender_, uint64 nonce_, bytes32 payloadHash_)` | Permanently destroys a payload. |
| `clear(Origin origin_, bytes32 guid_, bytes message_)` | Clears a verified but unexecuted inbound message. |

### Enable/Disable (`PolicyEnabler`)

- `enable(bytes)` — `onlyAdminRole`
- `disable(bytes)` — `onlyEmergencyOrAdminRole`

When disabled: `lzReceive` reverts (inbound mints are blocked), `burnAndSend` reverts (outbound transfers are blocked). This is a fix: the original `CrossChainBridge` does not block inbound transfers when disabled.

### View

| Function | Description |
|---|---|
| `estimateSendFee(uint32 dstEid_, address to_, uint256 amount_, bytes extraOptions_)` | Constructs the payload with `MSG_BRIDGE_OHM`, combines options, and calls `LZ_ENDPOINT.quote(...)`. |
| `combineOptions(uint32 eid_, uint16 msgType_, bytes extraOptions_)` | Returns the combined enforced + caller-provided options for a given EID and message type. |
| `VERSION()` | `IVersioned`. Returns `(1, 0)`. |
| `supportsInterface(bytes4)` | ERC-165. Supports `ILZBridgeGateway`, `ILZEndpointV2Admin`, `ILayerZeroReceiver`, `IVersioned`. |

### Rate Limiter Override

The gateway overrides `_outflow` to skip rate limiting for unconfigured EIDs (where `limit == 0 && window == 0`), making rate limiting opt-in rather than mandatory.

### Enforced Options

The gateway combines enforced options with caller-provided extra options via `_combineOptions`:
- If no enforced options exist, returns whatever the caller supplied.
- If no caller options exist, returns enforced options.
- If both exist, validates caller options are Type 3, strips the 2-byte Type 3 prefix from the caller options, and concatenates with enforced options.
- Reverts if caller options are malformed (< 2 bytes) or not Type 3.

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

Validates both addresses are non-zero. Starts disabled; must be explicitly enabled after configuration.

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
| `sendOhm(uint32 dstEid_, address to_, uint256 amount_)` | Payable. Modifier: `onlyEnabled`. Checks: `amount_ > 0`. Executes `IERC20(OHM).safeTransferFrom(msg.sender, gateway, amount_)` — transfers OHM from the user to the Gateway, then calls `ILZBridgeGateway(gateway).burnAndSend{value: msg.value}(dstEid_, to_, amount_, payable(msg.sender), bytes(""))` — passes `msg.sender` as `refundAddress_` and empty extra options. |

### Owner only (`onlyOwner`)

| Function | Description |
|---|---|
| `setGateway(address)` | Sets the `LZBridgeGateway` address. Validates non-zero. |

### View

| Function | Description |
|---|---|
| `estimateSendFee(uint32 dstEid_, address to_, uint256 amount_)` | Proxies to `ILZBridgeGateway(gateway).estimateSendFee(...)` with empty extra options. |
| `VERSION()` | `IVersioned`. Returns `(1, 0)`. |
| `supportsInterface(bytes4)` | ERC-165. Supports `ILZCrossChainBridge`, `IVersioned`. |

### Enable/Disable (`PeripheryEnabler`)

- `enable(bytes)` — `onlyOwner`
- `disable(bytes)` — `onlyOwner`

`_onlyOwner()` override checks `msg.sender == owner` (Solmate `Owned`).

When disabled: `sendOhm` reverts. Does not affect the Gateway — inbound messages (`lzReceive`) are handled by the Gateway independently. This allows outbound sending to be paused without blocking receipt.
