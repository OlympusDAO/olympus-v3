# Local dependency patches

Applied by `shell/postinstall.sh` after `forge soldeer update`. Patches are standard unified diffs
applied with `git apply`.

## chainlink-local-029-sender-abi-encode.patch

**Target:** `dependencies/chainlink-local-0.2.9/src/ccip/CCIPLocalSimulatorFork.sol`
(chainlink-local v0.2.9, rev `f8c0efe8685660dac07e08f4558f1b578ae991aa`)

**What it fixes:** in `_executePostV1dot6`, the simulator reconstructs the inbound
`Internal.Any2EVMRampMessage` with `sender: abi.encodePacked(message.sender)` — a 20-byte value.
Real CCIP encodes the sender as 32-byte `abi.encode(address)`: `Internal.Any2EVMRampMessage.sender`
is a `bytes` field that carries one ABI word
(`@chainlink/contracts-ccip/contracts/libraries/Internal.sol`), and Chainlink's own CCIP tests
construct inbound messages exclusively with `sender: abi.encode(<address>)`. The v0.2.9 release
fixed the same 20-vs-32-byte defect for `receiver` and `destTokenAddress` (see `_decodeEVMAddress`
in the same file) but left `sender` unfixed.

**Why:**
`CCIPCrossChainBridge._receiveMessage` (`src/periphery/bridge/CCIPCrossChainBridge.sol:346`) does
`abi.decode(message_.sender, (address))`, which matches what a real v1.6 lane delivers. Under the
unpatched simulator that decode reverts (20 bytes cannot be `abi.decode`d as an address), so fork
tests would fail — or worse, mask the correct trusted-remote check.

**When to remove:** once the pinned chainlink-local version builds `sender` via `abi.encode`.
Then delete:

1. this patch file,
2. this directory if no patches remain,
3. the "Patching chainlink-local" step in `shell/postinstall.sh`.
