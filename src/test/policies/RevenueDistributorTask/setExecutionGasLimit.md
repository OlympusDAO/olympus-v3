# setExecutionGasLimit scenario plan

Scope: RDTask setExecutionGasLimit and executionGasLimit getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; Local disablement does not gate the setter; it does not query RD, so RD lifecycle is not a test dimension. RDTask itself must be Kernel-active. Authorization precedes numeric validation. reserve is current gasReserve; threshold is current minimumGasToAttempt. All quantities are uint32 gas units.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid value is stored and emits one ExecutionGasLimitSet(input), preserving other gas parameters, cursor and balances. A valid same-value input is a no-op and emits no event.

## Authorization

| ID | Caller | Task Kernel | Task local | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-A01 | Any caller outside Admin and Revenue Distributor Admin, fuzz | Active | Fuzz enabled/disabled | Fuzz 0..`type(uint32).max`; seed 0,1,MAX | NotAuthorised() before numeric error | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsExecutionGas_reverts] |

## Lifecycle

| ID | Caller | Task Kernel | Task local | RD state | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P02 | Each permitted caller | Active | Disabled | Not queried | Valid changed value | Success | Setter remains operational; exact value stored and one event emitted | Covered: [test][test_whenPermittedCallerSetsPositiveExecutionGas_updatesValue] |
| GAS-L01 | Admin; Revenue Distributor Admin separately, roles retained | Inactive | Enabled | Active/enabled but not queried | Valid changed value | RevenueDistributorTask_PolicyInactive() before input validation | Gas settings, cursor and balances unchanged; no setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts] |

## Invalid inputs

| ID | Caller | Task state | Current execution limit | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-I01 | Each permitted caller | Active; fuzz enabled/disabled | Any valid | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | Unchanged | Covered: [test][test_whenPermittedCallerSetsZeroExecutionGas_reverts] |

## Numeric inputs and extremes

| ID | Caller | Task local | Current execution limit | `gasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GAS-P01 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Different from input | Fuzz 1..uint32.MAX excluding current; seed 1,MAX | Success | executionGasLimit and exact event match input | Covered: [range][test_whenPermittedCallerSetsPositiveExecutionGas_updatesValue], [boundaries][test_whenExecutionGasBoundariesSet_updatesValue] |
| GAS-P03 | Admin; Revenue Distributor Admin separately | Fuzz enabled/disabled | Same as input | Current valid value | Success | No storage change and no event | Covered: [test][test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp] |

[test_whenUnauthorizedCallerSetsExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L10
[test_whenPermittedCallerSetsPositiveExecutionGas_updatesValue]: ./setExecutionGasLimit.t.sol#L64
[test_whenPermittedCallerSetsCurrentExecutionGas_isNoOp]: ./setExecutionGasLimit.t.sol#L90
[test_givenTaskInactive_whenPermittedCallerSetsExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L29
[test_whenPermittedCallerSetsZeroExecutionGas_reverts]: ./setExecutionGasLimit.t.sol#L46
[test_whenExecutionGasBoundariesSet_updatesValue]: ./setExecutionGasLimit.t.sol#L111
