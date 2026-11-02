# DepositManagerConfigTimelock.queueEnableAssetPeriod coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-ENABLE-PERIOD`.

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
the route-creation validators. Pre-state hashes isConfigured and isEnabled. Enable and disable
share the same key. Periods span 1..MAX8 when the tuple is configured.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Execution / effects | Test |
| --- | --- | --- | --- |
| DMCT-QUEUE-ENABLE-PERIOD-A01 | Fuzz ADMIN-only, manager-only and overlapping grants | Queue exact target selector/payload; preserve target state | Covered: [test][test_givenAdminOnly_whenTypedActionQueued], [test][test_givenManagerOnly_whenTypedActionQueued], [test][test_givenBothRoles_whenTypedActionQueued] |
| DMCT-QUEUE-ENABLE-PERIOD-A02 | Fuzz callers outside both permitted roles | NotAuthorised(); Unchanged | Covered: [test][test_whenTypedActionCallerUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-ENABLE-PERIOD-L01 | ADMIN | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-L02 | ADMIN | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenManagerPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-L03 | ADMIN | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-L04 | ADMIN | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenManagerInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-D01 | ADMIN | true | true | true | true | Config operator rotated: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenOperatorRotated_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-L05 | ADMIN | true | true | true | true | Normal queue after reEnable or Kernel reactivation | Covered: [test][test_givenReEnabled_whenTypedActionQueued], [test][test_givenReactivated_whenTypedActionQueued] |

## Tuple validation and period domain

| ID | Caller | Tuple / period | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-ENABLE-PERIOD-I01 | ADMIN | Fuzz absent operator/period tuple | DepositManager_InvalidAssetPeriod(asset,period,operator) | Covered: [test][test_whenRouteAbsent_reverts], [test][test_whenPeriodZero_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-I02 | Manager | Tuple already in requested enabled state | DepositManager_AssetPeriodEnabled(asset,period,operator) | Covered: [test][test_givenAssetPeriodIsEnabled_reverts] |
| DMCT-QUEUE-ENABLE-PERIOD-N01 | ADMIN | Fuzz configured period 1..MAX8 | Queue exact selector and uint8 payload | Covered: [test][test_givenAssetPeriodIsDisabled_queuesAndExecutesEnable], [test][test_whenConfiguredPeriodSpansFullRange], [test][test_whenConfiguredMaximumPeriod] |
| DMCT-QUEUE-ENABLE-PERIOD-P01 | Manager; fuzz executor | Tuple in opposite state | Queue then execute exact enabled-state transition | Covered: [test][test_givenAssetPeriodIsDisabled_queuesAndExecutesEnable] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenTypedActionQueued]: ./queueEnableAssetPeriod.t.sol#L56
[test_givenManagerOnly_whenTypedActionQueued]: ./queueEnableAssetPeriod.t.sol#L73
[test_givenBothRoles_whenTypedActionQueued]: ./queueEnableAssetPeriod.t.sol#L90
[test_whenTypedActionCallerUnauthorized_reverts]: ./queueEnableAssetPeriod.t.sol#L107
[test_givenTimelockPaused_whenTypedActionQueued_reverts]: ./queueEnableAssetPeriod.t.sol#L122
[test_givenManagerPaused_whenTypedActionQueued_reverts]: ./queueEnableAssetPeriod.t.sol#L138
[test_givenTimelockInactive_whenTypedActionQueued_reverts]: ./queueEnableAssetPeriod.t.sol#L154
[test_givenManagerInactive_whenTypedActionQueued_reverts]: ./queueEnableAssetPeriod.t.sol#L173
[test_givenOperatorRotated_whenTypedActionQueued_reverts]: ./queueEnableAssetPeriod.t.sol#L192
[test_givenReEnabled_whenTypedActionQueued]: ./queueEnableAssetPeriod.t.sol#L212
[test_givenReactivated_whenTypedActionQueued]: ./queueEnableAssetPeriod.t.sol#L228
[test_whenRouteAbsent_reverts]: ./queueEnableAssetPeriod.t.sol#L263
[test_whenPeriodZero_reverts]: ./queueEnableAssetPeriod.t.sol#L278
[test_givenAssetPeriodIsEnabled_reverts]: ./queueEnableAssetPeriod.t.sol#L26
[test_givenAssetPeriodIsDisabled_queuesAndExecutesEnable]: ./queueEnableAssetPeriod.t.sol#L40
[test_whenConfiguredPeriodSpansFullRange]: ./queueEnableAssetPeriod.t.sol#L245
[test_whenConfiguredMaximumPeriod]: ./queueEnableAssetPeriod.t.sol#L292
