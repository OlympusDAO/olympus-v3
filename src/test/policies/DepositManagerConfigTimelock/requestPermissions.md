# DepositManagerConfigTimelock.requestPermissions coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-PERMISSIONS`.

Permissionless pure discovery is independent of policy lifecycle and operational readiness.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Discovery

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-PERMISSIONS-P01 | Fuzz all callers | true | true | Empty permissions array; authority is DM's selected configOperator | Covered: [test][test_whenPermissionsRequested] |
| DMCT-PERMISSIONS-L01 | Fuzz all callers | false | false | Empty permissions array; authority is DM's selected configOperator | Covered: [test][test_givenPausedInactive_whenPermissionsRequested] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_whenPermissionsRequested]: requestPermissions.t.sol#L10
[test_givenPausedInactive_whenPermissionsRequested]: requestPermissions.t.sol#L21
