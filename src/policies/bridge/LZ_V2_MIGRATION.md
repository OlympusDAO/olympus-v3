# LZBridgeGateway: V1 → V2 Endpoint Migration Scope

## Context

The current `LZBridgeGateway` uses **LayerZero Endpoint V1** with **ULN301** (a V2-compatible MessageLib registered on V1). This document scopes migrating to **LayerZero Endpoint V2** with native `OApp` inheritance, primarily to gain access to V2's superior testing infrastructure.

## What Changes

| Area | V1 (Current) | V2 (Target) | Effort |
|------|-------------|-------------|--------|
| **Base contract** | `ILayerZeroReceiver` + `ILayerZeroUserApplicationConfig` | `OApp` (= OAppSender + OAppReceiver) | Medium |
| **Chain IDs** | `uint16` chainId (101, 110, 111, 184) | `uint32` EID (30101, 30110, 30111, 30184) | Low |
| **Peer config** | `setTrustedRemote(uint16, bytes)` — 40-byte packed path | `setPeer(uint32, bytes32)` — zero-padded address | Low |
| **Send** | `ILayerZeroEndpoint.send{value}(chainId, trustedRemote, payload, ...)` | `_lzSend(dstEid, message, options, MessagingFee, refund)` | Medium |
| **Receive** | `lzReceive(uint16, bytes, uint64, bytes)` + manual `msg.sender == endpoint` check | `_lzReceive(Origin, bytes32, bytes, address, bytes)` — peer check built-in | Medium |
| **Fee estimation** | `endpoint.estimateFees(chainId, app, payload, false, adapterParams)` | `_quote(dstEid, message, options, false)` → `MessagingFee` | Low |
| **Failed messages** | Custom `failedMessages` mapping + `retryMessage()` | Built into protocol — no `NonblockingLzApp` needed | **Simplification** |
| **Version pinning** | `setSendVersion()` / `setReceiveVersion()` | `endpoint.setSendLibrary()` / `setReceiveLibrary()` with address | Low |
| **DVN/Executor config** | `setConfig(version, chainId, configType, bytes)` via ULN301 | `endpoint.setConfig(oapp, libAddress, SetConfigParam[])` — same DVN model, cleaner API | Medium |
| **Options** | `adapterParams` (Type 1/2, currently empty `bytes("")`) | `OptionsBuilder` library (Type 3) | Low |

## What Stays the Same

- **Core business logic**: burn/mint OHM, message routing, bridged supply cap — untouched
- **Policy/Kernel integration**: all Default Framework code unchanged
- **DVN setup**: same DVNs (LZ Labs + Google Cloud), same confirmation counts
- **Periphery contract** (`LZCrossChainBridge`): only interface changes for fee estimation signature
- **Payload format**: `abi.encode(MSG_BRIDGE_OHM, abi.encode(to_, amount_))` — stays the same

## What Gets Simpler

1. **No more `NonblockingLzApp` pattern** — V2 handles failed messages at protocol level, so the custom `failedMessages` mapping, `retryMessage()`, and the try-catch self-call in `lzReceive` can all be removed
2. **Peer validation is built-in** — OApp checks `peers[srcEid] == sender` before calling `_lzReceive()`, removing manual validation
3. **No drag-along vulnerability** — V2 uses explicit library registration, eliminating the version-pinning workaround

## Files to Modify

| File | Change Type |
|------|------------|
| `src/policies/bridge/LZBridgeGateway.sol` | **Rewrite LZ layer** — inheritance, send, receive, config |
| `src/policies/bridge/interfaces/ILZBridgeGateway.sol` | Update function signatures (uint16→uint32, bytes→bytes32) |
| `src/libraries/LZConfigLib.sol` | Update chain IDs (uint16→uint32 EIDs), config encoding for V2 |
| `src/periphery/bridge/LZCrossChainBridge.sol` | Update fee estimation call signature |
| `src/proposals/LZBridgeSecurityUpgradeProposal.sol` | Update config calls |
| All batch scripts (`LZBridgeGatewayBatch`, `L2Batch`, `OCGSimulation`) | Update config calls |
| `src/test/policies/bridge/LZBridgeGateway.t.sol` | **Rewrite** using `TestHelper` + `EndpointV2Mock` |
| `src/test/policies/bridge/LZBridgeGatewayFork*.t.sol` | Update for V2 endpoint addresses |

## V1 → V2 API Mapping

### Send

