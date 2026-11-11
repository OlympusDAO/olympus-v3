# DepositManagerConfigTimelock.queueSetAssetShareWithdrawalRequired coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-QUEUE-WITHDRAWAL`.

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

Required is boolean. The wrapper delegates custody-route validation to DM. A synchronous
vault accepts either value; an idle asset cannot require shares; an asynchronous redeem vault
cannot disable the shares requirement. The key hashes the withdrawal domain and asset,
independently of limits and asset-period keys. Pre-state = keccak256(abi.encode(isConfigured,current required,DM.configOperator())).

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization

| ID | Caller | Execution / effects | Test |
| --- | --- | --- | --- |
| DMCT-QUEUE-WITHDRAWAL-A01 | Fuzz ADMIN-only, manager-only and overlapping grants | Queue exact target selector/payload; preserve target state; independently assert current target operator in stored pre-state | Covered: [test][test_givenAdminOnly_whenTypedActionQueued], [test][test_givenManagerOnly_whenTypedActionQueued], [test][test_givenBothRoles_whenTypedActionQueued] |
| DMCT-QUEUE-WITHDRAWAL-A02 | Fuzz callers outside both permitted roles | NotAuthorised(); Unchanged | Covered: [test][test_whenCallerIsUnauthorized_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-WITHDRAWAL-L01 | ADMIN | true | false | true | true | NotEnabled(); Unchanged | Covered: [test][test_givenTimelockPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-WITHDRAWAL-L02 | ADMIN | true | true | true | false | NotEnabled(); Unchanged | Covered: [test][test_givenManagerPaused_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-WITHDRAWAL-L03 | ADMIN | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT); Unchanged | Covered: [test][test_givenTimelockInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-WITHDRAWAL-L04 | ADMIN | true | true | false | true | PolicyDependency_NotActive(DM); Unchanged | Covered: [test][test_givenManagerInactive_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-WITHDRAWAL-D01 | ADMIN | true | true | true | true | Config operator rotated: ConfigOperator_Unauthorized(DMCT); Unchanged | Covered: [test][test_givenOperatorRotated_whenTypedActionQueued_reverts] |
| DMCT-QUEUE-WITHDRAWAL-L05 | ADMIN | true | true | true | true | Normal queue after reEnable or Kernel reactivation | Covered: [test][test_givenReEnabled_whenTypedActionQueued], [test][test_givenReactivated_whenTypedActionQueued] |

## Custody-route validation

| ID | Caller | Custody route / asset | Required | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-WITHDRAWAL-I01 | Manager | Fuzz unconfigured address | Fuzz false/true | AssetManager_NotConfigured() | Covered: [test][test_givenUnconfiguredAsset_reverts] |
| DMCT-QUEUE-WITHDRAWAL-I02 | Manager | Idle asset; vault=0 | true | AssetManager_VaultRequired(asset) | Covered: [test][test_givenIdleAsset_whenRequiredIsTrue_reverts] |
| DMCT-QUEUE-WITHDRAWAL-I03 | Manager | Asynchronous redeem vault | false | AssetManager_RequiresWithdrawAsShares(asset,vault) | Covered: [test][test_givenAsyncRedeemVault_whenRequiredIsFalse_reverts] |
| DMCT-QUEUE-WITHDRAWAL-P01 | Manager | Synchronous vault | Fuzz false/true | Unchanged before execution; exact requested boolean after execution | Covered: [test][test_whenRequirementIsQueued_executesAfterDelay] |

## Keys and drift

| ID | Caller | Existing queue / drift | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-QUEUE-WITHDRAWAL-P02 | Manager | Pending same-asset requirement | ConfigKeyPending(key,owner); no ID consumed | Covered: [test][test_givenPendingRequirement_whenSameAssetIsQueuedAgain_reverts] |
| DMCT-QUEUE-WITHDRAWAL-P03 | Manager | Pending requirement; queue period change | Distinct domain permits both actions | Covered: [test][test_givenPendingRequirement_whenAssetPeriodChangeIsQueued_succeeds] |
| DMCT-QUEUE-WITHDRAWAL-P04 | Manager | Second configured asset | Distinct asset keys permit two actions | Covered: [test][test_givenSecondAsset_requirementKeysAreIndependent] |
| DMCT-QUEUE-WITHDRAWAL-D02 | Any executor | Required flag changed after queue | ConfigStateChanged; preserve pending action | Covered: [test][test_givenQueuedRequirement_whenRequirementChanges_executionRevertsAsStale] |

## Same-value queueing

| ID | Caller | Current required | Proposed required | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-QUEUE-WITHDRAWAL-P05 | ADMIN | false | false | Queue exact delayed action, retaining current target configuration | Covered: [test][test_whenRequirementFalseUnchangedQueued] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenAdminOnly_whenTypedActionQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L218
[test_givenManagerOnly_whenTypedActionQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L230
[test_givenBothRoles_whenTypedActionQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L242
[test_whenCallerIsUnauthorized_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L34
[test_givenTimelockPaused_whenTypedActionQueued_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L254
[test_givenManagerPaused_whenTypedActionQueued_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L264
[test_givenTimelockInactive_whenTypedActionQueued_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L274
[test_givenManagerInactive_whenTypedActionQueued_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L287
[test_givenOperatorRotated_whenTypedActionQueued_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L300
[test_givenReEnabled_whenTypedActionQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L314
[test_givenReactivated_whenTypedActionQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L327
[test_givenUnconfiguredAsset_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L67
[test_givenIdleAsset_whenRequiredIsTrue_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L76
[test_givenAsyncRedeemVault_whenRequiredIsFalse_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L97
[test_whenRequirementIsQueued_executesAfterDelay]: ./queueSetAssetShareWithdrawalRequired.t.sol#L125
[test_givenPendingRequirement_whenSameAssetIsQueuedAgain_reverts]: ./queueSetAssetShareWithdrawalRequired.t.sol#L148
[test_givenPendingRequirement_whenAssetPeriodChangeIsQueued_succeeds]: ./queueSetAssetShareWithdrawalRequired.t.sol#L179
[test_givenSecondAsset_requirementKeysAreIndependent]: ./queueSetAssetShareWithdrawalRequired.t.sol#L195
[test_givenQueuedRequirement_whenRequirementChanges_executionRevertsAsStale]: ./queueSetAssetShareWithdrawalRequired.t.sol#L165
[test_whenRequirementFalseUnchangedQueued]: ./queueSetAssetShareWithdrawalRequired.t.sol#L341
