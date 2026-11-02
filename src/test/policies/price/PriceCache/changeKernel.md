# PriceCache.changeKernel coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-KERNEL`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
PRICE() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-KERNEL-A01 | Fuzz all non-Kernel callers | true | true | Caller differs from current Kernel; retain zero | KernelAdapter_OnlyKernel(caller); binding unchanged | Covered: [test][test_whenCallerIsNotKernel_reverts] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-KERNEL-L01 | Current Kernel | false | false | Paused/inactive subject; legitimate Kernel migration | Same binding update; no business-action activity gate | Covered: [test][test_givenInactivePaused_whenKernelMigrates] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-KERNEL-I01 | Current Kernel | true | true | Kernel supplies zero or same Kernel | Inherited adapter currently assigns the supplied address; define zero-binding policy before changing this framework behavior | Covered: [test][test_whenKernelAssignsSameOrZeroBinding] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-KERNEL-P01 | Current Kernel | true | true | Current Kernel supplies replacement Kernel | Update kernel() only; preserve enablement/history; isActive reads new Kernel | Covered: [test][test_whenCurrentKernelMigrates] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_whenCallerIsNotKernel_reverts]: changeKernel.t.sol#L10
[test_givenInactivePaused_whenKernelMigrates]: changeKernel.t.sol#L34
[test_whenKernelAssignsSameOrZeroBinding]: changeKernel.t.sol#L47
[test_whenCurrentKernelMigrates]: changeKernel.t.sol#L21
