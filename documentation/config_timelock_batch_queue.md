# Config Timelock Batch Queue

`ConfigTimelockBatchQueue` is a base contract for configuration timelocks. It adds conflict
protection and stale-state protection to `TimelockBatchQueue`.

Use this base when a queued action changes configuration that can also change before execution.

## Why this base is needed

A timelock delays a call, but a delay alone does not preserve the assumptions behind that call.
Consider two changes to one fee configuration:

1. Action A queues against the current fee configuration.
2. Action B queues against the same fee configuration.
3. Action B executes first.
4. Action A executes later and overwrites or invalidates the result of Action B.

A direct administrator call creates the same problem. The administrator can change the fee
configuration after Action A queues. Action A then represents intent based on stale state.

Projection can let later actions depend on the expected result of earlier actions. However,
separate batches do not have a global execution order. Projection therefore needs dependency links,
cancellation repair, and strict execution rules.

This base uses a smaller model:

- An unresolved action reserves every configuration domain that it reads or writes.
- Another action cannot reserve the same domain for the same destination.
- Each action records the canonical state of its domains at queue time.
- Execution fails if the destination or canonical state changed.
- Execution or cancellation releases the reservations. Expiry does not release them.

If an action becomes stale, cancel it and queue a new action against the current state.

## What the base guarantees

The base gives a subclass these guarantees:

- Each sub-action owns one or more non-zero configuration keys.
- A scoped key has only one unresolved owner.
- Duplicate scoped keys in one sub-action or batch cause the complete queue transaction to revert.
- A pending conflict reports the action ID that owns the key.
- The destination and all expected state hashes are captured at queue time.
- The destination and hashes are checked immediately before each target dispatch.
- All keys stay reserved during every external call in the batch.
- A later error rolls back earlier target calls and all queue state changes.
- Successful execution and cancellation release all keys and guard records.
- Cleanup fails if an action no longer owns one of its recorded keys.

These guarantees apply to both single-action queues and atomic batches.

## What the base does not guarantee

The base does not provide these behaviors:

- It does not impose an execution order on separate batches.
- It does not queue a change against projected future state.
- It does not permit two unresolved changes to the same scoped key.
- It does not prevent direct configuration changes by another authorized contract.
- It does not release keys when an action expires.
- It does not define proposer, executor, or cancellation authority.
- It does not validate product selectors, payloads, or values.
- It does not dispatch product calls.

The implementing contract owns all product rules and authorization.

## Destination-side config operator

`ConfigTimelockBatchQueue` is the queue-side abstraction. It deliberately does not install itself
as an operator or define how the destination rotates delegated configuration authority. The
separate target-side `ConfigOperatorSingleStep` mix-in provides that behavior for Config contracts
through the shared `IConfigOperator` interface.

The single-step mix-in has these semantics:

- `configOperator` starts at `address(0)`, so delegated configuration is denied by default.
- `setConfigOperator(newOperator)` replaces the operator immediately after authorization. The new
  operator does not perform a separate acceptance transaction.
- Setting `address(0)` revokes delegated access.
- A successful change emits `ConfigOperatorSet`.
- `_authorizeSetConfigOperator()` controls who may rotate or revoke the operator. Its base
  implementation returns false, so the setter denies every caller. A Config contract must
  explicitly override the hook to grant authority and may apply product roles, enabled-state
  requirements, or other lifecycle checks. The hook authorizes the caller rather than validating
  the new operator address.
- Product setters decide whether the configured operator is their only delegated caller or is
  accepted alongside another authority such as `admin`.
- Products that implement ERC-165 should advertise `IConfigOperator` explicitly.

This separation keeps target ownership independent from queue mechanics. A product can use
`ConfigOperatorSingleStep` without `ConfigTimelockBatchQueue`, and a product timelock must still
verify at queue and execution time that it remains the destination's current `configOperator`.

## Mental model

Each guard has four parts.

