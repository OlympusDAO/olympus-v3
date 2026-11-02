# setMinimumGasToAttempt scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: RDTask setMinimumGasToAttempt and minimumGasToAttempt getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorTask; own inactivity uses `RevenueDistributorTask_PolicyNotActive(Task)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one MinimumGasToAttemptSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Local active | Local enabled | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-MINIMUM-GAS-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | true | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,reserve,reserve+1 when valid,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsMinimumGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-A02 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | false | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,reserve,reserve+1 when valid,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsMinimumGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-MINIMUM-GAS-P02 | Fuzz permitted role caller | true | false | true | true | Valid | Valid changed value above reserve | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-L01 | Fuzz permitted role caller | false | true | true | true | Valid | Valid changed value above reserve | RevenueDistributorTask_PolicyNotActive(Task) before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |

## Invalid inputs

| ID | Caller | Local active | Local enabled | Current reserve | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-MINIMUM-GAS-I01 | Fuzz permitted role caller | true | true | Fuzz valid reserve | Any valid | Fuzz 0..reserve; seed 0,1,reserve-1,reserve | RevenueDistributorTask_InvalidMinimumGasToAttempt() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidMinimumGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-I02 | Fuzz permitted role caller | true | false | Fuzz valid reserve | Any valid | Fuzz 0..reserve; seed 0,1,reserve-1,reserve | RevenueDistributorTask_InvalidMinimumGasToAttempt() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidMinimumGas_reverts], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |

## Numeric inputs and extremes

| ID | Caller | Local enabled | Current reserve | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-MINIMUM-GAS-P01 | Fuzz permitted role caller | true | Repeat 1 and 100,000 | Different from input | Fuzz reserve+1..uint32.MAX excluding current; seed reserve+1,MAX | Success | minimumGasToAttempt and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-P04 | Fuzz permitted role caller | false | Repeat 1 and 100,000 | Different from input | Fuzz reserve+1..uint32.MAX excluding current; seed reserve+1,MAX | Success | minimumGasToAttempt and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-P03 | Fuzz permitted role caller | true | Repeat 1 and 100,000 | Same as input | Current valid threshold | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |
| RDTASK-MINIMUM-GAS-P05 | Fuzz permitted role caller | false | Repeat 1 and 100,000 | Same as input | Current valid threshold | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet] |

[test_whenUnauthorizedCallerSetsMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L10
[test_whenPermittedCallerSetsValidMinimumGas_updatesValue]: ./setMinimumGasToAttempt.t.sol#L106
[test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp]: ./setMinimumGasToAttempt.t.sol#L140
[test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L37

[test_givenRoleAndNumericBoundaries_whenMinimumGasToAttemptSet]: ./setMinimumGasToAttempt.t.sol#L169

[test_whenPermittedCallerSetsInvalidMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L69

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-MINIMUM-GAS-L02 | Any address, fuzz, without authorization exclusions | false | false | Task locally disabled, then Kernel-deactivated; Fuzz full `uint32` input type without bounds/exclusions | `RevenueDistributorTask_PolicyNotActive(task)` before local enablement (where required), caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst]: ./setMinimumGasToAttempt.t.sol#L969
