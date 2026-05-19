# Gateway Upgrade Notes

## `isReceiveEnabled`

The `LZBridgeGateway.isReceiveEnabled` flag is provided for use during future gateway replacements, so that a disabled old gateway can continue delivering in-flight LZ messages instead of reverting them.

- Managed automatically by `enable()` (sets `true`) and `disable()` (sets `false`).
- Can be set manually via `setIsReceiveEnabled()`, gated to `emergency` / `admin` roles.

### Expected usage

1. **OCG proposal** calls `oldGateway.disable("")` then `oldGateway.setIsReceiveEnabled(true)` (and enables the new gateway). The old gateway can no longer send but still delivers incoming messages.
2. **DAO MS** reconfigures non-canonical chains at its own pace; in-flight messages continue to arrive at the old gateway.
3. **Old gateway is deactivated in the Kernel** once operations are complete. Calling `setIsReceiveEnabled(false)` is not required — Kernel deactivation is sufficient.

## Timelock-gated configuration via `LZBridgeAndDelegateConfig`

After bootstraps, the `LZBridgeAndDelegateConfig` policy is expected to be the sole entry point for configuration of the bridge stack:

- On `LZBridgeGateway` and `LZEndpointDelegate` every `bridge_configurator`-gated mutator only accepts callers holding that role; the role is expected to be granted exclusively to the policy. The contracts themselves do not enforce a timelock; the timelock is the policy's queue.
- The `LZEndpointDelegate` inbound-channel management primitives (`skip`, `nilify`, `burn`, `clear`) are the exception: they are gated directly to `bridge_admin` / `admin`.
- On the periphery `LZCrossChainBridge` the `configurator`-gated setters (`setGateway`, `setReEnabler`, `setGracePeriod`, `setConfigurator`) only accept the address pinned in the `configurator` variable, which is expected to be the policy.

Operators do not call these mutators directly. The flow is: submit the gateway / delegate / facilitator mutator(s) as sub-actions of a single `queue([...])` batch on the config policy (a single-element batch behaves like one timelocked action; multiple sub-actions execute atomically), then call `executeQueuedAction` after the policy's timelock has elapsed. The emergency role can cancel a queued action at any time before execution. The policy's own configuration (target slots, timelock delay) is rotated through the typed `queueSetTargetGateway` / `queueSetTargetDelegate` / `queueSetTargetFacilitator` / `queueSetTimelockDelay` helpers; `queue` rejects self-targeted sub-actions.

The one-shot exceptions are `LZBridgeGateway.initializeBridgedSupply` (kept under `bridge_admin` / `admin` so the DAO MS can write the initial bridged supply immediately after OCG) and the bootstrap call to `LZCrossChainBridge.setConfigurator` (kept under the owner so the configurator variable can be seeded post-deploy). After both bootstrap calls and the corresponding role / configurator grants, the policy's timelock queue is the only path for the `bridge_configurator`-gated and `configurator`-gated mutators; the delegate inbound-channel management primitives (`skip`, `nilify`, `burn`, `clear`) remain directly callable by `bridge_admin` / `admin`.
