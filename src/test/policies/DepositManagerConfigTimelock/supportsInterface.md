# DepositManagerConfigTimelock.supportsInterface coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-INTERFACES`.

Permissionless ERC165 discovery must expose the concrete policy, version, both enabler versions,
reEnable, grace-period and both timelock queue interfaces independently of policy state.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Supported and unknown IDs

| ID | Caller | Interface domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-INTERFACES-P01 | Fuzz all callers | IERC165, IVersioned, IEnabler, IEnablerV2, IReEnabler, IGracePeriod, ITimelockBatchQueue, IConfigTimelockBatchQueue, IDepositManagerConfigTimelock | true for each required ID | Covered: [test][test_supportsExpectedInterfaces] |
| DMCT-INTERFACES-I01 | Fuzz all callers | Fuzz bytes4 outside every supported ID; explicit 0xffffffff | false | Covered: [test][test_whenInterfaceIsUnsupported_returnsFalse], [test][test_whenUnknownInterfaceQueried] |

## Lifecycle independence

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-INTERFACES-L01 | Fuzz all callers | false | false | All supported interfaces remain discoverable | Covered: [test][test_givenPausedInactive_whenInterfacesQueried] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_supportsExpectedInterfaces]: supportsInterface.t.sol#L20
[test_whenInterfaceIsUnsupported_returnsFalse]: supportsInterface.t.sol#L62
[test_whenUnknownInterfaceQueried]: supportsInterface.t.sol#L74
[test_givenPausedInactive_whenInterfacesQueried]: supportsInterface.t.sol#L67
