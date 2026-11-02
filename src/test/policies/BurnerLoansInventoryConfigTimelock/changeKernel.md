# BurnerLoansInventoryConfigTimelock.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91), [isActive](../../../Kernel.sol#L139), [configureDependencies](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L84).

The inherited hook accepts only the policy's current Kernel, independently of local activity/enablement. It changes the Kernel pointer, not cached ROLES, Inventory, queue state or token balances. `configureDependencies` separately refreshes ROLES through the new Kernel. These are framework semantics, not a public component replacement API.

## Authorization

| ID | Caller | Current Kernel | Requested Kernel | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-KERNEL-A01 | Fuzz caller excluding current Kernel, including ADMIN and EMERGENCY | K0 | Deployed K1 | KernelAdapter_OnlyKernel(caller) | No pointer/state/log change | Covered: [test][test_whenCallerIsNotCurrentKernel_reverts]; [test][test_givenAdminOrEmergency_whenKernelChanged_reverts] |
| BLINCT-KERNEL-A02 | K0 | K0 | Deployed K1 | Success | kernel=K1; immutable Inventory and queued actions unchanged; no hook event | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges] |
| BLINCT-KERNEL-A03 | Former Kernel K0 after authorized change | K1 | K2 | KernelAdapter_OnlyKernel(K0) | No pointer/state/log change | Covered: [test][test_givenKernelChanged_whenFormerKernelCalls_reverts] |

## Lifecycle

Use K0 as caller. Local active is membership in K0 immediately before the hook.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-KERNEL-L01 | K0 | true | true | Success | Pointer only; local enabled stays true | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges] |
| BLINCT-KERNEL-L02 | K0 | true | false | Success | Pointer only; local enabled stays false | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges] |
| BLINCT-KERNEL-L03 | K0 | false | true | Success | No own-activity gate | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges] |
| BLINCT-KERNEL-L04 | K0 | false | false | Success | No own-activity gate | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges] |

## Framework input semantics

The generic hook does not validate the new Kernel or reject an unchanged pointer. Governance migration must use a real Kernel; no new Burner Loans validation is invented here.

| ID | Caller | Requested Kernel | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-KERNEL-I01 | K0 | Zero | Assign zero per inherited hook | No other state changes; ordinary Kernel-dependent calls cannot operate | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_whenNextKernelZero_thenOnlyPointerChanges] |
| BLINCT-KERNEL-I02 | K0 | EOA | Assign EOA per inherited hook | No other state changes; ordinary Kernel-dependent calls cannot operate | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_whenNextKernelEOA_thenOnlyPointerChanges] |
| BLINCT-KERNEL-P01 | K0 | K0 | Success | Pointer unchanged; no event or side effects | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test][test_whenNextKernelUnchanged_thenNoOtherEffects] |

## Migration readiness

Pending recovery exists before migration; time and local admission otherwise pass.

| ID | Caller | Migration state | Execution / read | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-KERNEL-D01 | Fuzz executor | TL on K1 but not activated in K1 | isActive=false; ready execution rejects BurnerLoans_PolicyNotActive(TL) | Pending action/key retained | Covered: [test][test_givenNewKernelNotActivated_whenExecuted_reverts] |
| BLINCT-KERNEL-D02 | Fuzz executor | TL active in K1; I still reports K0 | Ready execution rejects PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Pending action/key retained | Covered: [test][test_givenOnlyTimelockMigrated_whenExecuted_reverts] |
| BLINCT-KERNEL-D03 | Fuzz executor | Both policies migrated/active in K1; TL selected; ROLES refreshed | isActive=true; ready execution succeeds | Original immutable I receives live surplus recovery; original metadata/key cleanup | Covered: [test][test_givenBothPoliciesMigrated_whenExecuted_thenOriginalRecoverySucceeds] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_whenCallerIsNotCurrentKernel_reverts]: ./changeKernel.t.sol#L30
[test_givenAdminOrEmergency_whenKernelChanged_reverts]: ./changeKernel.t.sol#L214
[test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]: ./changeKernel.t.sol#L46
[test_givenEachLifecyclePair_whenMigrated_thenOnlyPointerChanges]: ./changeKernel.t.sol#L177
[test_givenKernelChanged_whenFormerKernelCalls_reverts]: ./changeKernel.t.sol#L78
[test_whenNextKernelZero_thenOnlyPointerChanges]: ./changeKernel.t.sol#L193
[test_whenNextKernelEOA_thenOnlyPointerChanges]: ./changeKernel.t.sol#L201
[test_whenNextKernelUnchanged_thenNoOtherEffects]: ./changeKernel.t.sol#L209
[test_givenNewKernelNotActivated_whenExecuted_reverts]: ./changeKernel.t.sol#L96
[test_givenOnlyTimelockMigrated_whenExecuted_reverts]: ./changeKernel.t.sol#L117
[test_givenBothPoliciesMigrated_whenExecuted_thenOriginalRecoverySucceeds]: ./changeKernel.t.sol#L141
