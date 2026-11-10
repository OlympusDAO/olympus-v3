# BurnerLoansPayout.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansPayout.sol#L60). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CONSTRUCTOR` identifies this contract/function.

Kernel and Core addresses are bound explicitly. Core must be deployed and advertise IBurnerLoansCore. Payout calls Core.requireNotReentrant() before configuration changes and payout recovery, so Core is a callable guard dependency as well as the immutable credit authority. The constructor validates the interface for that callback; Core must report the supplied Kernel and Core owns Payout admission through Core.setPayout, Core.enable and Core.reEnable. The constructor does not read Core routing or accounting values. Core activity/enablement do not gate deployment. Kernel initialization follows the shared Policy base. Payout starts locally disabled, with configOperator=0.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

On rejection: no deployment, state or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-I01 | Fuzz all deployers | core=0; no Core interface probe | BurnerLoansPayout_InvalidCore(0); no deployment/logs | Covered: [test_whenCoreIsZero_reverts][test_whenCoreIsZero_reverts] |
| BLCU-CONSTRUCTOR-I02 | Fuzz all deployers | Nonzero Core EOA | BurnerLoansPayout_InvalidCore(candidate) | Covered: [test_whenCoreIsEoa_reverts][test_whenCoreIsEoa_reverts] |
| BLCU-CONSTRUCTOR-D01 | Fuzz all deployers | Deployed candidate lacks IBurnerLoansCore | BurnerLoansPayout_InvalidCore(candidate) | Covered: [test_givenMissingCoreInterface_whenDeployed_reverts][test_givenMissingCoreInterface_whenDeployed_reverts] |
| BLCU-CONSTRUCTOR-D02 | Fuzz all deployers | Core ERC165 reverts | BurnerLoansPayout_InvalidCore(candidate) | Covered: [test_givenRevertingCoreInterface_whenDeployed_reverts][test_givenRevertingCoreInterface_whenDeployed_reverts] |
| BLCU-CONSTRUCTOR-D03 | Fuzz all deployers | Core ERC165 malformed | BurnerLoansPayout_InvalidCore(candidate) | Covered: [test_givenMalformedCoreInterface_whenDeployed_reverts][test_givenMalformedCoreInterface_whenDeployed_reverts] |
| BLCU-CONSTRUCTOR-D04 | Fuzz all deployers | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Covered: [test_givenDifferentCoreKernel_whenDeployed_reverts][test_givenDifferentCoreKernel_whenDeployed_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-P02 | Fuzz all deployers | Deployed Core | Success | Kernel/core exact; empty obligations; configOperator=0; locally disabled; flags false; no token movement | Covered: [test_whenPayoutDeployed_thenDisabledWithEmptyObligations][test_whenPayoutDeployed_thenDisabledWithEmptyObligations] |
| BLCU-CONSTRUCTOR-V03 | Fuzz all callers | Initial isEnabled() and configOperator() getters | false, address(0) | No dependency reads or state changes | Covered: [test_whenPayoutDeployed_thenDisabledWithEmptyObligations][test_whenPayoutDeployed_thenDisabledWithEmptyObligations] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `core`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Core compatibility and readiness

| ID | Caller | Core metadata | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-D05 | Fuzz deployers | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | No deployment or committed logs | Covered: [test][test_givenUnreadableCoreMetadata_whenDeployed_reverts] |

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | No deployment or committed logs | Covered: [test][test_givenMalformedCoreKernel_whenDeployed_reverts]; [test][test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts] |

[test_givenDifferentCoreKernel_whenDeployed_reverts]: ./constructor.t.sol#L134
[test_givenMalformedCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L114
[test_givenMissingCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L73
[test_givenRevertingCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L94
[test_whenCoreIsEoa_reverts]: ./constructor.t.sol#L36
[test_whenCoreIsZero_reverts]: ./constructor.t.sol#L19
[test_whenPayoutDeployed_thenDisabledWithEmptyObligations]: ./constructor.t.sol#L48

[test_givenUnreadableCoreMetadata_whenDeployed_reverts]: ./constructor.t.sol#L151

[test_givenMalformedCoreKernel_whenDeployed_reverts]: constructor.t.sol#L167

[test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts]: constructor.t.sol#L184
