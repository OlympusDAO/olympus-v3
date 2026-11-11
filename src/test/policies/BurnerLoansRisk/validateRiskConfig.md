# BurnerLoansRisk.validateRiskConfig coverage plan

Source: [validateRiskConfig](../../../policies/burnerloans/BurnerLoansRisk.sol#L503). Coverage is recorded in the Test column.

## Domains and notation

Input type: `IBurnerLoansRisk.AssetRiskConfigInput`, shared by Config and its timelock.

Scenario scope: `BLRISK-VALIDATE-RISK` identifies this contract/function.

Permissionless pure. maxLtvBps/backingMultiplierBps/keeperRewardBps uint16; termLength/maxMaturityHorizon uint48; maxKeeperReward uint128. Bounds from LoanParameters.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local lifecycle independence

Pure input validation does not read Risk lifecycle or dependencies. Use the valid defaults defined below. Each call preserves all state, balances and logs.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-RISK-L01 | Fuzz all callers | true | true | Success | Covered: [test][test_givenOperational_whenCalled] |
| BLRISK-VALIDATE-RISK-L02 | Fuzz all callers | true | false | Success | Covered: [test][test_givenDisabled_whenCalled] |
| BLRISK-VALIDATE-RISK-L03 | Fuzz all callers | false | true | Success | Covered: [test][test_givenInactive_whenCalled] |
| BLRISK-VALIDATE-RISK-L04 | Fuzz all callers | false | false | Success | Covered: [test][test_givenInactiveAndDisabled_whenCalled] |

Invalid inputs still receive the same validation error in every lifecycle state; no lifecycle rejection masks it.

| ID | Caller | Local active | Local enabled | Invalid field | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-RISK-L05 | Fuzz all callers | true | true | maxLtvBps=0; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) | Covered: [test][test_givenOperational_whenLtvIsZero_reverts] |
| BLRISK-VALIDATE-RISK-L06 | Fuzz all callers | true | false | maxLtvBps=0; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) | Covered: [test][test_givenDisabled_whenLtvIsZero_reverts] |
| BLRISK-VALIDATE-RISK-L07 | Fuzz all callers | false | true | maxLtvBps=0; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) | Covered: [test][test_givenInactive_whenLtvIsZero_reverts] |
| BLRISK-VALIDATE-RISK-L08 | Fuzz all callers | false | false | maxLtvBps=0; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(0) | Covered: [test][test_givenInactiveAndDisabled_whenLtvIsZero_reverts] |

## Numeric boundaries and arithmetic

All input type maxima are represented by the exact rejecting field family or accepted maxKeeperReward=MAX128. Generation preserves every earlier validation condition; risk and fee sums use their documented scales. Accepted boundary cases are below.

## Invalid inputs

