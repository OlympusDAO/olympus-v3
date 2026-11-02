# BurnerLoansInventoryConfigTimelock.queueBurnSurplus coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [queueBurnSurplus](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L125).

## Scope and fixtures

`MAXn` denotes `2**n-1`; time is measured in seconds.

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Authorization

TL and I active/enabled; controller=TL; no pending key. Caller variation is tested here rather than repeated across lifecycle rows.

| ID | Caller | Pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-A01 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | Caller role independent of TL; TL has no ADMIN grant | Return next ID | Store I target, correct selector, empty payload; no immediate payout | Covered: [test][test_givenBurnerLoansAdmin_whenBurnQueued_thenNoticePrecedesBurn]; [test][test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents]; [test][test_givenEachPermittedRole_whenQueued_thenExactMetadata] |
| BLINCT-BURN-A02 | Fuzz outside both role-holder sets | Positive surplus | NotAuthorised() | Unchanged | Covered: [test][test_whenUnauthorizedProposer_reverts] |
| BLINCT-BURN-A03 | ADMIN | Controller is another nonzero address | NotAuthorised() | Unchanged | Covered: [test][test_givenAnotherController_whenQueued_reverts] |
| BLINCT-BURN-A04 | ADMIN | Controller is zero | NotAuthorised() | Unchanged | Covered: [test][test_givenClearedController_whenQueued_reverts] |

## Lifecycle

Use ADMIN with cached ROLES; every unvaried service is ready. Burn requires I enabled; rescue remains available while I is paused.

| ID | Caller | Local active | Local enabled | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-L03 | ADMIN | true | false | true | true | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabledTimelock_whenQueued_reverts] |
| BLINCT-BURN-L04 | ADMIN | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabledTimelock_whenQueued_reverts] |
| BLINCT-BURN-L05 | ADMIN | false | true | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveTimelock_whenQueued_reverts] |
| BLINCT-BURN-L06 | ADMIN | true | true | false | true | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInactiveTarget_whenQueued_reverts] |
| BLINCT-BURN-L07 | ADMIN | true | true | false | false | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInactiveTarget_whenQueued_reverts] |
| BLINCT-BURN-L01 | ADMIN | true | true | true | false | PolicyDependency_NotActive(I) | No action/key acquired | Covered: [test][test_givenDisabledInventory_whenBurnQueued_reverts] |
| BLINCT-BURN-L08 | ADMIN | true | true | true | true | Queue succeeds after local disable/reEnable within grace | One metadata record and shared key | Covered: [test][test_givenReEnabled_whenQueued_thenOneAction] |

Read-only queue getters have no lifecycle gate. After admission, assert `inventory()==I`, `nextActionId==id+1`, one sub-action `(I,selector,0x)`, destination I, one state record `(K,keccak256(abi.encode(TL)))`, and `pendingActionId(K)==id`. `maxConfigKeysPerBatch()==15` is inherited; the typed wrappers always queue one action and one key.

## Queue conflicts and economics

Both operations share `K=keccak256(abi.encode(I,keccak256(abi.encode(burnSurplus.selector))))`. The committed hash is `keccak256(abi.encode(TL))`; the destination is I. Queue event order: `ConfigStateQueued`, `TimelockSubActionQueued`, `TimelockActionQueued`; assert every field, including scoped key, proposer, selector, payload hash, action hash and timestamps. Queueing reserves no OHM. Fixed units: OHM has 9 decimals; provider idle/claims=50e9.

