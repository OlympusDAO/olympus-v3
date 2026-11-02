# BurnerLoansInventoryConfigTimelock.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Concrete behavior: [_beforeReEnable](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L308).

## Scope and fixtures

`MAXn` denotes `2**n-1`; time is measured in seconds.

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Dependency validation contract

The immutable Inventory target must be compatible and Kernel-active, but may be locally disabled so rescue remains available. Burn-specific queue/execute paths additionally require enabled Inventory. Controller selection is separate authorization; Core is an upstream identity whose activity/enablement does not gate recovery.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Inventory → `BurnerLoansInventoryTimelock_InvalidInventory(I)`.

## Authorization

Local disabled, own active, cached ROLES; I is bound/active and selects TL. Re-enable has initialized history and valid grace.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-REENABLE-A01 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | Permitted | Success | enabled=true; timestamp=now; Enabled then Transition(caller,true,empty,now) | Covered: [test][test_givenReadyTarget_whenActivated_thenExactTransition]; [test][test_givenWithinGrace_whenReEnabled_thenInclusiveTransition]; [test][test_givenEachPermittedRole_whenReEnabled_thenExactTransition]; [test][test_givenGraceEndpointSeeds_whenReEnabled_thenInclusiveTransition] |
| BLINCT-REENABLE-A02 | Fuzz outside both role sets | Unauthorized | NotAuthorised() | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenActivated_reverts] |

## Lifecycle

Use a fuzzed permitted caller (ADMIN-only, BL-admin-only or overlap, with each class seeded). A paused I may acquire/enable its recovery queue; only the burn service needs I enabled.

| ID | Caller | Local active | Local enabled | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-REENABLE-L01 | Fuzz permitted caller | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenOwnPolicyInactive_whenActivated_reverts]; [test][test_givenOwnPolicyInactive_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-L02 | Fuzz permitted caller | true | true | true | true | NotDisabled() | No second transition | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts]; [test][test_givenAlreadyEnabled_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-L03 | Fuzz permitted caller | false | true | true | true | NotDisabled() | Local transition guard wins | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts]; [test][test_givenAlreadyEnabled_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-D01 | Fuzz permitted caller | true | false | true | false | Success | Recovery queue enabled; I unchanged | Covered: [test][test_givenReadyTarget_whenActivated_thenExactTransition]; [test][test_givenEachPermittedRole_whenReEnabled_thenExactTransition] |
| BLINCT-REENABLE-D03 | Fuzz permitted caller | true | false | false | true | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInventoryInactive_whenActivated_reverts]; [test][test_givenInventoryInactive_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-D04 | Fuzz permitted caller | true | false | false | false | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInventoryInactive_whenActivated_reverts]; [test][test_givenInventoryInactive_whenEachPermittedRoleReEnables_reverts] |

## Bindings

All local and time prerequisites pass. A different Kernel is produced by reachable Kernel migration.

| ID | Caller | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-REENABLE-D02 | Fuzz permitted caller | I controller is another nonzero address | NotAuthorised() | Unchanged | Covered: [test][test_givenAnotherController_whenActivated_reverts]; [test][test_givenAnotherController_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-D06 | Fuzz permitted caller | I controller is zero | NotAuthorised() | Unchanged | Covered: [test][test_givenClearedController_whenActivated_reverts]; [test][test_givenClearedController_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-D05 | Fuzz permitted caller | I reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenTargetKernelDrift_whenActivated_reverts]; [test][test_givenTargetKernelDrift_whenEachPermittedRoleReEnables_reverts] |

## Grace boundaries

L=`lastTransitionAt`, G=`gracePeriod` in 1..MAX32, D=L+G. Fuzz L in 1..MAX48-G and now independently; seed L=1 and MAX48-G. Local disabled/active; target readiness and caller authorization pass. Order is local-disabled check, NeverEnabled, caller authorization, narrowed deadline/grace, then activation checks.

| ID | Caller | Time / history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-REENABLE-N01 | Fuzz permitted caller | L=0 | NeverEnabled() | Unchanged | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts]; [test][test_givenNeverEnabled_whenEachPermittedRoleReEnables_reverts] |
| BLINCT-REENABLE-N02 | Fuzz permitted caller | Fuzz now in L..D; seed L,D-1 when G>0,D | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); pending work preserved | Covered: [test][test_givenWithinGrace_whenReEnabled_thenInclusiveTransition]; [test][test_givenGraceEndpointSeeds_whenReEnabled_thenInclusiveTransition] |
| BLINCT-REENABLE-N03 | Fuzz permitted caller | Fuzz now in D+1..MAX48 when nonempty; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_givenExpiredGrace_whenReEnabled_reverts]; [test][test_givenExpiredGraceEndpointSeeds_whenReEnabled_reverts] |
| BLINCT-REENABLE-N04 | Fuzz permitted caller | Fuzz L in MAX48-G+1..MAX48; seed both ends; L+G>MAX48 | SafeCastOverflowedUintDowncast(48,L+G) | Unchanged | Covered: [test][test_givenGraceOverflow_whenReEnabled_reverts]; [test][test_givenGraceOverflowEndpointSeeds_whenReEnabled_reverts] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_givenReadyTarget_whenActivated_thenExactTransition]: ./reEnable.t.sol#L31
[test_givenWithinGrace_whenReEnabled_thenInclusiveTransition]: ./reEnable.t.sol#L210
[test_givenEachPermittedRole_whenReEnabled_thenExactTransition]: ./reEnable.t.sol#L289
[test_givenGraceEndpointSeeds_whenReEnabled_thenInclusiveTransition]: ./reEnable.t.sol#L325
[test_givenUnauthorizedCaller_whenActivated_reverts]: ./reEnable.t.sol#L59
[test_givenOwnPolicyInactive_whenActivated_reverts]: ./reEnable.t.sol#L74
[test_givenOwnPolicyInactive_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L421
[test_givenAlreadyEnabled_whenActivated_reverts]: ./reEnable.t.sol#L91
[test_givenAlreadyEnabled_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L432
[test_givenInventoryInactive_whenActivated_reverts]: ./reEnable.t.sol#L103
[test_givenInventoryInactive_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L449
[test_givenAnotherController_whenActivated_reverts]: ./reEnable.t.sol#L122
[test_givenAnotherController_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L466
[test_givenClearedController_whenActivated_reverts]: ./reEnable.t.sol#L137
[test_givenClearedController_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L477
[test_givenTargetKernelDrift_whenActivated_reverts]: ./reEnable.t.sol#L152
[test_givenTargetKernelDrift_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L488
[test_givenNeverEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L190
[test_givenNeverEnabled_whenEachPermittedRoleReEnables_reverts]: ./reEnable.t.sol#L499
[test_givenExpiredGrace_whenReEnabled_reverts]: ./reEnable.t.sol#L239
[test_givenExpiredGraceEndpointSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L366
[test_givenGraceOverflow_whenReEnabled_reverts]: ./reEnable.t.sol#L263
[test_givenGraceOverflowEndpointSeeds_whenReEnabled_reverts]: ./reEnable.t.sol#L396