Valid risk domain: maxLtvBps in 1..10000, backingMultiplierBps in 10000..50000, keeperRewardBps in 0..10000, maxKeeperReward in 0..MAX128, termLength in 1..365 days, maxMaturityHorizon in termLength+1..366 days. Fuzz fields independently within those constraints; guarantee each endpoint and maxKeeperReward=0,1,MAX128. Defaults for isolated faults: LTV=7500, backing multiplier=12000, keeper BPS=100, max reward=1, term=30 days, horizon=90 days. For TERM-HIGH, an in-range horizon cannot exceed a MAX48 term; the earlier term-bound rejection is the expected path, so a later term/horizon relationship need not be valid.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-RISK-I01 | Fuzz all callers | maxLtvBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(0)` | Unchanged; no committed logs | Covered: [test][test_givenOperational_whenLtvIsZero_reverts], [test][test_givenDisabled_whenLtvIsZero_reverts], [test][test_givenInactive_whenLtvIsZero_reverts], [test][test_givenInactiveAndDisabled_whenLtvIsZero_reverts] |
| BLRISK-VALIDATE-RISK-I02 | Fuzz all callers | maxLtvBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(maxLtvBps)` | Unchanged; no committed logs | Covered: [test][test_whenExcessLtv_reverts], [test][test_whenExcessLtvBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I03 | Fuzz all callers | backingMultiplierBps in 0..9999; seed 0,1,9999 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenLowBacking_reverts], [test][test_whenLowBackingBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I04 | Fuzz all callers | backingMultiplierBps in 50001..MAX16; seed 50001,MAX16 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenExcessBacking_reverts], [test][test_whenExcessBackingBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I05 | Fuzz all callers | keeperRewardBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(keeperRewardBps)` | Unchanged; no committed logs | Covered: [test][test_whenExcessRewardBps_reverts], [test][test_whenExcessRewardBpsBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I06 | Fuzz all callers | termLength=0; horizon=90 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenZeroTerm_reverts], [test][test_whenZeroTermBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I07 | Fuzz all callers | termLength in 365 days+1..MAX48; seed lower bound,MAX48; horizon=366 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenExcessTerm_reverts], [test][test_whenExcessTermBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I08 | Fuzz all callers | maxMaturityHorizon=0; termLength=30 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenZeroHorizon_reverts], [test][test_whenZeroHorizonBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I09 | Fuzz all callers | termLength in 2..365 days; maxMaturityHorizon in 1..termLength-1; seed 1,termLength-1 | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenShortHorizon_reverts], [test][test_whenHorizonBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I10 | Fuzz all callers | maxMaturityHorizon=termLength; fuzz termLength in 1..365 days; seed 1,365 days | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenEqualHorizon_reverts], [test][test_whenHorizonBoundaries_reverts] |
| BLRISK-VALIDATE-RISK-I11 | Fuzz all callers | maxMaturityHorizon in 366 days+1..MAX48; seed lower bound,MAX48; valid termLength | `IBurnerLoansErrors.BurnerLoans_InvalidParam()` | Unchanged; no committed logs | Covered: [test][test_whenExcessHorizon_reverts], [test][test_whenExcessHorizonBoundaries_reverts] |

## Successful execution

Valid risk domain: maxLtvBps in 1..10000, backingMultiplierBps in 10000..50000, keeperRewardBps in 0..10000, maxKeeperReward in 0..MAX128, termLength in 1..365 days, maxMaturityHorizon in termLength+1..366 days. Fuzz fields independently within those constraints; guarantee each endpoint and maxKeeperReward=0,1,MAX128. Defaults for isolated faults: LTV=7500, backing multiplier=12000, keeper BPS=100, max reward=1, term=30 days, horizon=90 days. For TERM-HIGH, an in-range horizon cannot exceed a MAX48 term; the earlier term-bound rejection is the expected path, so a later term/horizon relationship need not be valid.

| ID | Caller | Valid domain / boundary | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-RISK-P01 | Fuzz all callers | Full independently fuzzed valid domain; seed every semantic endpoint | Success | No state/token/event changes | Covered: [test][test_whenConfigIsValid], [test][test_whenValidEndpoints] |
| BLRISK-VALIDATE-RISK-P02 | Fuzz all callers | LTV=10000, multiplier=50000, keeper=10000, reward=MAX128, term=365 days, horizon=366 days | Success | No state/token/event changes | Covered: [test][test_whenValidEndpoints] |

[test_givenDisabled_whenCalled]: validateRiskConfig.t.sol#L28

[test_givenDisabled_whenLtvIsZero_reverts]: validateRiskConfig.t.sol#L59

[test_givenInactiveAndDisabled_whenCalled]: validateRiskConfig.t.sol#L40

[test_givenInactiveAndDisabled_whenLtvIsZero_reverts]: validateRiskConfig.t.sol#L81

[test_givenInactive_whenCalled]: validateRiskConfig.t.sol#L34

[test_givenInactive_whenLtvIsZero_reverts]: validateRiskConfig.t.sol#L70

[test_givenOperational_whenCalled]: validateRiskConfig.t.sol#L22

[test_givenOperational_whenLtvIsZero_reverts]: validateRiskConfig.t.sol#L48

[test_whenConfigIsValid]: validateRiskConfig.t.sol#L300

[test_whenEqualHorizon_reverts]: validateRiskConfig.t.sol#L271

[test_whenExcessBackingBoundaries_reverts]: validateRiskConfig.t.sol#L152

[test_whenExcessBacking_reverts]: validateRiskConfig.t.sol#L147

[test_whenExcessHorizonBoundaries_reverts]: validateRiskConfig.t.sol#L255

[test_whenExcessHorizon_reverts]: validateRiskConfig.t.sol#L250

[test_whenExcessLtvBoundaries_reverts]: validateRiskConfig.t.sol#L109

[test_whenExcessLtv_reverts]: validateRiskConfig.t.sol#L104

[test_whenExcessRewardBpsBoundaries_reverts]: validateRiskConfig.t.sol#L173

[test_whenExcessRewardBps_reverts]: validateRiskConfig.t.sol#L168

[test_whenExcessTermBoundaries_reverts]: validateRiskConfig.t.sol#L214

[test_whenExcessTerm_reverts]: validateRiskConfig.t.sol#L209

[test_whenHorizonBoundaries_reverts]: validateRiskConfig.t.sol#L281

[test_whenLowBackingBoundaries_reverts]: validateRiskConfig.t.sol#L130

[test_whenLowBacking_reverts]: validateRiskConfig.t.sol#L125

[test_whenShortHorizon_reverts]: validateRiskConfig.t.sol#L261

[test_whenValidEndpoints]: validateRiskConfig.t.sol#L315

[test_whenZeroHorizonBoundaries_reverts]: validateRiskConfig.t.sol#L235

[test_whenZeroHorizon_reverts]: validateRiskConfig.t.sol#L230

[test_whenZeroTermBoundaries_reverts]: validateRiskConfig.t.sol#L194

[test_whenZeroTerm_reverts]: validateRiskConfig.t.sol#L189