| ID | Caller | Pre-state / operation | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-P01 | ADMIN | Burn pending; queue rescue | ConfigKeyPending(key,owner) | No new ID/key | Covered: [test][test_givenBurnPending_whenRescueQueued_reverts] |
| BLINCT-BURN-P02 | ADMIN | Rescue pending; queue burn | ConfigKeyPending(key,owner) | No new ID/key | Covered: [test][test_givenRescuePending_whenBurnQueued_reverts] |
| BLINCT-BURN-P03 | ADMIN | Same operation pending | ConfigKeyPending(key,owner) | Original action unchanged | Covered: [test][test_givenSameActionPending_whenQueued_reverts] |
| BLINCT-BURN-P04 | ADMIN | Core active/enabled flags varied independently; seed all four pairs | Queue succeeds | No Core lifecycle dependency | Covered: [test][test_givenAnyCoreLifecycle_whenQueued_thenIndependent]; [test][test_givenEachCoreLifecyclePair_whenQueued_thenIndependent] |
| BLINCT-BURN-P05 | ADMIN | Surplus=0 both at queue and execution | Executable no-op | Release queue/key; no Inventory surplus event | Covered: [test][test_givenNoSurplus_whenExecuted_thenNoInventoryEventAndKeyReleased] |
| BLINCT-BURN-P06 | ADMIN | Surplus=1e9 at queue; another 2e9 arrives before execution | Execute live surplus 3e9 | Idle/claims remain 50e9; supply -3e9 | Covered: [test][test_givenSurplusArrivesDuringNotice_whenExecuted_thenLiveAmount] |
| BLINCT-BURN-P07 | ADMIN | Queue at T with key free | Return ID | queuedAt=T; executableAt=T+1day; expiresAt=T+4days; the three queue events above and one stored configuration-state record | Covered: [test][test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents] |

## Invalid read-back indices

Use a valid pending action; fuzz all view callers, independent of their roles or policy lifecycle.

| ID | Caller | Read | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-I01 | Fuzz all callers | getQueuedSubAction(id,index), fuzz index in 1..MAX256; seed 1,MAX256 | ITimelockBatchQueue_SubActionIndexOutOfBounds(id,index,1) | No writes | Covered: [test][test_whenSubActionIndexOutOfBounds_reverts]; [test][test_whenSubActionIndexAtBounds_reverts] |
| BLINCT-BURN-I02 | Fuzz all callers | getQueuedConfigState(id,0,stateIndex), fuzz stateIndex in 1..MAX256; seed 1,MAX256 | IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(id,0,stateIndex,1) | No writes | Covered: [test][test_whenConfigStateIndexOutOfBounds_reverts]; [test][test_whenConfigStateIndexAtBounds_reverts] |
| BLINCT-BURN-I03 | Fuzz all callers | getQueuedConfigState(id,index,0), fuzz index in 1..MAX256; seed 1,MAX256 | IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(id,index,0,0); count=0 and destination=0 at absent index | No writes | Covered: [test][test_whenSubActionStateIndexOutOfBounds_reverts]; [test][test_whenSubActionStateIndexAtBounds_reverts] |

## Dependency identity

The immutable target can change its reported Kernel through Kernel migration.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-D01 | ADMIN | I reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenTargetKernelDrift_whenQueued_reverts] |

## Inherited arithmetic boundaries

No public numeric queue input. These are explicit storage/time boundary fixtures.

| ID | Caller | Boundary | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-N01 | ADMIN | nextActionId=MAX64 | Panic(0x11) from inherited checked increment | No queue/key/ID mutation | Covered: [test][test_givenExhaustedCounter_whenQueued_revertsWithoutPartialState] |
| BLINCT-BURN-N02 | ADMIN | T=MAX48-4days | Success; expiresAt=MAX48 | No truncation | Covered: [test][test_givenMaximumExpiry_whenQueued_thenNoTruncation] |
| BLINCT-BURN-N03 | ADMIN | T=MAX48-4days+1 | Panic(0x11) from inherited expiry addition | No queue/key mutation | Covered: [test][test_givenExpiryAdditionOverflows_whenQueued_revertsWithoutPartialState] |
| BLINCT-BURN-N04 | ADMIN | nextActionId=MAX64-1; free key | Return MAX64-1; nextActionId=MAX64 | One valid pending action | Covered: [test][test_givenLastAvailableId_whenQueued_thenMaximumCounter] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-BURN-L09 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; empty batch where exposed | BurnerLoans_PolicyNotActive(TL) | No ID, guard, payload or committed log | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts] |
| BLINCT-BURN-L10 | Fuzz all callers | true | false | ROLES code rejects; empty batch where exposed | NotEnabled() | No ID, guard, payload or committed log | Covered: [test][test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts] |
| BLINCT-BURN-A05 | Fuzz outside both accepted proposer roles | true | true | Target inactive or required metadata rejects; empty batch where exposed | NotAuthorised() | No ID, guard, payload or committed log | Covered: [test][test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts] |

