# DepositManagerConfigTimelock.queueBatch coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Scope: the shared admin-or-deposit_manager_admin authorization check, reached by queueBatch and the six typed queue functions: deposit cap, minimum deposit, share withdrawal requirement, period enablement, period disablement and period creation. This plan also covers product inputs, batch bounds, key conflicts and atomic queueing.

## Domains and assertions

- DMCT = DepositManagerConfigTimelock; DM = its bound DepositManager. Default: both enabled and Kernel-active; DMCT selected as DM's configOperator; configured asset and a valid one-action deposit-cap batch.
- Admin and Deposit Manager Admin are authorized caller classes, tested separately. Fuzz unauthorized callers excluding exactly those two fixture accounts; guarantee zero, emergency-only, deposit-operator-only and the previous config operator.
- Authorization rejection is IPolicyAdmin.NotAuthorised(), matching DMCT's existing combined-role reEnable check. Single-role cancellation retains ROLES_RequireRole(EMERGENCY_ROLE).
- Unchanged: nextActionId, pending action length/config guards, target deposit cap and operator unchanged; no committed events. The caller error wins over an invalid one-action payload. Own activity, local enablement and proposer authorization run before batch-size validation, including an empty batch.

| ID | Caller | State / request | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-A01 | Admin; Deposit Manager Admin separately | Default; deposit-cap batch | Store exact proposer, target, selector and payload; one action ID consumed; no DM configuration change at queue | Covered: [test][test_whenAdminQueues], [test][test_whenDepositManagerAdminQueues] |
| DMCT-A02 | Fuzz unauthorized caller; fixed unauthorized identities | Default; valid deposit-cap batch or invalid asset | NotAuthorised(); Unchanged | Covered: [test][test_whenCallerIsUnauthorized_reverts], [test][test_whenCallerIsUnauthorized_whenAssetIsZero_reverts], [test][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| DMCT-A03 | Fuzz unauthorized caller | Default; typed cap/share-withdrawal/period-creation queue | NotAuthorised(); input validation is not reached | Covered: [cap](./queueLimits.t.sol#L21), [withdrawal](./queueSetAssetShareWithdrawalRequired.t.sol#L34), [period][test_whenCallerIsNotAuthorized_reverts], [emergency][test_givenEmergency_whenQueueingRouteCreation_reverts] |

Lifecycle checks still precede authorization: DMCT active → DMCT enabled → caller role → DM active → selected operator → DM enabled → sub-action validation. Lifecycle behavior is covered by [enable](./enable.md), [disable](./disable.md), [reEnable](./reEnable.md) and the typed queue plans. Execution and cancellation have dedicated function plans.

## Batch boundaries, product dispatch and atomicity

| ID | Caller | Batch | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-BATCH-I01 | Manager | Empty batch | BatchEmpty() after proposer admission | Covered: [test][test_whenBatchIsEmpty_reverts] |
| DMCT-BATCH-N01 | Manager | 15 independent period actions | Queue maximum batch; length=15 | Covered: [test][test_whenBatchIsAtMaximum_queues] |
| DMCT-BATCH-N02 | Manager | 16 actions | BatchTooLarge(16,15); next ID unchanged | Covered: [test][test_whenBatchIsAboveMaximum_reverts] |
| DMCT-BATCH-I02 | Manager | Wrong target | ActionInvalid(target,selector) | Covered: [test][test_whenTargetIsInvalid_reverts] |
| DMCT-BATCH-I03 | Manager | Unsupported selector | ActionInvalid(DM,selector) | Covered: [test][test_whenSelectorIsInvalid_reverts] |
| DMCT-BATCH-I04 | Manager | Wrong limits payload length | ActionInvalid(DM,setAssetDepositCap) | Covered: [test][test_whenPayloadLengthIsInvalid_reverts] |
| DMCT-BATCH-I05 | Manager | Wrong route payload length | ActionInvalid(DM,addAssetPeriod) | Covered: [test][test_whenRouteCreationPayloadLengthIsInvalid_reverts] |
| DMCT-BATCH-I06 | Manager | Create route then enable same absent tuple | InvalidAssetPeriod: queue validators inspect live state, not projected earlier actions | Covered: [test][test_givenRouteCreationThenEnablementOfSameTuple_reverts] |
| DMCT-BATCH-P01 | Manager | Duplicate route creations | ConfigKeyPending; complete queue rollback | Covered: [test][test_givenConflictingRouteCreations_reverts] |
| DMCT-BATCH-P02 | Manager | Cap and minimum for same asset | Shared limits ConfigKeyPending; ID rollback | Covered: [test][test_givenSameAssetCapAndMinimum_whenQueuedTogether_reverts] |
| DMCT-BATCH-P03 | ADMIN; fuzz executor | Independent cap and period actions | One ordered batch applies both atomically after delay | Covered: [test][test_givenIndependentActions_queuesAndExecutesAtomically] |
| DMCT-BATCH-T01 | Any executor | Later action stale at execution | Roll back earlier cap update | Covered: [test][test_givenLaterActionStateIsStale_executionRollsBackEarlierAction] |

## Additional collection and ABI boundaries

| ID | Caller | Batch domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-BATCH-N03 | ADMIN | Fuzz 1..15 independent configured period actions | Exact length; one action ID; key cap remains 15 | Covered: [test][test_whenBatchLengthSpansValidRange] |
| DMCT-BATCH-I07 | ADMIN | Correct-length cap payload with noncanonical address word | Exact empty Solidity ABI-decoder revert; queue rollback | Covered: [test][test_whenAssetWordNoncanonical_reverts] |
| DMCT-BATCH-I08 | ADMIN | Correct-length route payload with period word=256 | Exact empty Solidity ABI-decoder revert; queue rollback | Covered: [test][test_whenPeriodWordNoncanonical_reverts] |
| DMCT-BATCH-I09 | ADMIN | Correct-length withdrawal payload with bool word=2 | Exact empty Solidity ABI-decoder revert; queue rollback | Covered: [test][test_whenBooleanWordNoncanonical_reverts] |

- [x] Expand the batch plan beyond proposer authorization.
- [x] Validate reciprocal mappings and focused execution.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-BATCH-L01 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; empty batch where exposed | DepositManagerConfigTimelock_PolicyInactive(TL) | No ID, guard, payload or committed log | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts] |
| DMCT-BATCH-L02 | Fuzz all callers | true | false | ROLES code rejects; empty batch where exposed | NotEnabled() | No ID, guard, payload or committed log | Covered: [test][test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts] |
| DMCT-BATCH-A01 | Fuzz outside both accepted proposer roles | true | true | Target inactive or required metadata rejects; empty batch where exposed | NotAuthorised() | No ID, guard, payload or committed log | Covered: [test][test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts] |

[test_whenAdminQueues]: ./queueBatch.t.sol#L23
[test_whenDepositManagerAdminQueues]: ./queueBatch.t.sol#L29
[test_whenCallerIsUnauthorized_reverts]: ./queueBatch.t.sol#L35
[test_whenCallerIsUnauthorized_whenAssetIsZero_reverts]: ./queueBatch.t.sol#L41
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./queueBatch.t.sol#L48
[test_whenCallerIsNotAuthorized_reverts]: ./queueAddAssetPeriod.t.sol#L33
[test_givenEmergency_whenQueueingRouteCreation_reverts]: ./queueAddAssetPeriod.t.sol#L257
[test_whenBatchIsEmpty_reverts]: ./queueBatch.t.sol#L227
[test_whenBatchIsAtMaximum_queues]: ./queueBatch.t.sol#L192
[test_whenBatchIsAboveMaximum_reverts]: ./queueBatch.t.sol#L207
[test_whenTargetIsInvalid_reverts]: ./queueBatch.t.sol#L236
[test_whenSelectorIsInvalid_reverts]: ./queueBatch.t.sol#L256
[test_whenPayloadLengthIsInvalid_reverts]: ./queueBatch.t.sol#L273
[test_whenRouteCreationPayloadLengthIsInvalid_reverts]: ./queueBatch.t.sol#L132
[test_givenRouteCreationThenEnablementOfSameTuple_reverts]: ./queueBatch.t.sol#L168
[test_givenConflictingRouteCreations_reverts]: ./queueBatch.t.sol#L151
[test_givenSameAssetCapAndMinimum_whenQueuedTogether_reverts]: ./queueBatch.t.sol#L289
[test_givenIndependentActions_queuesAndExecutesAtomically]: ./queueBatch.t.sol#L308
[test_givenLaterActionStateIsStale_executionRollsBackEarlierAction]: ./queueBatch.t.sol#L338
[test_whenBatchLengthSpansValidRange]: ./queueBatch.t.sol#L389
[test_whenAssetWordNoncanonical_reverts]: ./queueBatch.t.sol#L400
[test_whenPeriodWordNoncanonical_reverts]: ./queueBatch.t.sol#L408
[test_whenBooleanWordNoncanonical_reverts]: ./queueBatch.t.sol#L416
[test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L435
[test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L462
[test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts]: ./queueBatch.t.sol#L482
