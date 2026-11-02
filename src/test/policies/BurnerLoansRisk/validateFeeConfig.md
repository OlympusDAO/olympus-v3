# BurnerLoansRisk.validateFeeConfig coverage plan

Source: [validateFeeConfig](../../../policies/burnerloans/BurnerLoansRisk.sol#L506). Coverage is recorded in the Test column.

## Domains and notation

Input type: `IBurnerLoansRisk.AssetFeeConfig`, shared by Config and its timelock.

Scenario scope: `BLRISK-VALIDATE-FEE` identifies this contract/function.

Permissionless pure. Four uint16 fields; sum uses widened arithmetic. Allowed base/pre/post each0..10000; kink0..9999; sum<=10000; zero kink requires both slopes zero.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

Valid fee domain: baseFeeBps, preKinkSlopeBps and postKinkSlopeBps each in 0..10000; their sum is <=10000; kinkBps in 0..9999, with kink=0 allowed only when both slopes are zero. Fuzz base first, then pre within the remaining budget, then post within the remaining budget; choose kink=0..9999 for zero slopes and 1..9999 otherwise. Guarantee zero, one, exact BPS-cap and kink=9999 seeds. Defaults for isolated faults: base=100, kink=5000, pre=200, post=300. Slopes need not be monotonic; seed pre>post as a valid example.

| ID | Caller | Invalid field / fuzz domain / seeds | Exact execution error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-FEE-I01 | Fuzz all callers | baseFeeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(baseFeeBps)` | Unchanged; no committed logs | Covered: [test][test_whenbaseFeeBpsExceedsLimit_reverts], [test][test_whenbaseFeeBpsBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I02 | Fuzz all callers | preKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(preKinkSlopeBps)` | Unchanged; no committed logs | Covered: [test][test_whenpreKinkSlopeBpsExceedsLimit_reverts], [test][test_whenpreKinkSlopeBpsBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I03 | Fuzz all callers | postKinkSlopeBps in 10001..MAX16; seed 10001,MAX16 | `IBurnerLoansRisk.BurnerLoans_InvalidBps(postKinkSlopeBps)` | Unchanged; no committed logs | Covered: [test][test_whenpostKinkSlopeBpsExceedsLimit_reverts], [test][test_whenpostKinkSlopeBpsBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I04 | Fuzz all callers | kinkBps in 10000..MAX16; seed 10000,MAX16; other BPS fields valid | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenkinkBpsExceedsLimit_reverts], [test][test_whenkinkBpsBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I05 | Fuzz all callers | kinkBps=0; preKinkSlopeBps in 1..10000; postKinkSlopeBps=0; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenZeroKinkAndPreSlope_reverts], [test][test_whenInvalidCurveBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I06 | Fuzz all callers | kinkBps=0; preKinkSlopeBps=0; postKinkSlopeBps in 1..10000; baseFeeBps=0 | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenZeroKinkAndPostSlope_reverts], [test][test_whenInvalidCurveBoundaries_reverts] |
| BLRISK-VALIDATE-FEE-I07 | Fuzz all callers | Each component in 0..10000; kinkBps in 1..9999; sum=base+pre+post in 10001..30000; seed totals 10001,30000 and single-slope tuples (5000,5001,0), (5000,0,5001) | `IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig()` | Unchanged; no committed logs | Covered: [test][test_whenFeeTotalExceedsBps_reverts], [test][test_whenInvalidCurveBoundaries_reverts] |

## Local lifecycle independence

Pure input validation does not read Risk lifecycle or dependencies. Use the valid defaults defined below. Each call preserves all state, balances and logs.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-FEE-L01 | Fuzz all callers | true | true | Success | Covered: [test][test_givenOperational_whenCalled] |
| BLRISK-VALIDATE-FEE-L02 | Fuzz all callers | true | false | Success | Covered: [test][test_givenDisabled_whenCalled] |
| BLRISK-VALIDATE-FEE-L03 | Fuzz all callers | false | true | Success | Covered: [test][test_givenInactive_whenCalled] |
| BLRISK-VALIDATE-FEE-L04 | Fuzz all callers | false | false | Success | Covered: [test][test_givenInactiveAndDisabled_whenCalled] |

Invalid inputs still receive the same validation error in every lifecycle state; no lifecycle rejection masks it.

| ID | Caller | Local active | Local enabled | Invalid field | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-FEE-L05 | Fuzz all callers | true | true | baseFeeBps=10001; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001) | Covered: [test][test_givenOperational_whenBaseExceedsBps_reverts] |
| BLRISK-VALIDATE-FEE-L06 | Fuzz all callers | true | false | baseFeeBps=10001; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001) | Covered: [test][test_givenDisabled_whenBaseExceedsBps_reverts] |
| BLRISK-VALIDATE-FEE-L07 | Fuzz all callers | false | true | baseFeeBps=10001; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001) | Covered: [test][test_givenInactive_whenBaseExceedsBps_reverts] |
| BLRISK-VALIDATE-FEE-L08 | Fuzz all callers | false | false | baseFeeBps=10001; other fields valid | IBurnerLoansRisk.BurnerLoans_InvalidBps(10001) | Covered: [test][test_givenInactiveAndDisabled_whenBaseExceedsBps_reverts] |

