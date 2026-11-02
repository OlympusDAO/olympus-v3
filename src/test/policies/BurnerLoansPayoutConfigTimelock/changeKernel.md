# BurnerLoansPayoutConfigTimelock.changeKernel coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [changeKernel](../../../Kernel.sol#L91).

Scenario scope: `BLCUCT-KERNEL`. Inherited Kernel migration hook. Local enablement and the bound Payout's state do not gate this call. Only the current Kernel may change the pointer. This hook does not activate the policy or refresh cached ROLES.

## Authorization

| ID | Caller | Local active | Local enabled | New Kernel | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-KERNEL-A01 | Current Kernel | Fuzz true/false | Fuzz true/false | Distinct deployed Kernel | Success | Only kernel pointer changes; queue, controller, payout, cached ROLES and local transition state unchanged | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges], [test][test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges] |
| BLCUCT-KERNEL-A02 | Fuzz caller excluding current Kernel | Fuzz true/false | Fuzz true/false | Fuzz address; seed valid Kernel and zero | KernelAdapter_OnlyKernel(caller) | No pointer change or committed logs | Covered: [test][test_givenOtherCaller_whenKernelChanged_reverts], [test][test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges] |

## Pointer inputs

The shared hook trusts its Kernel caller; it imposes no candidate-code or unchanged-address validation.

| ID | Caller | Candidate | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-KERNEL-I01 | Current Kernel | Current Kernel | Success | Same pointer; no new activation or queue change | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges], [test][test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges] |
| BLCUCT-KERNEL-I02 | Current Kernel | Zero | Success under shared hook | Pointer becomes zero; unusable for product operation; not a supported deployment flow | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges], [test][test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges] |
| BLCUCT-KERNEL-I03 | Current Kernel | Nonzero EOA | Success under shared hook | Pointer stores exactly; no candidate getter is called | Covered: [test][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges], [test][test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges] |

## Migration coordination

| ID | Caller | Sequence | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-KERNEL-D01 | Governance through framework | Move timelock but leave its bound Payout on old Kernel; activate timelock on new Kernel | Queue/enable/reEnable reject PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | Existing queues do not retarget or disappear; cancellation remains possible when locally active/enabled with new EMERGENCY authorization | Covered: [test][test_givenOnlyTimelockMigrated_whenUsed_thenBindingRejectedAndCancellationAvailable] |
| BLCUCT-KERNEL-D02 | Governance through framework | Move both bound policies; initialize roles/activation on new Kernel | Ready binding restored | Same concrete Payout and queue commitments; target role/Treasury changes are revalidated by the relevant stored hash | Covered: [test][test_givenBothPoliciesMigrated_whenExecuted_thenOriginalTargetPays] |

- [x] Map focused framework and product-binding tests without inventing validation on the shared hook.

[test_givenBothPoliciesMigrated_whenExecuted_thenOriginalTargetPays]: ./changeKernel.t.sol#L96
[test_givenOnlyTimelockMigrated_whenUsed_thenBindingRejectedAndCancellationAvailable]: ./changeKernel.t.sol#L60
[test_givenOtherCaller_whenKernelChanged_reverts]: ./changeKernel.t.sol#L43
[test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]: ./changeKernel.t.sol#L21
[test_whenPointerBoundarySeedsUsed_thenOnlyPointerChanges]: ./changeKernel.t.sol#L129
