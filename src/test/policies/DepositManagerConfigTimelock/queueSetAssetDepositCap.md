# DepositManagerConfigTimelock.queueSetAssetDepositCap coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-CAP`.

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
Limits key = keccak256(abi.encode(DM, keccak256(abi.encode(keccak256("DEPOSIT_MANAGER_ASSET_LIMITS"), asset)))).
Pre-state hash = keccak256(abi.encode(isConfigured, depositCap, minimumDeposit)). Cap and minimum
share that key; separate assets and period/withdrawal settings have independent keys.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Cap domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-A01 | Fuzz ADMIN-only, manager-only and overlapping role holders | 0..MAX256 | Queue exact typed cap action; preserve target | Covered: [test][test_givenAdminOnly_whenCapQueued], [test][test_givenManagerOnly_whenCapQueued], [test][test_givenBothRoles_whenCapQueued] |
| DMCT-QUEUE-CAP-A02 | Fuzz callers outside both roles | 1 | NotAuthorised(); Unchanged | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-L01 | Manager | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockIsDisabled_queueReverts] |
| DMCT-QUEUE-CAP-L02 | Manager | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenDepositManagerIsDisabled_queueReverts] |
| DMCT-QUEUE-CAP-L03 | Manager | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockPolicyIsInactive_queueReverts] |
| DMCT-QUEUE-CAP-L04 | Manager | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenDepositManagerPolicyIsInactive_queueReverts] |
| DMCT-QUEUE-CAP-L05 | ADMIN | true | true | true | true | After reEnable or Kernel reactivation: queue normally | Covered: [test][test_givenPausedThenReEnabled_whenCapQueued], [test][test_givenPoliciesReactivated_whenCapQueued] |
| DMCT-QUEUE-CAP-D01 | Manager | true | true | true | true | After operator rotation: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenConfigOperatorChanged_queueReverts] |

## Inputs and precedence

| ID | Caller | Asset | Competing fault | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-I01 | ADMIN | Zero | None | AssetManager_NotConfigured(); Unchanged | Covered: [test][test_whenCapAssetZero_reverts] |
| DMCT-QUEUE-CAP-I02 | Manager | Fuzz unconfigured addresses | None | AssetManager_NotConfigured(); Unchanged | Covered: [test][test_givenUnconfiguredAsset_reverts] |
| DMCT-QUEUE-CAP-I03 | Fuzz all callers | Zero | DMCT paused | NotEnabled() before role and product checks | Covered: [test][test_givenPaused_whenUnauthorisedAndAssetZero_reverts] |

## Numeric boundaries

| ID | Caller | Minimum | Proposed cap / time | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-N01 | ADMIN | Fuzz 0..MAX256 | Cap equals minimum | Queue at inclusive minimum | Covered: [test][test_whenCapEqualsCurrentMinimum] |
| DMCT-QUEUE-CAP-N02 | ADMIN | Fuzz 1..MAX256 | Fuzz cap 0..minimum-1 | AssetManager_MinimumDepositExceedsDepositCap(asset,minimum,cap); Unchanged | Covered: [test][test_whenDepositCapIsBelowMinimum_reverts], [test][test_whenCapBelowCurrentMinimum_reverts] |
| DMCT-QUEUE-CAP-N03 | ADMIN / manager | 0 | Cap seeds 0,1,MAX256; full uint256 fuzz | Accepted; later execution sets exact value | Covered: [test][test_givenDepositManagerAdmin_queuesAndExecutesDepositCap], [test][test_whenDepositCapIsUint256Max_queuesAndExecutes], [test][test_whenCapZero], [test][test_whenCapOne], [test][test_whenCapUnchanged] |
| DMCT-QUEUE-CAP-N04 | Manager | 0 | Q=MAX48-delay-window | Queue; expiresAt=MAX48 | Covered: [test][test_whenQueueExpiryIsMaximum] |
| DMCT-QUEUE-CAP-N05 | ADMIN | 0 | Q=MAX48-delay-window+1 | Panic(0x11); roll back ID and reserved key | Covered: [test][test_whenQueueExpiryOverflows_reverts] |

## Queue effects and conflicts

