# DepositManagerConfigTimelock.queueSetAssetMinimumDeposit coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-MINIMUM`.

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

Minimum is uint256 raw asset units. Current cap and minimum share the limits key; its
pre-state hash includes both values and isConfigured. Accept 0≤minimum≤current cap.
An unchanged minimum still queues; target no-op semantics do not bypass the delay.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Execution / effects | Test |
| --- | --- | --- | --- |
| DMCT-QUEUE-MINIMUM-A01 | Fuzz ADMIN-only, manager-only and overlapping grants | Queue exact target selector/payload; preserve target state | Covered: [test][test_givenAdminOnly_whenTypedActionQueued], [test][test_givenManagerOnly_whenTypedActionQueued], [test][test_givenBothRoles_whenTypedActionQueued] |
| DMCT-QUEUE-MINIMUM-A02 | Fuzz callers outside both permitted roles | NotAuthorised(); Unchanged | Covered: [test][test_whenTypedActionCallerUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-MINIMUM-L01 | ADMIN | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-MINIMUM-L02 | ADMIN | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenManagerPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-MINIMUM-L03 | ADMIN | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-MINIMUM-L04 | ADMIN | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenManagerInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-MINIMUM-D01 | ADMIN | true | true | true | true | Config operator rotated: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenOperatorRotated_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-MINIMUM-L05 | ADMIN | true | true | true | true | Normal queue after reEnable or Kernel reactivation | Covered: [test][test_givenReEnabled_whenTypedActionQueued], [test][test_givenReactivated_whenTypedActionQueued] |

## Numeric boundaries and invalid assets

| ID | Caller | Cap / asset | Proposed minimum | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-MINIMUM-I01 | ADMIN | Fuzz unconfigured address | 1 | AssetManager_NotConfigured() | Covered: [test][test_whenMinimumAssetUnconfigured_reverts] |
| DMCT-QUEUE-MINIMUM-N01 | ADMIN | Fuzz cap 0..MAX256 | Equals cap | Queue exact inclusive boundary | Covered: [test][test_whenMinimumEqualsCap] |
| DMCT-QUEUE-MINIMUM-N02 | ADMIN | Fuzz cap 0..MAX256-1 | Fuzz cap+1..MAX256 | AssetManager_MinimumDepositExceedsDepositCap(asset,minimum,cap) | Covered: [test][test_whenMinimumDepositExceedsCap_reverts], [test][test_whenMinimumAboveCap_reverts] |
| DMCT-QUEUE-MINIMUM-N03 | ADMIN / manager | MAX256 | Full uint256; seeds 0,1,MAX256 | Queue; execution stores exact minimum | Covered: [test][test_givenDepositManagerAdmin_queuesAndExecutesMinimumDeposit], [test][test_whenMinimumDepositIsUint256Max_queuesAndExecutes], [test][test_whenMinimumZeroUnchanged], [test][test_whenMinimumOne] |

## Conflicts and stale state

| ID | Caller | Existing queue / configuration | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-MINIMUM-P01 | Manager | Pending cap, same asset | ConfigKeyPending(key,owner); ID unchanged | Covered: [test][test_givenPendingCap_whenMinimumIsQueuedForSameAsset_reverts] |
| DMCT-QUEUE-MINIMUM-P02 | ADMIN | Current minimum=proposed minimum=0 | Still queue delayed action | Covered: [test][test_whenMinimumZeroUnchanged] |
| DMCT-QUEUE-MINIMUM-P03 | Manager | Pending cap for another configured asset | Distinct limits key; queue another ID | Covered: [test][test_givenPendingCap_whenMinimumIsQueuedForAnotherAsset_succeeds] |

## Drift after queueing

| ID | Caller | Intervening change | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-MINIMUM-D02 | Any executor | Current cap changes after minimum is queued | ConfigStateChanged with exact limits hash; action and key remain pending | Covered: [test][test_givenQueuedMinimum_whenCapChanges_reverts] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenTypedActionQueued]: ./queueSetAssetMinimumDeposit.t.sol#L24
[test_givenManagerOnly_whenTypedActionQueued]: ./queueSetAssetMinimumDeposit.t.sol#L36
[test_givenBothRoles_whenTypedActionQueued]: ./queueSetAssetMinimumDeposit.t.sol#L48
[test_whenTypedActionCallerUnauthorized_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L60
[test_givenTimelockPaused_whenTypedActionQueued_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L70
[test_givenManagerPaused_whenTypedActionQueued_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L80
[test_givenTimelockInactive_whenTypedActionQueued_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L90
[test_givenManagerInactive_whenTypedActionQueued_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L103
[test_givenOperatorRotated_whenTypedActionQueued_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L116
[test_givenReEnabled_whenTypedActionQueued]: ./queueSetAssetMinimumDeposit.t.sol#L130
[test_givenReactivated_whenTypedActionQueued]: ./queueSetAssetMinimumDeposit.t.sol#L143
[test_whenMinimumAssetUnconfigured_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L187
[test_whenMinimumEqualsCap]: ./queueSetAssetMinimumDeposit.t.sol#L157
[test_whenMinimumDepositExceedsCap_reverts]: ./queueLimits.t.sol#L57
[test_whenMinimumAboveCap_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L169
[test_givenDepositManagerAdmin_queuesAndExecutesMinimumDeposit]: ./queueLimits.t.sol#L92
[test_whenMinimumDepositIsUint256Max_queuesAndExecutes]: ./queueLimits.t.sol#L126
[test_whenMinimumZeroUnchanged]: ./queueSetAssetMinimumDeposit.t.sol#L197
[test_whenMinimumOne]: ./queueSetAssetMinimumDeposit.t.sol#L207
[test_givenPendingCap_whenMinimumIsQueuedForSameAsset_reverts]: ./queueLimits.t.sol#L140
[test_givenPendingCap_whenMinimumIsQueuedForAnotherAsset_succeeds]: ./queueLimits.t.sol#L151
[test_givenQueuedMinimum_whenCapChanges_reverts]: ./queueSetAssetMinimumDeposit.t.sol#L217
