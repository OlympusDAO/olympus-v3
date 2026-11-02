# BurnerLoansInventoryConfigTimelock.executeQueuedAction coverage plan

Shared action existence, terminal-status and execution-window checks precede concrete admission. Execution then requires own Kernel activity before local enablement and target checks; its caller remains permissionless.

Source: [executeQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L136). Concrete behavior: [_validateExecution](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L237).

## Scope and fixtures

`MAXn` denotes `2**n-1`; time is measured in seconds.

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Authorization and success

A ready rescue has surplus=1e9 and idle/claims=50e9. Assert Inventory `SurplusRescued(1e9)` before `TimelockSubActionExecuted(id,I,rescueSurplus.selector,0)`, then `TimelockActionExecuted(id,executor)`. Metadata persists; payload, destination, state records and key are cleared. T=executableAt; E=expiresAt.

| ID | Caller | Pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-P01 | Fuzz all executors | T<=now<=E; controller unchanged | Success | Treasury +1e9; idle/claims unchanged; executed=true; payload and guards cleared; shared key released | Covered: [test][test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup]; [test][test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup] |

## Lifecycle

Use ADMIN only; authorization independence is established above. Queued action is pending and time-valid.

| ID | Caller | Local active | Local enabled | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-L01 | ADMIN | true | true | true | false | Burn: PolicyDependency_NotActive(I) | Pending action/key retained | Covered: [test][test_givenInventoryDisabledAfterQueue_whenBurnExecutes_reverts] |
| BLINCT-EXECUTE-L02 | ADMIN | true | true | true | false | Rescue: success | Transfer surplus; I stays paused | Covered: [test][test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup]; [test][test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup] |
| BLINCT-EXECUTE-L03 | ADMIN | true | false | true | true | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabledTimelock_whenExecuted_reverts] |
| BLINCT-EXECUTE-L04 | ADMIN | false | true | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveTimelock_whenExecuted_reverts] |
| BLINCT-EXECUTE-L05 | ADMIN | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabledTimelock_whenExecuted_reverts] |
| BLINCT-EXECUTE-L06 | ADMIN | true | true | false | true | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInactiveInventory_whenExecuted_reverts] |
| BLINCT-EXECUTE-L07 | ADMIN | true | true | false | false | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInactiveInventory_whenExecuted_reverts] |

## Time and terminal state

Inherited pending-state/time guards run before lifecycle hooks; match full error arguments.

| ID | Caller | Input / state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-I01 | Fuzz all executors | Unknown id; seed 0,MAX64 | ActionNotFound(id) |Unchanged; getQueuedAction/length/subAction use ActionNotFound(id); absent config count/destination are 0; getQueuedConfigState(id,0,0) uses ConfigStateIndexOutOfBounds(id,0,0,0) | Covered: [test][test_whenActionUnknown_revertsBeforeAuthorization]; [test][test_whenUnknownIdAtTypeBounds_reverts] |
| BLINCT-EXECUTE-N01 | Fuzz all executors | Fuzz now in queuedAt..T-1; seed queuedAt,T-1 | ActionNotReady(id,T) | Unchanged | Covered: [test][test_givenNoticeNotElapsed_whenExecuted_reverts]; [test][test_givenNoticeEndpointSeeds_whenExecuted_reverts] |
| BLINCT-EXECUTE-N02 | Fuzz all executors | now=T | Success | Inclusive lower boundary | Covered: [test][test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup]; [test][test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup] |
| BLINCT-EXECUTE-N03 | Fuzz all executors | now=E | Success | Inclusive upper boundary | Covered: [test][test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup]; [test][test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup] |
| BLINCT-EXECUTE-N04 | Fuzz all executors | Fuzz now in E+1..MAX256; seed E+1,MAX48,MAX256 | ActionExpired(id,E) | Retain key until cancellation | Covered: [test][test_givenExpiredWindow_whenExecuted_reverts]; [test][test_givenExpiredWindowEndpointSeeds_whenExecuted_reverts] |
| BLINCT-EXECUTE-I02 | Fuzz all executors | Already executed | ActionAlreadyExecuted(id) |No second dispatch; metadata retains executed=true; length/subAction reject ActionAlreadyExecuted(id); payload/destination/state/key cleared | Covered: [test][test_givenExecutedAction_whenCalled_revertsBeforeAuthorization] |
| BLINCT-EXECUTE-I03 | Fuzz all executors | Cancelled | ActionCancelled(id) |No dispatch; metadata retains cancelled=true; length/subAction reject ActionCancelled(id); payload/destination/state/key cleared | Covered: [test][test_givenCancelledAction_whenCalled_revertsBeforeAuthorization] |