## Numeric boundaries and arithmetic

All input type maxima are represented by the exact rejecting field family or accepted maxKeeperReward=MAX128. Generation preserves every earlier validation condition; risk and fee sums use their documented scales. Accepted boundary cases are below.

## Successful execution

Valid fee domain: baseFeeBps, preKinkSlopeBps and postKinkSlopeBps each in 0..10000; their sum is <=10000; kinkBps in 0..9999, with kink=0 allowed only when both slopes are zero. Fuzz base first, then pre within the remaining budget, then post within the remaining budget; choose kink=0..9999 for zero slopes and 1..9999 otherwise. Guarantee zero, one, exact BPS-cap and kink=9999 seeds. Defaults for isolated faults: base=100, kink=5000, pre=200, post=300. Slopes need not be monotonic; seed pre>post as a valid example.

| ID | Caller | Valid domain / boundary | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-FEE-P01 | Fuzz all callers | Full independently fuzzed valid domain; seed every semantic endpoint | Success | No state/token/event changes | Covered: [test][test_whenConfigIsValid], [test][test_whenValidEndpoints] |
| BLRISK-VALIDATE-FEE-P02 | Fuzz all callers | Zero-kink flat fee; separate exact total=10000 with pre>post | Success | No state/token/event changes | Covered: [test][test_whenValidEndpoints] |

[test_givenDisabled_whenBaseExceedsBps_reverts]: validateFeeConfig.t.sol#L51

[test_givenDisabled_whenCalled]: validateFeeConfig.t.sol#L22

[test_givenInactiveAndDisabled_whenBaseExceedsBps_reverts]: validateFeeConfig.t.sol#L69

[test_givenInactiveAndDisabled_whenCalled]: validateFeeConfig.t.sol#L34

[test_givenInactive_whenBaseExceedsBps_reverts]: validateFeeConfig.t.sol#L60

[test_givenInactive_whenCalled]: validateFeeConfig.t.sol#L28

[test_givenOperational_whenBaseExceedsBps_reverts]: validateFeeConfig.t.sol#L42

[test_givenOperational_whenCalled]: validateFeeConfig.t.sol#L16

[test_whenConfigIsValid]: validateFeeConfig.t.sol#L212

[test_whenFeeTotalExceedsBps_reverts]: validateFeeConfig.t.sol#L178

[test_whenInvalidCurveBoundaries_reverts]: validateFeeConfig.t.sol#L193

[test_whenValidEndpoints]: validateFeeConfig.t.sol#L227

[test_whenZeroKinkAndPostSlope_reverts]: validateFeeConfig.t.sol#L170

[test_whenZeroKinkAndPreSlope_reverts]: validateFeeConfig.t.sol#L162

[test_whenbaseFeeBpsBoundaries_reverts]: validateFeeConfig.t.sol#L95

[test_whenbaseFeeBpsExceedsLimit_reverts]: validateFeeConfig.t.sol#L90

[test_whenkinkBpsBoundaries_reverts]: validateFeeConfig.t.sol#L156

[test_whenkinkBpsExceedsLimit_reverts]: validateFeeConfig.t.sol#L151

[test_whenpostKinkSlopeBpsBoundaries_reverts]: validateFeeConfig.t.sol#L137

[test_whenpostKinkSlopeBpsExceedsLimit_reverts]: validateFeeConfig.t.sol#L132

[test_whenpreKinkSlopeBpsBoundaries_reverts]: validateFeeConfig.t.sol#L116

[test_whenpreKinkSlopeBpsExceedsLimit_reverts]: validateFeeConfig.t.sol#L111