```solidity
// V1
ILayerZeroEndpoint(LZ_ENDPOINT).send{value: msg.value}(
    dstChainId_,                                          // uint16
    trustedRemote,                                        // abi.encodePacked(remote, local)
    payload_,
    refundAddress_,
    address(0),                                           // ZRO payment
    adapterParams_                                        // bytes("")
);

// V2
_lzSend(
    dstEid_,                                              // uint32
    payload_,
    options_,                                             // OptionsBuilder encoded
    MessagingFee(msg.value, 0),
    refundAddress_
);
```

### Receive

```solidity
// V1
function lzReceive(
    uint16 srcChainId_,
    bytes calldata srcAddress_,
    uint64 nonce_,
    bytes calldata payload_
) external {
    require(msg.sender == LZ_ENDPOINT);
    // manual trusted remote check
    // try-catch self-call for non-blocking
}

// V2
function _lzReceive(
    Origin calldata _origin,       // { srcEid, sender, nonce }
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal override {
    // peer check already done by OApp
    // just process the message
}
```

### Peer Configuration

```solidity
// V1
trustedRemoteLookup[chainId] = abi.encodePacked(remoteAddress, address(this));

// V2
setPeer(eid, bytes32(uint256(uint160(remoteAddress))));
```

### Fee Estimation

```solidity
// V1
(uint256 nativeFee, ) = ILayerZeroEndpoint(LZ_ENDPOINT).estimateFees(
    dstChainId_, address(this), payload_, false, adapterParams_
);

// V2
MessagingFee memory fee = _quote(dstEid_, payload_, options_, false);
// fee.nativeFee, fee.lzTokenFee
```

### DVN/Executor Config

```solidity
// V1 (via ULN301)
ILayerZeroEndpoint(LZ_ENDPOINT).setConfig(
    version, chainId, CONFIG_TYPE_ULN, abi.encode(ulnConfig)
);

// V2 (via MessageLib)
SetConfigParam[] memory params = new SetConfigParam[](1);
params[0] = SetConfigParam(eid, CONFIG_TYPE_ULN, abi.encode(ulnConfig));
ILayerZeroEndpointV2(endpoint).setConfig(address(this), sendLibAddress, params);
```

## V2 Endpoint IDs

| Chain | V1 chainId (uint16) | V2 EID (uint32) |
|-------|---------------------|-----------------|
| Ethereum | 101 | 30101 |
| Arbitrum | 110 | 30110 |
| Optimism | 111 | 30111 |
| Base | 184 | 30184 |

## Testing Gains

With V2 you get:

- **`TestHelper.sol`** — `setUpEndpoints(4, LibraryType.UltraLightNode)` spins up 4 mock endpoints with mock DVNs + Executors
- **`verifyPackets(dstEid, dstAddress)`** — simulates DVN verification + executor delivery in a single call
- **Full cross-chain message relay in unit tests** — no forks needed for basic flow testing
- **Testnet infrastructure** — Sepolia, Arb Sepolia, OP Sepolia, Base Sepolia all have active V2 endpoints + DVNs

## Interoperability Note

V1 apps using ULN301 can **interoperate** with V2 apps using ULN302. This means incremental migration is possible — deploy V2 gateway alongside V1, test on testnets, then switch over. No big-bang required.

## Security Considerations

1. **Drag-along vulnerability**: Eliminated in V2 (explicit library registration replaces version-number model)
2. **Peer validation**: Built into OApp — simpler, less room for error
3. **Failed message handling**: Protocol-level in V2 — removes custom retry logic and associated attack surface
4. **Bridged supply cap**: Must survive migration without losing accounting; payload format is unchanged so cap logic is unaffected
5. **DVN configuration**: Same dual-DVN model (LZ Labs + Google Cloud) carries over; verify addresses on V2 endpoint

## TODO

- [ ] Install LayerZero V2 OApp dependency (`@layerzerolabs/oapp-evm`)
- [ ] Install LayerZero V2 test helpers (`@layerzerolabs/test-devtools-evm-foundry`)
- [ ] Rewrite `LZBridgeGateway.sol` LZ integration layer (inherit OApp, update send/receive/config)
- [ ] Update `ILZBridgeGateway.sol` interface (uint16→uint32, bytes→bytes32, remove failed message types)
- [ ] Update `LZConfigLib.sol` (V1 chainIds→V2 EIDs, V2 config encoding)
- [ ] Update `LZCrossChainBridge.sol` periphery (fee estimation signature)
- [ ] Rewrite unit tests using `TestHelper` + `EndpointV2Mock`
- [ ] Add cross-chain relay unit tests (send on chain A → verify → receive on chain B)
- [ ] Update fork tests for V2 endpoint addresses
- [ ] Update batch scripts and proposal for V2 config calls
- [ ] Test on Sepolia testnets with real V2 infrastructure
- [ ] Security review of V2 integration layer