| Part        | Meaning                                                    | Selected by               |
| ----------- | ---------------------------------------------------------- | ------------------------- |
| Destination | The contract that owns the guarded configuration namespace | `_configDestination`      |
| Local key   | A configuration domain within that destination             | `_configKeys`             |
| Scoped key  | The key that the base reserves                             | The shared base           |
| State hash  | The canonical state that must stay unchanged               | `_currentConfigStateHash` |

The base calculates the scoped key as follows:

```solidity
bytes32 scopedKey = keccak256(abi.encode(destination, localKey));
```

For example, an asset fee domain can use this local key:

```solidity
bytes32 localKey = keccak256(abi.encode(_FEE_CONFIG_DOMAIN, asset));
```

The complete reserved key is then:

```solidity
bytes32 scopedKey = keccak256(abi.encode(destination, localKey));
```

`pendingActionId(scopedKey)` returns the action that owns this key. It returns zero when the key is
free.

### Destination

The destination identifies the configuration namespace. It does not have to equal
`BatchAction.target`, but both addresses are usually the same.

The base stores the destination when the action queues. At execution, it calls
`_configDestination` again. Execution fails if the returned address changed.

A changed destination also creates a new key namespace for new actions. An unresolved action for
destination A does not block the same local key for destination B.

Choose the destination based on the required rotation behavior:

- Return a replaceable contract when each replacement is an independent namespace.
- Return a stable configuration contract when stale actions must keep blocking the logical domain.
- Include other replaceable dependencies in the state hash when their rotation makes intent stale.

### Local keys

A local key identifies the smallest configuration domain that the action reads or writes. Key
design must follow storage dependencies, not only function selectors.

Use the same local key when either action can change an assumption of the other action. Use different
local keys only when both actions are valid in either execution order.

A selector alone is usually not a safe key:

- Two selectors that update the same storage domain must share a key.
- One selector for two independent assets normally needs one key per asset.
- One composite selector can return multiple keys when it affects multiple domains.

The local key must not depend on mutable destination state. Equal validated actions must identify
the same domains regardless of the current configuration.

### State hashes

The state hash is a compare-and-set guard. It records the state that the queued intent assumes.

Include all configuration whose change makes the action stale. Exclude unrelated or deliberately
volatile accounting data.

For example, a debt-cap hash can include the configured cap but exclude live debt. Live debt changes
during normal operation. The destination can validate the proposed cap against live debt during
execution.

The base calls `_currentConfigStateHash` at queue time and before execution. Use one canonical
encoding in this hook. Do not create separate queue-time and execution-time hash functions.

If a sub-action returns multiple local keys, return the state hash for the supplied `key_`. Each
local key gets a separate stored hash.

## Lifecycle

### Queue

For a new batch, the base performs these operations:

1. `TimelockBatchQueue` validates the batch size and assigns the action ID.
2. `_validateConfigQueue` validates queue-wide product rules for the first sub-action.
3. `_validateConfigSubAction` validates each target, selector, payload, and proposed value.
4. `_configDestination` selects the destination for the sub-action.
5. `_configKeys` returns every local key for the sub-action.
6. The base scopes, validates, and reserves each local key.
7. `_currentConfigStateHash` records the canonical state for each local key.
8. `_validateConfigBatch` validates optional rules across the complete batch.
9. `TimelockBatchQueue` stores the actions and emits its queue events.

Any error reverts the complete transaction. No action ID, reservation, or state hash leaks from a
failed queue attempt.

### Execute

For a pending batch, the base performs these operations:

1. `TimelockBatchQueue` validates the action state and timestamps.
2. `_validateExecution` validates product execution rules.
3. The base compares the current destination with the stored destination.
4. The base confirms ownership of every scoped key.
5. The base compares every current state hash with its stored hash.
6. `_executeConfigSubAction` dispatches the product call.
7. Steps 3 through 6 repeat in array order for each sub-action.
8. The base releases all keys only after every dispatch in the complete batch succeeds.
9. `TimelockBatchQueue` removes the stored sub-actions and emits the execution event.

The hash checks occur immediately before each dispatch. If an earlier sub-action changes a later
hash, the later check fails and the complete transaction reverts.

The base keeps every key until the complete batch succeeds. A reentrant target cannot queue any key
owned by the executing batch, including a key belonging to a later sub-action.

