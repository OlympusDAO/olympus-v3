# BurnerLoansConfigTimelock.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L101). Coverage is recorded in the Test column.

Construction validates Config compatibility and its derived Core interface without runtime readiness checks.

## Domains and notation

Scenario scope: `BLCT-CONSTRUCTOR` identifies this contract/function.

Kernel,Config required interfaces Config,IConfigOperator,IEnabler. `configKernel` is the readable Kernel reported by Config. Incompatible Config addresses/interfaces use the required `BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config)` name, including Config=0; a readable foreign Kernel uses the separate `PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel)` error.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Dependency compatibility

Fixed for this table: Accounting / events: No deployment or committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-CONSTRUCTOR-D01 | Fuzz all deployers | Config lacks IBurnerLoansConfig; other required interfaces advertised | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenMissingIBurnerLoansConfig_whenConstructed_reverts][test_givenMissingIBurnerLoansConfig_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D02 | Fuzz all deployers | Config lacks IEnabler; other required interfaces advertised | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenMissingIEnabler_whenConstructed_reverts][test_givenMissingIEnabler_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D03 | Fuzz all deployers | Config reports another Kernel | PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel) | Covered: [test_givenForeignConfigKernel_whenConstructed_reverts][test_givenForeignConfigKernel_whenConstructed_reverts] |

## Invalid inputs