| ID | Caller | Existing configuration / queue | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-P01 | ADMIN | Fresh limits key | Exact ConfigStateQueued → TimelockSubActionQueued → TimelockActionQueued fields and emitters; exact metadata, destination/key/hash | Covered: [test][test_whenCapQueued_emitsExactEvents] |
| DMCT-QUEUE-CAP-P02 | ADMIN | Pending cap for same asset | ConfigKeyPending(key,owner); preserve owner/action and next ID | Covered: [test][test_givenPendingCap_whenCapQueuedAgain_reverts] |
| DMCT-QUEUE-CAP-P03 | ADMIN | Cap equals existing MAX256 | Still queue a delayed no-op; no target mutation at queue time | Covered: [test][test_whenCapUnchanged] |

## Drift after queueing

| ID | Caller | Intervening change | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-D02 | Any executor | Current minimum changes after cap is queued | ConfigStateChanged with exact limits hash; action and key remain pending | Covered: [test][test_givenQueuedCap_whenMinimumChanges_executionRevertsAsStale] |

## Enabled-state metadata

| ID | Caller | Manager status getter | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-CAP-D04 | DEPOSIT_MANAGER_ADMIN | Reverts | PolicyDependency_InvalidDependency(DM); no action, key or target change | Covered: [test][test_givenManagerStatusGetterReverts_whenQueued_reverts] |
| DMCT-QUEUE-CAP-D05 | DEPOSIT_MANAGER_ADMIN | Malformed ABI | PolicyDependency_InvalidDependency(DM); no action, key or target change | Covered: [test][test_givenManagerStatusMalformed_whenQueued_reverts] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenCapQueued]: ./queueSetAssetDepositCap.t.sol#L124
[test_givenManagerOnly_whenCapQueued]: ./queueSetAssetDepositCap.t.sol#L131
[test_givenBothRoles_whenCapQueued]: ./queueSetAssetDepositCap.t.sol#L138
[test_whenCallerIsUnauthorized_reverts]: ./queueLimits.t.sol#L21
[test_givenTimelockIsDisabled_queueReverts]: ./queueSetAssetDepositCap.t.sol#L59
[test_givenDepositManagerIsDisabled_queueReverts]: ./queueSetAssetDepositCap.t.sol#L69
[test_givenTimelockPolicyIsInactive_queueReverts]: ./queueSetAssetDepositCap.t.sol#L79
[test_givenDepositManagerPolicyIsInactive_queueReverts]: ./queueSetAssetDepositCap.t.sol#L94
[test_givenPausedThenReEnabled_whenCapQueued]: ./queueSetAssetDepositCap.t.sol#L210
[test_givenPoliciesReactivated_whenCapQueued]: ./queueSetAssetDepositCap.t.sol#L218
[test_givenConfigOperatorChanged_queueReverts]: ./queueSetAssetDepositCap.t.sol#L109
[test_whenCapAssetZero_reverts]: ./queueSetAssetDepositCap.t.sol#L145
[test_givenUnconfiguredAsset_reverts]: ./queueLimits.t.sol#L31
[test_givenPaused_whenUnauthorisedAndAssetZero_reverts]: ./queueSetAssetDepositCap.t.sol#L227
[test_whenCapEqualsCurrentMinimum]: ./queueSetAssetDepositCap.t.sol#L154
[test_whenDepositCapIsBelowMinimum_reverts]: ./queueLimits.t.sol#L40
[test_whenCapBelowCurrentMinimum_reverts]: ./queueSetAssetDepositCap.t.sol#L162
[test_givenDepositManagerAdmin_queuesAndExecutesDepositCap]: ./queueLimits.t.sol#L74
[test_whenDepositCapIsUint256Max_queuesAndExecutes]: ./queueLimits.t.sol#L110
[test_whenCapZero]: ./queueSetAssetDepositCap.t.sol#L180
[test_whenCapOne]: ./queueSetAssetDepositCap.t.sol#L185
[test_whenCapUnchanged]: ./queueSetAssetDepositCap.t.sol#L190
[test_whenQueueExpiryIsMaximum]: ./queueSetAssetDepositCap.t.sol#L237
[test_whenQueueExpiryOverflows_reverts]: ./queueSetAssetDepositCap.t.sol#L252
[test_whenCapQueued_emitsExactEvents]: ./queueSetAssetDepositCap.t.sol#L267
[test_givenPendingCap_whenCapQueuedAgain_reverts]: ./queueSetAssetDepositCap.t.sol#L195
[test_givenQueuedCap_whenMinimumChanges_executionRevertsAsStale]: ./queueLimits.t.sol#L169
[test_givenManagerStatusGetterReverts_whenQueued_reverts]: ./queueSetAssetDepositCap.t.sol#L29
[test_givenManagerStatusMalformed_whenQueued_reverts]: ./queueSetAssetDepositCap.t.sol#L46