### Cancel and expire

`_validateCancellation` defines cancellation authority. After authorization, the shared base
releases every key and removes every guard record.

Expiry is a timestamp condition, not a state transition. An expired action keeps its keys until an
authorized caller cancels it. Every product must provide a cancellation path after disablement and
expiry.

## Implement a subclass

### Start with the base contract

Derive the product timelock from `ConfigTimelockBatchQueue`. Pass the initial delay to the base
constructor. Keep product targets and wiring in the product contract.

```solidity
contract ProductConfigTimelock is ConfigTimelockBatchQueue {
    IProductConfig public immutable CONFIG;

    constructor(
        IProductConfig config_,
        uint48 initialDelay_
    ) ConfigTimelockBatchQueue(initialDelay_) {
        CONFIG = config_;
    }

    // Implement the product and shared hooks described below.
}
```

This outline omits product inheritance, imports, roles, and deployment checks.

### 1. Inventory the supported actions

List each supported selector. For each selector, list these items:

- The target contract.
- The decoded payload fields.
- Every storage field that the action reads.
- Every storage field that the action writes.
- Every external address whose rotation makes the action stale.
- Every execution-time condition that can change normally.

This inventory defines the destination, local keys, and state hashes.

### 2. Define the configuration domains

Group actions when their read or write sets overlap. Define one domain constant for each group.

```solidity
bytes32 internal constant _FEE_CONFIG_DOMAIN = keccak256("PRODUCT_FEE_CONFIG");
bytes32 internal constant _RISK_CONFIG_DOMAIN = keccak256("PRODUCT_RISK_CONFIG");
```

Add the entity identifier when entities are independent:

```solidity
keccak256(abi.encode(_FEE_CONFIG_DOMAIN, asset));
```

An action can own more than one domain:

```solidity
function _configKeys(
    ITimelockBatchQueue.BatchAction memory action_
) internal pure override returns (bytes32[] memory keys) {
    address asset = abi.decode(action_.payload, (address));

    keys = new bytes32[](2);
    keys[0] = keccak256(abi.encode(_FEE_CONFIG_DOMAIN, asset));
    keys[1] = keccak256(abi.encode(_RISK_CONFIG_DOMAIN, asset));
}
```

Do not return duplicate keys. Do not return `bytes32(0)`.

### 3. Select the destination

Return the contract that owns the configuration namespace:

```solidity
function _configDestination(
    ITimelockBatchQueue.BatchAction memory
) internal view override returns (address destination) {
    return address(CONFIG);
}
```

The destination must not be zero. If the hook uses mutable wiring, it must return the current
address. The base then detects a rotation during execution.

### 4. Define each canonical state hash

Read the live configuration and hash the exact state that the action assumes:

```solidity
function _currentConfigStateHash(
    uint64,
    uint256,
    bytes32 localKey_,
    ITimelockBatchQueue.BatchAction memory action_
) internal view override returns (bytes32 stateHash) {
    address asset = abi.decode(action_.payload, (address));

    if (localKey_ == keccak256(abi.encode(_FEE_CONFIG_DOMAIN, asset))) {
        return keccak256(abi.encode(asset, CONFIG.getFeeConfig(asset)));
    }

    if (localKey_ == keccak256(abi.encode(_RISK_CONFIG_DOMAIN, asset))) {
        return keccak256(abi.encode(asset, CONFIG.getRiskConfig(asset)));
    }

    revert UnsupportedConfigKey(localKey_);
}
```

Do not hash a proposed value in place of live state. The hash describes the queue-time pre-state.

### 5. Validate queue requests

Use `_validateConfigQueue` for rules that apply to the complete queue request:

- Proposer authorization.
- Product enablement.
- Required target wiring.

Use `_validateConfigSubAction` for rules that apply to one sub-action:

- Target and selector support.
- Exact payload shape.
- Decoded value bounds.
- Validation of the complete resulting configuration.

Use `_validateConfigBatch` only for rules that span otherwise independent sub-actions. The default
implementation accepts every batch.

### 6. Dispatch the product call