Fixed for this table: Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-CONSTRUCTOR-I01 | Fuzz all deployers | Config=0 | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenZeroConfig_whenConstructed_reverts][test_givenZeroConfig_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-I02 | Fuzz all deployers | Config is EOA | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenEoaConfig_whenConstructed_reverts][test_givenEoaConfig_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-I03 | Fuzz all deployers | Config lacks IConfigOperator; other required interfaces advertised | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenMissingIConfigOperator_whenConstructed_reverts][test_givenMissingIConfigOperator_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-I04 | Fuzz all deployers | Config supportsInterface reverts | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenInterfaceProbeReverts_whenConstructed_reverts][test_givenInterfaceProbeReverts_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-I05 | Fuzz all deployers | Config supportsInterface returns malformed data | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test_givenMalformedInterfaceProbe_whenConstructed_reverts][test_givenMalformedInterfaceProbe_whenConstructed_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-CONSTRUCTOR-P01 | Fuzz all deployers | Config kernel getter reverts | PolicyDependency_InvalidDependency(Config) | No deployment or committed logs | Covered: [test_givenKernelGetterReverts_whenConstructed_reverts][test_givenKernelGetterReverts_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-P02 | Fuzz all deployers | Compatible Config; Config active=true; Config enabled=true | Success | Immutable Config/Kernel; disabled; grace 7 days; delay1 day/window3 days; no queued actions | Covered: [test_givenConfigActiveTrue_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults][test_givenConfigActiveTrue_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults] |
| BLCT-CONSTRUCTOR-P03 | Fuzz all deployers | Compatible Config; Config active=true; Config enabled=false | Success | Immutable Config/Kernel; disabled; grace 7 days; delay1 day/window3 days; no queued actions | Covered: [test_givenConfigActiveTrue_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults][test_givenConfigActiveTrue_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults] |
| BLCT-CONSTRUCTOR-P04 | Fuzz all deployers | Compatible Config; Config active=false; Config enabled=true | Success | Immutable Config/Kernel; disabled; grace 7 days; delay1 day/window3 days; no queued actions | Covered: [test_givenConfigActiveFalse_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults][test_givenConfigActiveFalse_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults] |
| BLCT-CONSTRUCTOR-P05 | Fuzz all deployers | Compatible Config; Config active=false; Config enabled=false | Success | Immutable Config/Kernel; disabled; grace 7 days; delay1 day/window3 days; no queued actions | Covered: [test_givenConfigActiveFalse_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults][test_givenConfigActiveFalse_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `burnerLoans`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Construction without runtime readiness

| ID | Caller | Target condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-CONSTRUCTOR-P06 | Fuzz deployer | Consumed interfaces and same-Kernel binding valid; target activity, enabled and selected-operator reads revert | Success | Target bound; queue disabled; no readiness/selection reads | Covered: [test][test_givenRuntimeReadinessGettersRevert_whenConstructed] |

## Core interface admission

Config otherwise satisfies its existing interface and Kernel checks. Read Config.facility() as a canonical address; then require IBurnerLoansCore because queue validation calls Core.depositManager() directly. Do not query Core Kernel, activity or enabled state. Rejection creates no contract or committed logs.

| ID | Caller | Condition | Result | Test |
| --- | --- | --- | --- | --- |
| BLCT-CONSTRUCTOR-D04 | Fuzz deployers | Core is zero | BurnerLoansConfigTimelock_InvalidCore(Core) | Covered: [test][test_givenZeroCore_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D05 | Fuzz deployers | Core is an EOA | BurnerLoansConfigTimelock_InvalidCore(Core) | Covered: [test][test_givenEoaCore_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D06 | Fuzz deployers | Core lacks IBurnerLoansCore | BurnerLoansConfigTimelock_InvalidCore(Core) | Covered: [test][test_givenMissingCoreInterface_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D07 | Fuzz deployers | Core interface probe reverts | BurnerLoansConfigTimelock_InvalidCore(Core) | Covered: [test][test_givenRevertingCoreInterface_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D08 | Fuzz deployers | Core interface probe returns short data | BurnerLoansConfigTimelock_InvalidCore(Core) | Covered: [test][test_givenMalformedCoreInterface_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D09 | Fuzz deployers | Config.facility() reverts | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test][test_givenRevertingCoreBinding_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-D10 | Fuzz deployers | Config.facility() returns non-32-byte or noncanonical address data | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Covered: [test][test_givenMalformedCoreBinding_whenConstructed_reverts]; [dirty word][test_givenNoncanonicalCoreBinding_whenConstructed_reverts] |
| BLCT-CONSTRUCTOR-P07 | Fuzz deployers | Compatible Core; active/enabled flags independently false/true, all four seeded | Success; Config bound, queue disabled, no actions | Covered: [test][test_givenCoreLifecycle_whenConstructed]; [seeds][test_whenCoreLifecycleStatesSeeded_thenAccepted] |
| BLCT-CONSTRUCTOR-P08 | Fuzz deployers | Core Kernel/status getters revert; membership lookup must not occur | Success without Core readiness probes | Covered: [test][test_givenUnreadableCoreLifecycle_whenConstructed] |

[test_givenMissingIBurnerLoansConfig_whenConstructed_reverts]: constructor.t.sol#L25
[test_givenMissingIEnabler_whenConstructed_reverts]: constructor.t.sol#L47
[test_givenForeignConfigKernel_whenConstructed_reverts]: constructor.t.sol#L155
[test_givenZeroConfig_whenConstructed_reverts]: constructor.t.sol#L85
[test_givenEoaConfig_whenConstructed_reverts]: constructor.t.sol#L99
[test_givenMissingIConfigOperator_whenConstructed_reverts]: constructor.t.sol#L66
[test_givenInterfaceProbeReverts_whenConstructed_reverts]: constructor.t.sol#L117
[test_givenMalformedInterfaceProbe_whenConstructed_reverts]: constructor.t.sol#L136
[test_givenKernelGetterReverts_whenConstructed_reverts]: constructor.t.sol#L175
[test_givenConfigActiveTrue_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults]: constructor.t.sol#L188
[test_givenConfigActiveTrue_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults]: constructor.t.sol#L205
[test_givenConfigActiveFalse_givenConfigEnabledTrue_whenConstructed_thenDisabledDefaults]: constructor.t.sol#L222
[test_givenConfigActiveFalse_givenConfigEnabledFalse_whenConstructed_thenDisabledDefaults]: constructor.t.sol#L239
[test_givenRuntimeReadinessGettersRevert_whenConstructed]: ./constructor.t.sol#L256

[test_givenZeroCore_whenConstructed_reverts]: constructor.t.sol#L295

[test_givenEoaCore_whenConstructed_reverts]: constructor.t.sol#L307

[test_givenMissingCoreInterface_whenConstructed_reverts]: constructor.t.sol#L320

[test_givenRevertingCoreInterface_whenConstructed_reverts]: constructor.t.sol#L332

[test_givenMalformedCoreInterface_whenConstructed_reverts]: constructor.t.sol#L348

[test_givenRevertingCoreBinding_whenConstructed_reverts]: constructor.t.sol#L360

[test_givenMalformedCoreBinding_whenConstructed_reverts]: constructor.t.sol#L372

[test_givenNoncanonicalCoreBinding_whenConstructed_reverts]: constructor.t.sol#L384
[test_givenCoreLifecycle_whenConstructed]: constructor.t.sol#L396
[test_whenCoreLifecycleStatesSeeded_thenAccepted]: constructor.t.sol#L411
[test_givenUnreadableCoreLifecycle_whenConstructed]: constructor.t.sol#L424
