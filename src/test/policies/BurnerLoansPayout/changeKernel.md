# BurnerLoansPayout.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage is recorded in the Test column. Apply [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md).

## Domains and behavior

Scenario scope: `BLCU-KERNEL` identifies this contract/function.

Inherited KernelAdapter implementation. Caller must equal Payout's current Kernel. Local enablement does not gate this inherited hook. Core/Payout active/inactive states do not add guards to the inherited hook.

| ID | Caller | Kernel input | Payout active | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-KERNEL-P01 | Current Kernel | Production migration target; boundary zero explicitly exercises unvalidated inherited input | true | Kernel binding changes; routing, immutable Core and payout records unchanged | Covered: [test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test_whenKernelZero_thenInheritedInputAccepted][test_whenKernelZero_thenInheritedInputAccepted] |
| BLCU-KERNEL-P02 | Current Kernel | Production migration target; boundary zero explicitly exercises unvalidated inherited input | false | Kernel binding changes; routing, immutable Core and payout records unchanged | Covered: [test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges][test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]; [test_whenKernelZero_thenInheritedInputAccepted][test_whenKernelZero_thenInheritedInputAccepted] |
| BLCU-KERNEL-P03 | Fuzz caller excluding current Kernel | Any | true | KernelAdapter_OnlyKernel(caller); Unchanged | Covered: [test_whenCallerIsNotCurrentKernel_reverts][test_whenCallerIsNotCurrentKernel_reverts] |
| BLCU-KERNEL-P04 | Fuzz caller excluding current Kernel | Any | false | KernelAdapter_OnlyKernel(caller); Unchanged | Covered: [test_whenCallerIsNotCurrentKernel_reverts][test_whenCallerIsNotCurrentKernel_reverts] |

Co-located getters: kernel,isActive. Standard Kernel migration updates active Payout contracts; include previous Payout contracts with outstanding obligations in the migration set and hand off their local Config authority explicitly. An inactive retiree is not automatically migrated.

- [x] Review expectations before production test implementation.
- [x] Adapt existing Framework/recovery tests and map passing proofs.

[test_whenCallerIsNotCurrentKernel_reverts]: ./changeKernel.t.sol#L27
[test_whenCurrentKernelChangesPointer_thenOnlyPointerChanges]: ./changeKernel.t.sol#L10
[test_whenKernelZero_thenInheritedInputAccepted]: ./changeKernel.t.sol#L19