Implement `_executeConfigSubAction` with explicit selector dispatch. Let target errors revert the
complete batch.

Do not make another state-changing external call before the intended dispatch. Such a call can
change state after the shared base completes its hash checks.

### 7. Implement product lifecycle hooks

`ConfigTimelockBatchQueue` does not define product authority or timing. Implement the applicable
`TimelockBatchQueue` hooks:

- `_validateExecution` for execution authority and enabled-state rules.
- `_validateCancellation` for cancellation authority.
- `_validateTimelockDelay` for delay bounds.
- `_executionWindow` for the execution window.
- `_maxBatchSize` when the default batch size is not correct.

Expose product queue helpers that call `_queueAction`. A batch entry point can pass an array directly
to `_queueAction`.

```solidity
function queueSetFeeConfig(
    address asset_,
    FeeConfig calldata config_
) external returns (uint64 actionId) {
    return
        _queueAction(
            address(CONFIG),
            IProductConfig.setFeeConfig.selector,
            abi.encode(asset_, config_)
        );
}
```

### 8. Set the aggregate key limit

By default, `_maxConfigKeysPerBatch` equals `_maxBatchSize`. This is an aggregate gas-safety bound.
It is not a per-sub-action key limit.

Override `_maxConfigKeysPerBatch` when valid composite actions need more total keys:

```solidity
function _maxConfigKeysPerBatch() internal pure override returns (uint256 maximum) {
    return 24;
}
```

Use a constant bound that limits queue, execution, and cleanup gas.

### 9. Advertise the interfaces

The shared base advertises `ITimelockBatchQueue` and `IConfigTimelockBatchQueue` through ERC-165.
If the product overrides `supportsInterface`, include `super.supportsInterface(interfaceId_)`.

The product interface does not need to inherit `IConfigTimelockBatchQueue`. Generic tools can cast
the concrete contract to the shared interface.

## Hook reference

| Hook                       | Required | Implementing contract responsibility                              |
| -------------------------- | -------- | ----------------------------------------------------------------- |
| `_validateConfigQueue`     | Yes      | Validate the proposer, lifecycle, and common wiring               |
| `_validateConfigSubAction` | Yes      | Validate the target, selector, payload, and proposed result       |
| `_configDestination`       | Yes      | Select the non-zero configuration namespace                       |
| `_configKeys`              | Yes      | Return all non-zero local domains that the action reads or writes |
| `_currentConfigStateHash`  | Yes      | Hash the live canonical state for the supplied local key          |
| `_validateConfigBatch`     | No       | Validate invariants across independent sub-actions                |
| `_executeConfigSubAction`  | Yes      | Dispatch the validated product action                             |
| `_maxConfigKeysPerBatch`   | No       | Set the aggregate key bound for composite actions                 |

The shared base owns the parent queue, execution, completion, and cancellation hooks. A subclass
cannot override those shared bookkeeping paths. Product customization uses only the hooks in this
section and the remaining `TimelockBatchQueue` lifecycle hooks.

## Burner Loans example

Burner Loans selects its immutable `BurnerLoansConfig` policy as `_configDestination`. In this
section, `config` means `address(_BURNER_LOANS_CONFIG)`.

The facility is not the selected destination. It is a one-time dependency returned by
`_BURNER_LOANS_CONFIG.facility()`: after Config stores a non-zero facility, `setFacility` rejects
every later binding. Burner Loans includes that immutable facility in each canonical state hash so
the action is bound to the Config instance's deployment wiring.

The facility component therefore cannot independently make a queued action stale. Replacing the
Burner Loans stack requires a fresh Config and facility pair; the new Config address creates a new
destination namespace without rotating the old Config's facility.

