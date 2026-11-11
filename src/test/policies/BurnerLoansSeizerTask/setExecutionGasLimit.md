# BurnerLoansSeizerTask.setExecutionGasLimit coverage plan

Source: [setExecutionGasLimit](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L192). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-EXECUTION-GAS` identifies this contract/function.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN or BL admin, local enablement is independent; own policy activity is enforced before role/input validation;uint32 budget. Nonzero accepted without practical minimum.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTION-GAS-A01 | Fuzz caller with neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE; exclude all holders of either | Any budget | NotAuthorised | Covered: [test][test_whenCallerHasNeitherRole_whenGasLimitSet_reverts] |
| BLSEIZ-EXECUTION-GAS-A02 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenGasLimitSet], [test][test_whenRoleAndNumericBoundariesSeeded] |
| BLSEIZ-EXECUTION-GAS-A03 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenGasLimitSet], [test][test_whenRoleAndNumericBoundariesSeeded] |
| BLSEIZ-EXECUTION-GAS-A04 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenGasLimitSet], [test][test_whenRoleAndNumericBoundariesSeeded] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTION-GAS-P01 | Fuzz permitted role caller | gas=0 | InvalidExecutionGasLimit | Unchanged | Partial: [test][test_whenGasLimitZero_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-EXECUTION-GAS-P02 | Fuzz permitted role caller | gas1..MAX32; changed value; seed1,MAX32 | Store exact budget; emit once | No immediate task work; too-small gas tested through execute | Covered: [test][test_givenPermittedCaller_whenGasLimitSet], [test][test_whenRoleAndNumericBoundariesSeeded] |

Co-located API assertions: `executionGasLimit`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTION-GAS-P03 | Fuzz ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holder | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no body/token/module calls or committed logs | Partial: [test][test_givenInactiveTask_whenGasLimitSet_reverts]; other permitted caller partitions remain planned |

## Test organization

[setExecutionGasLimit.t.sol](./setExecutionGasLimit.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Same configuration value

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTION-GAS-P04 | ADMIN_ROLE holder | Exact current budget | No-op after validation | No event or setter write | Covered: [test][test_whenGasLimitUnchanged_thenNoEvent] |

[test_givenInactiveTask_whenGasLimitSet_reverts]: ./setExecutionGasLimit.t.sol#L78
[test_givenPermittedCaller_whenGasLimitSet]: ./setExecutionGasLimit.t.sol#L19
[test_whenCallerHasNeitherRole_whenGasLimitSet_reverts]: ./setExecutionGasLimit.t.sol#L50
[test_whenGasLimitUnchanged_thenNoEvent]: ./setExecutionGasLimit.t.sol#L71
[test_whenGasLimitZero_reverts]: ./setExecutionGasLimit.t.sol#L65
[test_whenRoleAndNumericBoundariesSeeded]: ./setExecutionGasLimit.t.sol#L39