## Drift and failures

Recovery commits the controller, not balances, debt or the global cap. No Config dependency. A controller change away from TL and back to TL restores the original hash; there is no controller-generation nonce. Test this separately from a controller that remains changed.

| ID | Caller | Fault / transition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-D01 | Fuzz all executors | I controller changes to another nonzero address | ConfigStateChanged(id,0,key,expected,current) | Pending action/key retained | Covered: [test][test_givenControllerChanged_whenActionExecutes_reverts] |
| BLINCT-EXECUTE-D02 | Fuzz all executors | Core settlement guard entered | ReentrancyGuardReentrantCall() | No payout; pending retained; idle guard restoration permits retry | Covered: [test][test_givenCoreSettlementBusy_whenRecoveryExecutes_revertsAndCanRetry] |
| BLINCT-EXECUTE-D03 | Fuzz all executors | I reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | No dispatch | Covered: [test][test_givenInventoryKernelDrift_whenExecuted_reverts] |
| BLINCT-EXECUTE-D04 | Fuzz all executors | I controller cleared to zero | ConfigStateChanged(id,0,key,expected,keccak256(abi.encode(address(0)))) | Pending action/key retained | Covered: [test][test_givenControllerCleared_whenExecuted_reverts] |
| BLINCT-EXECUTE-T01 | Fuzz all executors | Positive rescue transfer fails with a typed token error | Exact underlying error | Balances/claims and queue/key roll back; retry after restoration | Covered: [test][test_givenRescueTransferFailure_whenExecuted_thenRollbackAndRetry] |
| BLINCT-EXECUTE-T04 | Fuzz all executors | Positive MINTR burn fails with typed error | Exact MINTR error | No burn; claims, queue/key and token supply unchanged; retry after restoration | Covered: [test][test_givenMintrBurnFailure_whenExecuted_thenRollbackAndRetry] |
| BLINCT-EXECUTE-T02 | Fuzz all executors | Target failure empty data | SubActionCallFailed(selector) | Pending/key retained | Covered: [test][test_givenTargetEmptyFailure_whenExecuted_thenWrappedError] |
| BLINCT-EXECUTE-T03 | Fuzz all executors | Target failure hits 256-byte cap | SubActionCallFailed(selector) | Pending/key retained | Covered: [test][test_givenTargetCappedFailure_whenExecuted_thenWrappedError]; [test][test_givenTargetReturnBomb_whenExecuted_thenCappedWrapper] |
| BLINCT-EXECUTE-P02 | Fuzz all executors | Replace BurnerLoansConfig; same Inventory controller | Success | No redirect/invalidation | Covered: [test][test_givenConfigReplaced_whenExecuted_thenImmutableInventoryUsed] |
| BLINCT-EXECUTE-P03 | Fuzz all executors | Core selects another empty-ledger Inventory; old I remains active | Old queue dispatches to old I | Replacement gets no call/funds | Covered: [test][test_givenCoreInventoryReplaced_whenExecuted_thenOriginalTargetRecovered] |

## Transfer callback

Use one OHM transfer callback during rescue. Give the token callback caller ADMIN so a nested Inventory rescue is otherwise authorized. Inventory owns the token-transfer guard; TL does not add another guard. A same-id TL execution retry is separately rejected by its already-executed flag before dispatch.