| Action                        | Local key                                                 | Scoped ownership key                      | Canonical state hash                                          |
| ----------------------------- | --------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------- |
| `setAssetFeeConfig`           | `keccak256(abi.encode(_FEE_CONFIG_DOMAIN, asset))`         | `keccak256(abi.encode(config, localKey))` | `keccak256(abi.encode(facility, asset, completeFeeConfig))`   |
| `setAssetRiskConfig`          | `keccak256(abi.encode(_RISK_CONFIG_DOMAIN, asset))`        | `keccak256(abi.encode(config, localKey))` | `keccak256(abi.encode(facility, asset, riskAndTermFields))`   |
| `setAssetDebtCap`             | `keccak256(abi.encode(_DEBT_CAP_DOMAIN, asset))`           | `keccak256(abi.encode(config, localKey))` | `keccak256(abi.encode(facility, asset, configuredDebtCap))`   |
| `setAssetOriginationsEnabled` | `keccak256(abi.encode(_ASSET_ORIGINATIONS_DOMAIN, asset))` | `keccak256(abi.encode(config, localKey))` | `keccak256(abi.encode(facility, asset, originationsEnabled))` |

The risk hash excludes collateral decimals, debt cap, and origination state. The risk setter does
not change or depend on those fields.

The debt-cap hash excludes live market debt. Live debt changes during normal operation. The target
validates the proposed cap against live debt during execution.

Fee, risk, debt-cap, and origination actions for one asset use independent keys. They can coexist in
one batch because their canonical domains do not overlap.

Two partial fee updates for one asset use the same fee key. Two partial risk updates use the same
risk key. Cancel and replace the existing action when another same-domain update is required.

## Observability

`IConfigTimelockBatchQueue` exposes the shared guard state:

- `pendingActionId(scopedKey)` returns the unresolved owner.
- `getQueuedConfigDestination(actionId, index)` returns the queue-time destination.
- `getQueuedConfigStateCount(actionId, index)` returns the guard count for a sub-action.
- `getQueuedConfigState(actionId, index, guardIndex)` returns a scoped key and expected hash.
- `maxConfigKeysPerBatch()` returns the aggregate batch limit.

`ConfigStateQueued` records the action ID, sub-action index, scoped key, destination, and expected
hash. The terminal execution or cancellation event proves that cleanup completed atomically.

## Required tests

Test the shared guarantees and the product rules separately. Product tests do not need to duplicate
all shared bookkeeping tests.

Add product tests for these cases:

- Every selector returns the documented destination, keys, and state hashes.
- Every unsupported target, selector, payload, and value reverts.
- Same-domain actions conflict within one batch and across batches.
- Independent domains queue and execute in both orders.
- Every relevant direct state change makes the action stale.
- An unrelated or volatile state change does not make the action stale.
- A destination rotation prevents execution.
- A later sub-action error rolls back earlier product calls.
- Execution and cancellation release all product keys.
- Expiry retains all product keys until cancellation.
- Cancellation remains available while the product is disabled.
- Reentrant calls cannot reserve a key that the executing batch owns.
- ERC-165 reports the product and shared capability interfaces.

Add shared-base tests when the base behavior itself changes. The shared suite covers zero keys,
duplicate keys, ownership mismatches, cleanup, destination changes, aggregate limits, and atomic
rollback.

## Common mistakes

### Keys are too narrow

Two actions use different keys even though one changes state that the other hash assumes. The
actions can queue together, but one execution order reverts.

Use the same key or return all affected keys from the composite action.

### Keys are too broad

Independent assets or domains share one key. Safe actions then block each other.

Add the independent entity to the local key or separate the domains.

### A key depends on mutable state

The same payload returns different local keys after a state change. The stored reservation no
longer represents the action domain.

Derive local keys only from stable domain constants and validated action data.

### The state hash includes volatile accounting

Normal operation makes queued actions stale. For example, live debt movement invalidates every
queued debt-cap update.

Remove volatile accounting from the hash. Keep its execution-time validation in the destination.

### The state hash omits a dependency

A direct change alters the meaning or validity of queued intent, but execution still succeeds.

Include that dependency in the canonical hash or give it another owned key.

### Cancellation is unavailable after expiry

Expired actions keep their keys. If no authorized cancellation path remains, those keys stay locked.

Make cancellation available after expiry and during product disablement.

### Separate batches depend on execution order

Permissionless execution can run ready batches in either order. The shared base does not provide
FIFO ordering.

Put ordered calls in one atomic batch. If queue-time state depends on an earlier result, queue the
later action after the earlier action executes.
