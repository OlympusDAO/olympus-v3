# DepositManagerConfigTimelock.queueDisableAssetPeriod coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-DISABLE-PERIOD`.

DMCT is the timelock and DM its immutable DepositManager. Defaults: both policies are active
in their shared Kernel and enabled; DM selects DMCT as configOperator; the asset is configured.
Accepted proposers hold ADMIN_ROLE or DEPOSIT_MANAGER_ADMIN_ROLE, including overlap.
Unauthorized fuzzing excludes every holder of either role and retains zero.

Typed queues form one sub-action. Admission order is DMCT enabled → DMCT active → DM active
→ proposer role → selected config operator → DM enabled → product validation → pending key.
The next ID increment rolls back on rejection. Every successful queue stores the exact proposer,
target, selector, payload and pre-state hash, reserves its destination-scoped key, and consumes
one uint64 action ID. Target configuration is applied only by later execution.
Times are uint48 seconds: Q=queuedAt, T=Q+1 day, E=T+3 days. Values use raw asset units.

Asset-period keys hash the asset, uint8 period and operator under the period domain.
The tuple must already exist. Zero/unregistered tuples fail InvalidAssetPeriod rather than
the route-creation validators. Pre-state hashes isConfigured, isEnabled and current DM.configOperator(). Enable and disable
share the same key. Periods span 1..MAX8 when the tuple is configured.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Execution / effects | Test |
| --- | --- | --- | --- |
| DMCT-QUEUE-DISABLE-PERIOD-A01 | Fuzz ADMIN-only, manager-only and overlapping grants | Queue exact target selector/payload; preserve target state; independently assert current target operator in stored pre-state | Covered: [test][test_givenAdminOnly_whenTypedActionQueued], [test][test_givenManagerOnly_whenTypedActionQueued], [test][test_givenBothRoles_whenTypedActionQueued] |
| DMCT-QUEUE-DISABLE-PERIOD-A02 | Fuzz callers outside both permitted roles | NotAuthorised(); Unchanged | Covered: [test][test_whenTypedActionCallerUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-DISABLE-PERIOD-L01 | ADMIN | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-L02 | ADMIN | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenManagerPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-L03 | ADMIN | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-L04 | ADMIN | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenManagerInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-D01 | ADMIN | true | true | true | true | Config operator rotated: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenOperatorRotated_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-L05 | ADMIN | true | true | true | true | Normal queue after reEnable or Kernel reactivation | Covered: [test][test_givenReEnabled_whenTypedActionQueued], [test][test_givenReactivated_whenTypedActionQueued] |

## Tuple validation and period domain

| ID | Caller | Tuple / period | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-DISABLE-PERIOD-I01 | ADMIN | Fuzz absent operator/period tuple | DepositManager_InvalidAssetPeriod(asset,period,operator) | Covered: [test][test_whenRouteAbsent_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-I02 | Manager | Tuple already in requested enabled state | DepositManager_AssetPeriodDisabled(asset,period,operator) | Covered: [test][test_givenAssetPeriodIsDisabled_whenDisableIsQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-N01 | ADMIN | Fuzz configured period 1..MAX8 | Queue exact selector and uint8 payload | Covered: [test][test_givenEnabledPeriod_queuesAndExecutesDisable], [test][test_whenConfiguredPeriodSpansFullRange] |
| DMCT-QUEUE-DISABLE-PERIOD-P01 | Manager; fuzz executor | Tuple in opposite state | Queue then execute exact enabled-state transition | Covered: [test][test_givenEnabledPeriod_queuesAndExecutesDisable] |

## Conflicts, independence and drift

| ID | Caller | Existing queue / drift | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-DISABLE-PERIOD-P02 | Manager | Duplicate pending disable | ConfigKeyPending(key,owner) | Covered: [test][test_givenPendingDisable_whenSamePeriodChangeIsQueued_reverts] |
| DMCT-QUEUE-DISABLE-PERIOD-P03 | Manager | Different period | Independent key; queue succeeds | Covered: [test][test_givenPendingDisable_whenDifferentPeriodIsQueued_succeeds] |
| DMCT-QUEUE-DISABLE-PERIOD-P04 | Manager | Different asset or operator | Independent keys; both actions execute | Covered: [test][test_givenPendingDisable_whenDifferentAssetIsQueued_executesBoth], [test][test_givenPendingDisable_whenDifferentOperatorIsQueued_executesBoth] |
| DMCT-QUEUE-DISABLE-PERIOD-N02 | Manager | Configured MAX8 period | Queue and execute exact maximum seed | Covered: [test][test_whenDepositPeriodIsUint8Max_whenConfigured_executesDisable] |
| DMCT-QUEUE-DISABLE-PERIOD-D02 | Any executor | Enabled flag changed after queue | ConfigStateChanged; retain pending action | Covered: [test][test_givenQueuedDisable_whenPeriodChanges_executionRevertsAsStale] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenTypedActionQueued]: ./queueDisableAssetPeriod.t.sol#L233
[test_givenManagerOnly_whenTypedActionQueued]: ./queueDisableAssetPeriod.t.sol#L248
[test_givenBothRoles_whenTypedActionQueued]: ./queueDisableAssetPeriod.t.sol#L263
[test_whenTypedActionCallerUnauthorized_reverts]: ./queueDisableAssetPeriod.t.sol#L278
[test_givenTimelockPaused_whenTypedActionQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L291
[test_givenManagerPaused_whenTypedActionQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L304
[test_givenTimelockInactive_whenTypedActionQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L317
[test_givenManagerInactive_whenTypedActionQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L333
[test_givenOperatorRotated_whenTypedActionQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L349
[test_givenReEnabled_whenTypedActionQueued]: ./queueDisableAssetPeriod.t.sol#L366
[test_givenReactivated_whenTypedActionQueued]: ./queueDisableAssetPeriod.t.sol#L382
[test_whenRouteAbsent_reverts]: ./queueDisableAssetPeriod.t.sol#L417
[test_givenAssetPeriodIsDisabled_whenDisableIsQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L55
[test_givenEnabledPeriod_queuesAndExecutesDisable]: ./queueDisableAssetPeriod.t.sol#L72
[test_whenConfiguredPeriodSpansFullRange]: ./queueDisableAssetPeriod.t.sol#L399
[test_givenPendingDisable_whenSamePeriodChangeIsQueued_reverts]: ./queueDisableAssetPeriod.t.sol#L86
[test_givenPendingDisable_whenDifferentPeriodIsQueued_succeeds]: ./queueDisableAssetPeriod.t.sol#L95
[test_givenPendingDisable_whenDifferentAssetIsQueued_executesBoth]: ./queueDisableAssetPeriod.t.sol#L116
[test_givenPendingDisable_whenDifferentOperatorIsQueued_executesBoth]: ./queueDisableAssetPeriod.t.sol#L158
[test_whenDepositPeriodIsUint8Max_whenConfigured_executesDisable]: ./queueDisableAssetPeriod.t.sol#L189
[test_givenQueuedDisable_whenPeriodChanges_executionRevertsAsStale]: ./queueDisableAssetPeriod.t.sol#L210
