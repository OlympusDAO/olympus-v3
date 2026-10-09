# setMinimumGasToAttempt scenario plan

Scope: RDTask setMinimumGasToAttempt and minimumGasToAttempt getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one MinimumGasToAttemptSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Task Kernel | Task local | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | Active | Fuzz enabled/disabled | Any valid | Fuzz 0..`type(uint32).max`; seed 0,1,reserve,reserve+1 when valid,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsMinimumGas_reverts] |

## Lifecycle

| ID | Caller | Task Kernel | Task local | RD state | Current reserve | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P02 | Each permitted caller | Active | Disabled | Not queried | Valid | Valid changed value above reserve | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue] |
| GAS-L01 | Admin; Revenue Distributor Admin separately, roles retained | Inactive | Enabled | Active/enabled but not queried | Valid | Valid changed value above reserve | RevenueDistributorTask_PolicyInactive() before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts] |

## Invalid inputs

| ID | Caller | Task state | Current reserve | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-I01 | Each permitted caller | Active; fuzz enabled/disabled | Fuzz valid reserve | Any valid | Fuzz 0..reserve; seed 0,1,reserve-1,reserve | RevenueDistributorTask_InvalidMinimumGasToAttempt() | Unchanged | Covered: [test][test_whenMinimumGasDoesNotExceedReserve_reverts] |

## Numeric inputs and extremes

| ID | Caller | Task local | Current reserve | Current threshold | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P01 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Repeat 1 and 100,000 | Different from input | Fuzz reserve+1..uint32.MAX excluding current; seed reserve+1,MAX | Success | minimumGasToAttempt and exact event match input | Covered: [range][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [boundaries][test_whenMinimumGasBoundariesSet_updatesValue] |
| GAS-P03 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Repeat 1 and 100,000 | Same as input | Current valid threshold | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp] |

[test_whenUnauthorizedCallerSetsMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L10
[test_whenPermittedCallerSetsValidMinimumGas_updatesValue]: ./setMinimumGasToAttempt.t.sol#L70
[test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp]: ./setMinimumGasToAttempt.t.sol#L99
[test_givenTaskInactive_whenPermittedCallerSetsMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L29
[test_whenMinimumGasDoesNotExceedReserve_reverts]: ./setMinimumGasToAttempt.t.sol#L46
[test_whenMinimumGasBoundariesSet_updatesValue]: ./setMinimumGasToAttempt.t.sol#L125