[test_givenBurnerLoansAdmin_whenBurnQueued_thenNoticePrecedesBurn]: ./queueBurnSurplus.t.sol#L31
[test_givenPermittedProposer_whenQueued_thenExactMetadataAndEvents]: ./queueBurnSurplus.t.sol#L58
[test_givenEachPermittedRole_whenQueued_thenExactMetadata]: ./queueBurnSurplus.t.sol#L72
[test_whenUnauthorizedProposer_reverts]: ./queueBurnSurplus.t.sol#L94
[test_givenAnotherController_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L103
[test_givenClearedController_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L112
[test_givenActiveDisabledTimelock_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L121
[test_givenInactiveTimelock_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L139
[test_givenInactiveTarget_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L151
[test_givenDisabledInventory_whenBurnQueued_reverts]: ./queueBurnSurplus.t.sol#L46
[test_givenReEnabled_whenQueued_thenOneAction]: ./queueBurnSurplus.t.sol#L177
[test_givenBurnPending_whenRescueQueued_reverts]: ./queueRescueSurplus.t.sol#L190
[test_givenRescuePending_whenBurnQueued_reverts]: ./queueBurnSurplus.t.sol#L198
[test_givenSameActionPending_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L185
[test_givenAnyCoreLifecycle_whenQueued_thenIndependent]: ./queueBurnSurplus.t.sol#L211
[test_givenEachCoreLifecyclePair_whenQueued_thenIndependent]: ./queueBurnSurplus.t.sol#L221
[test_givenNoSurplus_whenExecuted_thenNoInventoryEventAndKeyReleased]: ./queueBurnSurplus.t.sol#L232
[test_givenSurplusArrivesDuringNotice_whenExecuted_thenLiveAmount]: ./queueBurnSurplus.t.sol#L249
[test_whenSubActionIndexOutOfBounds_reverts]: ./queueBurnSurplus.t.sol#L312
[test_whenSubActionIndexAtBounds_reverts]: ./queueBurnSurplus.t.sol#L325
[test_whenConfigStateIndexOutOfBounds_reverts]: ./queueBurnSurplus.t.sol#L348
[test_whenConfigStateIndexAtBounds_reverts]: ./queueBurnSurplus.t.sol#L361
[test_whenSubActionStateIndexOutOfBounds_reverts]: ./queueBurnSurplus.t.sol#L384
[test_whenSubActionStateIndexAtBounds_reverts]: ./queueBurnSurplus.t.sol#L397
[test_givenTargetKernelDrift_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L163
[test_givenExhaustedCounter_whenQueued_revertsWithoutPartialState]: ./queueBurnSurplus.t.sol#L270
[test_givenMaximumExpiry_whenQueued_thenNoTruncation]: ./queueBurnSurplus.t.sol#L287
[test_givenExpiryAdditionOverflows_whenQueued_revertsWithoutPartialState]: ./queueBurnSurplus.t.sol#L299
[test_givenLastAvailableId_whenQueued_thenMaximumCounter]: ./queueBurnSurplus.t.sol#L279
[test_givenInactiveDisabledTimelock_whenQueued_reverts]: ./queueBurnSurplus.t.sol#L127
[test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBurnSurplus.t.sol#L420
[test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBurnSurplus.t.sol#L446
[test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts]: ./queueBurnSurplus.t.sol#L466
