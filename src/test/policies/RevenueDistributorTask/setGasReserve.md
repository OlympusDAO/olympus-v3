# setGasReserve scenario plan

Scope: RDTask setGasReserve and gasReserve getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one GasReserveSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Task Kernel | Task local | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | Active | Fuzz enabled/disabled | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,threshold-1 when valid,threshold,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsReserve_reverts] |

## Lifecycle

| ID | Caller | Task Kernel | Task local | RD state | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P02 | Each permitted caller | Active | Disabled | Not queried | Valid | Valid changed value below threshold | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue] |
| GAS-L01 | Admin; Revenue Distributor Admin separately, roles retained | Inactive | Enabled | Active/enabled but not queried | Valid | Valid changed value below threshold | RevenueDistributorTask_PolicyInactive() before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts] |

## Invalid inputs

| ID | Caller | Task state | Current threshold | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-I01 | Each permitted caller | Active; fuzz enabled/disabled | Any valid | Any valid | 0 | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenPermittedCallerSetsZeroReserve_reverts] |
| GAS-I02 | Each permitted caller | Active; fuzz enabled/disabled | Fuzz valid threshold | Any valid | Fuzz threshold..uint32.max; seed threshold,threshold+1,MAX | RevenueDistributorTask_InvalidGasReserve() | Unchanged | Covered: [test][test_whenReserveReachesThreshold_reverts] |

## Numeric inputs and extremes

| ID | Caller | Task local | Current threshold | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P01 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Fuzz 3..uint32.MAX | 1 before call | Fuzz 2..threshold-1; separately seed reserve 1 and threshold-1/MAX boundaries | Success | gasReserve and exact event match input | Covered: [range][test_whenPermittedCallerSetsValidReserve_updatesValue], [boundaries][test_whenReserveBoundariesSet_updatesValue] |
| GAS-P03 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Repeat 2 and 250,000 | Same as input | Current valid reserve | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentReserve_isNoOp] |

[test_whenUnauthorizedCallerSetsReserve_reverts]: ./setGasReserve.t.sol#L10
[test_whenPermittedCallerSetsValidReserve_updatesValue]: ./setGasReserve.t.sol#L84
[test_whenPermittedCallerSetsCurrentReserve_isNoOp]: ./setGasReserve.t.sol#L108
[test_givenTaskInactive_whenPermittedCallerSetsReserve_reverts]: ./setGasReserve.t.sol#L29
[test_whenPermittedCallerSetsZeroReserve_reverts]: ./setGasReserve.t.sol#L46
[test_whenReserveReachesThreshold_reverts]: ./setGasReserve.t.sol#L62
[test_whenReserveBoundariesSet_updatesValue]: ./setGasReserve.t.sol#L136