| ID | Caller | Callback | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-C01 | ADMIN | Nested I.rescueSurplus(); token propagates rejection | ReentrancyGuardReentrantCall() propagates through the token and bounded TL call | No double payment; full balance/claim rollback; key/action retained | Covered: [test][test_givenRescueTokenCallback_whenNestedRescuePropagates_thenCompleteRollback] |

## Restored controller and recovery retry

No queue-time balance or approval is reserved.

| ID | Caller | Transition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-EXECUTE-P04 | Fuzz all executors | Controller changes TL to another address and back to TL; original action remains in time window | Original recovery is executable | Original hash matches again; exactly one recovery and normal cleanup | Covered: [test][test_givenControllerRotatesBack_whenExecuted_thenOriginalCommitmentMatches] |
| BLINCT-EXECUTE-P05 | ADMIN proposer | After successful execution, queue another burn/rescue | Return fresh ID | Old key is free; new metadata/hash belong to new ID | Covered: [test][test_givenExecutedAction_whenRequeued_thenFreshIdOwnsKey] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_givenReadyRecovery_whenAnyoneExecutes_thenExactCleanup]: ./executeQueuedAction.t.sol#L94
[test_givenExecutionEndpointSeeds_whenExecuted_thenExactCleanup]: ./executeQueuedAction.t.sol#L537
[test_givenInventoryDisabledAfterQueue_whenBurnExecutes_reverts]: ./executeQueuedAction.t.sol#L77
[test_givenActiveDisabledTimelock_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L175
[test_givenInactiveTimelock_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L199
[test_givenInactiveInventory_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L214
[test_whenActionUnknown_revertsBeforeAuthorization]: ./executeQueuedAction.t.sol#L309
[test_whenUnknownIdAtTypeBounds_reverts]: ./executeQueuedAction.t.sol#L592
[test_givenNoticeNotElapsed_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L139
[test_givenNoticeEndpointSeeds_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L565
[test_givenExpiredWindow_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L157
[test_givenExpiredWindowEndpointSeeds_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L579
[test_givenExecutedAction_whenCalled_revertsBeforeAuthorization]: ./executeQueuedAction.t.sol#L330
[test_givenCancelledAction_whenCalled_revertsBeforeAuthorization]: ./executeQueuedAction.t.sol#L349
[test_givenControllerChanged_whenActionExecutes_reverts]: ./executeQueuedAction.t.sol#L36
[test_givenCoreSettlementBusy_whenRecoveryExecutes_revertsAndCanRetry]: ./executeQueuedAction.t.sol#L55
[test_givenInventoryKernelDrift_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L230
[test_givenControllerCleared_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L247
[test_givenRescueTransferFailure_whenExecuted_thenRollbackAndRetry]: ./executeQueuedAction.t.sol#L370
[test_givenMintrBurnFailure_whenExecuted_thenRollbackAndRetry]: ./executeQueuedAction.t.sol#L389
[test_givenTargetEmptyFailure_whenExecuted_thenWrappedError]: ./executeQueuedAction.t.sol#L411
[test_givenTargetCappedFailure_whenExecuted_thenWrappedError]: ./executeQueuedAction.t.sol#L418
[test_givenTargetReturnBomb_whenExecuted_thenCappedWrapper]: ./executeQueuedAction.t.sol#L425
[test_givenConfigReplaced_whenExecuted_thenImmutableInventoryUsed]: ./executeQueuedAction.t.sol#L456
[test_givenCoreInventoryReplaced_whenExecuted_thenOriginalTargetRecovered]: ./executeQueuedAction.t.sol#L480
[test_givenRescueTokenCallback_whenNestedRescuePropagates_thenCompleteRollback]: ./executeQueuedAction.t.sol#L508
[test_givenControllerRotatesBack_whenExecuted_thenOriginalCommitmentMatches]: ./executeQueuedAction.t.sol#L266
[test_givenExecutedAction_whenRequeued_thenFreshIdOwnsKey]: ./executeQueuedAction.t.sol#L284
[test_givenInactiveDisabledTimelock_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L184
