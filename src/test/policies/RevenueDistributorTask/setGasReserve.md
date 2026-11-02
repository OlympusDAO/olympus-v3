# setGasReserve scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: RDTask setGasReserve and gasReserve getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorTask; own inactivity uses `RevenueDistributorTask_PolicyNotActive(Task)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one GasReserveSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Local active | Local enabled | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GAS-RESERVE-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | true | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,threshold-1 when valid,threshold,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsReserve_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |
| RDTASK-GAS-RESERVE-A02 | Any caller outside Admin and Revenue Distributor Admin, fuzz | true | false | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,threshold-1 when valid,threshold,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsReserve_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GAS-RESERVE-P02 | Fuzz permitted role caller | true | false | true | true | Valid | Valid changed value below threshold | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet], [test][test_whenMinimumReserveSet_updatesValue] |
| RDTASK-GAS-RESERVE-L01 | Fuzz permitted role caller | false | true | true | true | Valid | Valid changed value below threshold | RevenueDistributorTask_PolicyNotActive(Task) before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |

## Invalid inputs

| ID | Caller | Local active | Local enabled | Current threshold | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GAS-RESERVE-I01 | Fuzz permitted role caller | true | true | Any valid | Any valid | 0 | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidReserve_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |
| GAS-I03 | Fuzz permitted role caller | true | false | Any valid | Any valid | 0 | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenPermittedCallerSetsInvalidReserve_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |
| RDTASK-GAS-RESERVE-I02 | Fuzz permitted role caller | true | true | Fuzz valid threshold | Any valid | Fuzz threshold..uint32.max; seed threshold,threshold+1,MAX | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenReserveReachesThreshold_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |
| GAS-I04 | Fuzz permitted role caller | true | false | Fuzz valid threshold | Any valid | Fuzz threshold..uint32.max; seed threshold,threshold+1,MAX | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenReserveReachesThreshold_reverts], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |

## Numeric inputs and extremes

| ID | Caller | Local enabled | Current threshold | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GAS-RESERVE-P01 | Fuzz permitted role caller | true | Fuzz 3..uint32.MAX | 1 before call | Fuzz 2..threshold-1; separately seed reserve 1 and threshold-1/MAX boundaries | Success | gasReserve and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet], [test][test_whenMinimumReserveSet_updatesValue] |
| RDTASK-GAS-RESERVE-P04 | Fuzz permitted role caller | false | Fuzz 3..uint32.MAX | 1 before call | Fuzz 2..threshold-1; separately seed reserve 1 and threshold-1/MAX boundaries | Success | gasReserve and exact event match input | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet], [test][test_whenMinimumReserveSet_updatesValue] |
| RDTASK-GAS-RESERVE-P03 | Fuzz permitted role caller | true | Repeat 2 and 250,000 | Same as input | Current valid reserve | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentReserve_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |
| RDTASK-GAS-RESERVE-P05 | Fuzz permitted role caller | false | Repeat 2 and 250,000 | Same as input | Current valid reserve | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentReserve_isNoOp], [test][test_givenRoleAndNumericBoundaries_whenGasReserveSet] |

[test_whenUnauthorizedCallerSetsReserve_reverts]: ./setGasReserve.t.sol#L10
[test_whenPermittedCallerSetsValidReserve_updatesValue]: ./setGasReserve.t.sol#L148
[test_whenPermittedCallerSetsCurrentReserve_isNoOp]: ./setGasReserve.t.sol#L189
[test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts]: ./setGasReserve.t.sol#L41

[test_whenReserveReachesThreshold_reverts]: ./setGasReserve.t.sol#L109

[test_givenRoleAndNumericBoundaries_whenGasReserveSet]: ./setGasReserve.t.sol#L262

[test_whenMinimumReserveSet_updatesValue]: ./setGasReserve.t.sol#L229

[test_whenPermittedCallerSetsInvalidReserve_reverts]: ./setGasReserve.t.sol#L77

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GAS-RESERVE-L02 | Any address, fuzz, without authorization exclusions | false | false | Task locally disabled, then Kernel-deactivated; Fuzz full `uint32` input type without bounds/exclusions | `RevenueDistributorTask_PolicyNotActive(task)` before local enablement (where required), caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst]: ./setGasReserve.t.sol#L691
