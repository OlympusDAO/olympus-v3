# PriceCacherTask.changeKernel coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-KERNEL`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
priceCache() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-KERNEL-A01 | Fuzz all non-Kernel callers | true | true | Caller differs from current Kernel; retain zero | KernelAdapter_OnlyKernel(caller); binding unchanged | Covered: [test][test_whenCallerIsNotKernel_reverts] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-KERNEL-L01 | Current Kernel | false | false | Paused/inactive subject; legitimate Kernel migration | Same binding update; no business-action activity gate | Covered: [test][test_givenInactivePaused_whenKernelMigrates] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-KERNEL-I01 | Current Kernel | true | true | Kernel supplies zero or same Kernel | Inherited adapter currently assigns the supplied address; define zero-binding policy before changing this framework behavior | Covered: [test][test_whenKernelAssignsSameOrZeroBinding] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-KERNEL-P01 | Current Kernel | Fuzz true/false | Fuzz true/false | Current Kernel supplies replacement; read membership from arbitrary callers across independent lifecycle states | Update kernel() only; preserve enablement/history; isActive reads new Kernel | Covered: [test][test_whenCurrentKernelMigrates], [test][test_whenMigrationLifecycleBoundarySeedsUsed] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePaused_whenKernelMigrates]: changeKernel.t.sol#L48
[test_whenCallerIsNotKernel_reverts]: changeKernel.t.sol#L9
[test_whenCurrentKernelMigrates]: changeKernel.t.sol#L20
[test_whenKernelAssignsSameOrZeroBinding]: changeKernel.t.sol#L58
[test_whenMigrationLifecycleBoundarySeedsUsed]: changeKernel.t.sol#L70
