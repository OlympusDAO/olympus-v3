# setExecutionGasLimit scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: RDTask setExecutionGasLimit and executionGasLimit getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorTask; own inactivity uses `RevenueDistributorTask_PolicyNotActive(Task)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one ExecutionGasLimitSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Local active | Local enabled | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-EXECUTION-GAS-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | true | Fuzz 0..`type(uint32).max`; seed 0,1,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsExecutionGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-A02 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | false | Fuzz 0..`type(uint32).max`; seed 0,1,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsExecutionGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-EXECUTION-GAS-P02 | Fuzz permitted role caller | true | false | true | true | Valid changed value | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsValidExecutionGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-L01 | Fuzz permitted role caller | false | true | true | true | Valid changed value | RevenueDistributorTask_PolicyNotActive(Task) before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |

## Invalid inputs

| ID | Caller | Local active | Local enabled | Current execution limit | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-EXECUTION-GAS-I01 | Fuzz permitted role caller | true | true | Any valid | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidExecutionGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-I02 | Fuzz permitted role caller | true | false | Any valid | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidExecutionGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |

## Numeric inputs and extremes

| ID | Caller | Local enabled | Current execution limit | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-EXECUTION-GAS-P01 | Fuzz permitted role caller | true | Different from input | Fuzz 1..uint32.MAX excluding current; seed 1,MAX | Success | executionGasLimit and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidExecutionGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-P04 | Fuzz permitted role caller | false | Different from input | Fuzz 1..uint32.MAX excluding current; seed 1,MAX | Success | executionGasLimit and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidExecutionGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-P03 | Fuzz permitted role caller | true | Same as input | Current valid value | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |
| RDTASK-EXECUTION-GAS-P05 | Fuzz permitted role caller | false | Same as input | Current valid value | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet] |

[test_whenUnauthorizedCallerSetsExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L10

[test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp]: ./setExecutionGasLimit.t.sol#L146
[test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L41

[test_givenRoleAndNumericBoundaries_whenExecutionGasLimitSet]: ./setExecutionGasLimit.t.sol#L177

[test_whenPermittedCallerSetsValidExecutionGas_updatesValue]: ./setExecutionGasLimit.t.sol#L111

[test_whenPermittedCallerSetsInvalidExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L77

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-EXECUTION-GAS-L02 | Any address, fuzz, without authorization exclusions | false | false | Task locally disabled, then Kernel-deactivated; Fuzz full `uint32` input type without bounds/exclusions | `RevenueDistributorTask_PolicyNotActive(task)` before local enablement (where required), caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst]: ./setExecutionGasLimit.t.sol#L419
