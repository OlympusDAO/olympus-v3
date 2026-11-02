# DepositManagerConfigTimelock.VERSION coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-VERSION`.

Permissionless pure discovery is independent of policy lifecycle and operational readiness.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Discovery

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-VERSION-P01 | Fuzz all callers | true | true | Return major=1,minor=0 without state/dependency reads | Covered: [test][test_whenVersionQueried] |
| DMCT-VERSION-L01 | Fuzz all callers | false | false | Return major=1,minor=0 without state/dependency reads | Covered: [test][test_givenPausedInactive_whenVersionQueried] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_whenVersionQueried]: VERSION.t.sol#L9
[test_givenPausedInactive_whenVersionQueried]: VERSION.t.sol#L17
