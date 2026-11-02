# DepositManagerConfigTimelock.queueAddAssetPeriod coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-ADD-PERIOD`.

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

Route creation delegates validation to DM.validateAddAssetPeriod. The asset must be
configured, period 1..MAX8, operator nonzero, registered by name and holding DEPOSIT_OPERATOR_ROLE,
and the route absent. Queueing creates no route or receipt token. The period key is shared with
enable/disable, and pre-state hashes isConfigured,isEnabled,operator role membership.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Execution / effects | Test |
| --- | --- | --- | --- |
| DMCT-QUEUE-ADD-PERIOD-A01 | Fuzz ADMIN-only, manager-only and overlapping grants | Queue exact target selector/payload; preserve target state | Covered: [test][test_givenAdminOnly_whenTypedActionQueued], [test][test_givenManagerOnly_whenTypedActionQueued], [test][test_givenBothRoles_whenTypedActionQueued] |
| DMCT-QUEUE-ADD-PERIOD-A02 | Fuzz callers outside both permitted roles | NotAuthorised(); Unchanged | Covered: [test][test_whenTypedActionCallerUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-ADD-PERIOD-L01 | ADMIN | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ADD-PERIOD-L02 | ADMIN | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenManagerPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ADD-PERIOD-L03 | ADMIN | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ADD-PERIOD-L04 | ADMIN | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenManagerInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ADD-PERIOD-D01 | ADMIN | true | true | true | true | Config operator rotated: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenOperatorRotated_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ADD-PERIOD-L05 | ADMIN | true | true | true | true | Normal queue after reEnable or Kernel reactivation | Covered: [test][test_givenReEnabled_whenTypedActionQueued], [test][test_givenReactivated_whenTypedActionQueued] |

## Route inputs

| ID | Caller | Invalid field / history | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-ADD-PERIOD-I01 | Manager | Asset=0 | AssetManager_NotConfigured() | Covered: [test][test_whenAssetIsZero_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I02 | Manager | Unconfigured nonzero asset | AssetManager_NotConfigured() | Covered: [test][test_whenAssetIsNotConfigured_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I03 | Manager | Period=0 | DepositManager_OutOfBounds() | Covered: [test][test_whenDepositPeriodIsZero_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I04 | Manager | Operator=0 | DepositManager_ZeroAddress() | Covered: [test][test_whenOperatorIsZero_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I05 | Manager | Unregistered operator | DepositManager_OperatorNameNotSet(operator) | Covered: [test][test_whenOperatorIsUnregistered_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I06 | Manager | Registered operator without deposit_operator | DepositManager_DepositOperatorRoleNotHeld(operator) | Covered: [test][test_whenOperatorHoldsNoDepositOperatorRole_reverts] |
| DMCT-QUEUE-ADD-PERIOD-I07 | Manager | Existing route | DepositManager_AssetPeriodExists(asset,period,operator) | Covered: [test][test_givenRouteExists_reverts] |
| DMCT-QUEUE-ADD-PERIOD-N01 | ADMIN / manager | Full uint8 valid period 1..MAX8; explicit 1,MAX8 | Exact typed payload queues | Covered: [test][test_whenDepositPeriodIsOne_succeeds], [test][test_whenDepositPeriodIsMaximum_succeeds], [test][test_whenNewPeriodSpansFullRange] |

## Key ownership

| ID | Caller | Existing queue / route | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-ADD-PERIOD-P01 | Manager | Repeated creation of same tuple | ConfigKeyPending(key,owner); no extra ID | Covered: [test][test_givenPendingAdd_whenQueueingSameRouteAgain_reverts] |
| DMCT-QUEUE-ADD-PERIOD-P02 | Manager | Directly create pending route, then queue disable | Shared period key remains reserved: ConfigKeyPending | Covered: [test][test_givenPendingAdd_whenQueueingDisableForSameRoute_reverts] |
| DMCT-QUEUE-ADD-PERIOD-P03 | Manager | Another period tuple | Independent key; another action ID | Covered: [test][test_givenPendingAdd_whenQueueingDifferentRoute_succeeds] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenTypedActionQueued]: ./queueAddAssetPeriod.t.sol#L265
[test_givenManagerOnly_whenTypedActionQueued]: ./queueAddAssetPeriod.t.sol#L280
[test_givenBothRoles_whenTypedActionQueued]: ./queueAddAssetPeriod.t.sol#L295
[test_whenTypedActionCallerUnauthorized_reverts]: ./queueAddAssetPeriod.t.sol#L310
[test_givenTimelockPaused_whenTypedActionQueued_reverts]: ./queueAddAssetPeriod.t.sol#L323
[test_givenManagerPaused_whenTypedActionQueued_reverts]: ./queueAddAssetPeriod.t.sol#L336
[test_givenTimelockInactive_whenTypedActionQueued_reverts]: ./queueAddAssetPeriod.t.sol#L349
[test_givenManagerInactive_whenTypedActionQueued_reverts]: ./queueAddAssetPeriod.t.sol#L365
[test_givenOperatorRotated_whenTypedActionQueued_reverts]: ./queueAddAssetPeriod.t.sol#L381
[test_givenReEnabled_whenTypedActionQueued]: ./queueAddAssetPeriod.t.sol#L398
[test_givenReactivated_whenTypedActionQueued]: ./queueAddAssetPeriod.t.sol#L414
[test_whenAssetIsZero_reverts]: ./queueAddAssetPeriod.t.sol#L61
[test_whenAssetIsNotConfigured_reverts]: ./queueAddAssetPeriod.t.sol#L71
[test_whenDepositPeriodIsZero_reverts]: ./queueAddAssetPeriod.t.sol#L87
[test_whenOperatorIsZero_reverts]: ./queueAddAssetPeriod.t.sol#L129
[test_whenOperatorIsUnregistered_reverts]: ./queueAddAssetPeriod.t.sol#L141
[test_whenOperatorHoldsNoDepositOperatorRole_reverts]: ./queueAddAssetPeriod.t.sol#L158
[test_givenRouteExists_reverts]: ./queueAddAssetPeriod.t.sol#L177
[test_whenDepositPeriodIsOne_succeeds]: ./queueAddAssetPeriod.t.sol#L99
[test_whenDepositPeriodIsMaximum_succeeds]: ./queueAddAssetPeriod.t.sol#L115
[test_whenNewPeriodSpansFullRange]: ./queueAddAssetPeriod.t.sol#L431
[test_givenPendingAdd_whenQueueingSameRouteAgain_reverts]: ./queueAddAssetPeriod.t.sol#L194
[test_givenPendingAdd_whenQueueingDisableForSameRoute_reverts]: ./queueAddAssetPeriod.t.sol#L217
[test_givenPendingAdd_whenQueueingDifferentRoute_succeeds]: ./queueAddAssetPeriod.t.sol#L232
