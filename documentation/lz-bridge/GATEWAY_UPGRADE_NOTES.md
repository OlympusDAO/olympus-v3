# Gateway Upgrade Notes

## `isReceiveEnabled`

The `LZBridgeGateway.isReceiveEnabled` flag is provided for use during future gateway replacements, so that a disabled old gateway can continue delivering in-flight LZ messages instead of reverting them.

- Managed automatically by `enable()` (sets `true`) and `disable()` (sets `false`).
- Can be set manually via `setIsReceiveEnabled()`, gated to `emergency` / `admin` roles.
- `lzReceive()` checks `isReceiveEnabled` directly; `burnAndSend()` checks `isEnabled` via `onlyEnabled`.

### Expected usage

1. **OCG proposal** calls `oldGateway.disable("")` then `oldGateway.setIsReceiveEnabled(true)` (and enables the new gateway). The old gateway can no longer send but still delivers incoming messages.
2. **DAO MS** reconfigures non-canonical chains at its own pace; in-flight messages continue to arrive at the old gateway.
3. **Old gateway is deactivated in the Kernel** once operations are complete. Calling `setIsReceiveEnabled(false)` is not required — Kernel deactivation is sufficient.
