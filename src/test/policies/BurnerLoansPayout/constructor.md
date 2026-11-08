# BurnerLoansPayout.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansPayout.sol#L60). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CONSTRUCTOR` identifies this contract/function.

Kernel and Core addresses are bound explicitly. Core must be deployed, advertise IBurnerLoansCore and report the same Kernel. Payout calls Core.requireNotReentrant() before configuration changes and payout recovery, so Core is a callable guard dependency as well as the immutable credit authority. The constructor validates the interface and same-Kernel binding for that callback; it does not call Core for routing or accounting values. Core activity/enablement do not gate deployment. Kernel initialization follows the shared Policy base. Payout starts locally disabled, with configOperator=0.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

On rejection: no deployment, state or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-I01 | Fuzz all deployers | core=0 | BurnerLoansAction_InvalidCore(0); no deployment/logs | Covered: [test_whenCoreIsZero_reverts][test_whenCoreIsZero_reverts] |
| BLCU-CONSTRUCTOR-I02 | Fuzz all deployers | Nonzero Core EOA | BurnerLoansAction_InvalidCore(candidate) | Covered: [test_whenCoreIsEoa_reverts][test_whenCoreIsEoa_reverts] |
| BLCU-CONSTRUCTOR-D01 | Fuzz all deployers | Deployed candidate lacks IBurnerLoansCore | BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenMissingCoreInterface_whenDeployed_reverts][test_givenMissingCoreInterface_whenDeployed_reverts] |
| BLCU-CONSTRUCTOR-D02 | Fuzz all deployers | Core ERC165 reverts | BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenRevertingCoreInterface_whenDeployed_reverts][test_givenRevertingCoreInterface_whenDeployed_reverts] |
| BLCU-CONSTRUCTOR-D03 | Fuzz all deployers | Core ERC165 malformed | BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenMalformedCoreInterface_whenDeployed_reverts][test_givenMalformedCoreInterface_whenDeployed_reverts] |
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

[test_givenDifferentCoreKernel_whenDeployed_reverts]: ./constructor.t.sol#L127
[test_givenMalformedCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L107
[test_givenMissingCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L67
[test_givenRevertingCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L87
[test_whenCoreIsEoa_reverts]: ./constructor.t.sol#L30
[test_whenCoreIsZero_reverts]: ./constructor.t.sol#L18
[test_whenPayoutDeployed_thenDisabledWithEmptyObligations]: ./constructor.t.sol#L42
