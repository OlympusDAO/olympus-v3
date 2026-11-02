# BurnerLoansRisk.keeperReward coverage plan

Source: [keeperReward](../../../policies/burnerloans/BurnerLoansRisk.sol#L440). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-KEEPER-REWARD` identifies this contract/function.

Permissionless view gated by Risk activity and enablement. A canonical FLOAN market ID selects configuration; no Core call. debt,collateral,output uint256; protocolCaller bool. Current cfg defines keeperRewardBps, maxKeeperReward, output mode. Basis=collateral underlying when shares, otherwise actual output.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-L01 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-KEEPER-REWARD-L02 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts] |
| BLRISK-KEEPER-REWARD-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts] |
| BLRISK-KEEPER-REWARD-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts] |

## Output conversion

Fixed for this table: Accounting / events: Share units; reward<=output for valid config.

| ID | Caller | Output / collateral inputs | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-P01 | Fuzz all callers | Shares mode; collateral>0; fuzz representable output/collateral ratios below, equal and above 1; independently computed underlying reward | floor(output*underlyingReward/collateral); rounding down | Covered: [test][test_whenShareConversionUsesAnyRepresentableOutput], [test][test_whenShareOutputMaximum] |
| BLRISK-KEEPER-REWARD-P02 | Fuzz all callers | Shares mode; collateral=0; positive cap/BPS; valid backing snapshot; fuzz output 0..MAX256 | 0; no division by zero | Covered: [test][test_whenShareCollateralIsZero], [test][test_whenZeroCollateralOutputEndpoints] |

## Fixed share-conversion boundaries

Use the same one-unit backing reservation as the percentage/cap table. In shares mode collateral=100 raw underlying units, keeperRewardBps=100 and maxKeeperReward=100: the pre-conversion reward is exactly 1 underlying unit. These cases isolate conversion rounding with fixed inputs.

| ID | Caller | Collateral | Output shares | Expected reward shares | Working | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N15 | Fixed caller | 100 | 50 | 0 | floor(50 * 1 / 100)=0 | Covered: [test][test_whenSharesBelowUnity] |
| BLRISK-KEEPER-REWARD-N16 | Fixed caller | 100 | 100 | 1 | 100 * 1 / 100=1 | Covered: [test][test_whenSharesAtUnity] |
| BLRISK-KEEPER-REWARD-N17 | Fixed caller | 100 | 200 | 2 | 200 * 1 / 100=2 | Covered: [test][test_whenSharesAboveUnity] |

## Percentage, cap and backing boundaries

Fixed caller; ordinary underlying-output mode unless specified. Use 9-decimal OHM and 6-decimal collateral. debt=1 raw OHM, snapshot OHM/collateral/backing prices=1e18, backingMultiplierBps=10000: the rounded backing reservation is exactly 1 raw underlying unit. Hard-code each expected integer and show the raw-unit arithmetic in test comments.

| ID | Caller | Output / reward basis | keeperRewardBps | maxKeeperReward | Expected reward | Binding proof | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N01 | Fixed caller | 999 | 100 | 100 | 9 | floor(999/100)=9; percentage binds | Covered: [test][test_whenBelowPercentBoundary] |
| BLRISK-KEEPER-REWARD-N08 | Fixed caller | 1000 | 100 | 100 | 10 | Exact percentage boundary | Covered: [test][test_whenAtPercentBoundary] |
| BLRISK-KEEPER-REWARD-N09 | Fixed caller | 1001 | 100 | 100 | 10 | floor(1001/100)=10; boundary+1 | Covered: [test][test_whenAbovePercentBoundary] |
| BLRISK-KEEPER-REWARD-N10 | Fixed caller | 1000 | 100 | 9 | 9 | Cap one below percentage reward | Covered: [test][test_whenCapBelowPercent] |
| BLRISK-KEEPER-REWARD-N11 | Fixed caller | 1000 | 100 | 10 | 10 | Cap equals percentage reward | Covered: [test][test_whenCapEqualsPercent] |
| BLRISK-KEEPER-REWARD-N12 | Fixed caller | 1000 | 100 | 11 | 10 | Cap one above percentage reward | Covered: [test][test_whenCapAbovePercent] |
| BLRISK-KEEPER-REWARD-N02 | Fixed caller | 0 | 10000 | 100 | 0 | Basis below reserved backing; no subtraction underflow | Covered: [test][test_whenBelowBacking] |
| BLRISK-KEEPER-REWARD-N13 | Fixed caller | 1 | 10000 | 100 | 0 | Basis equals reserved backing; no surplus | Covered: [test][test_whenAtBacking] |
| BLRISK-KEEPER-REWARD-N14 | Fixed caller | 2 | 10000 | 100 | 1 | Basis one above backing; exactly one reward unit | Covered: [test][test_whenAboveBacking] |

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Fixed rounding regressions

Use the fixed fixtures in [seize's payout rounding cases](../BurnerLoansSeize/seize.md#fixed-payout-rounding-and-zero-output-cases). Use a fixed caller; hard-code the expected integer reward rather than deriving it with LoanMath/FullMath or the implementation under test. Principal=1 raw OHM unit, OHM decimals=9, underlying decimals=6, snapshot prices/backing=1e18, backingMultiplierBps=10000 and maxKeeperReward=1000 underlying units; required backing is exactly 1 underlying unit after rounding up.

| ID | Caller | Output mode | Collateral / output | keeperRewardBps | Expected return | Required proof | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N04 | Fixed caller | Underlying | 99 / 99 | 100 | 0 | A 0.99-unit percentage reward rounds down; settlement remainder is 99 | Covered: [test][test_whenFractionalUnderlyingReward] |
| BLRISK-KEEPER-REWARD-N05 | Fixed caller | Shares | 100 underlying / 1 share | 100 | 0 shares | Underlying reward is 1; conversion of 0.01 share rounds down; settlement remainder is 1 share | Covered: [test][test_whenFractionalShareReward] |
| BLRISK-KEEPER-REWARD-N06 | Fixed caller | Underlying | 2 / 2 | 9999 | 1 | Integer reward and backing cap leave Treasury remainder 1; do not independently floor a percentage-only Treasury fraction to zero | Covered: [test][test_whenRewardLeavesBackingRemainder] |
| BLRISK-KEEPER-REWARD-N07 | Fixed caller | Shares | 100 underlying / 0 shares | 100 | 0 shares | Zero output cannot create a keeper allocation; no division or token arithmetic failure | Covered: [test][test_whenZeroShareOutput] |

## Zero-reward branches

Registered asset; representable snapshot fields; unset fields not used by this early branch can revert if queried.

| ID | Caller | protocolCaller_ | keeperRewardBps | maxKeeperReward | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-P03 | Fuzz all callers | true | Positive | Positive | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenProtocolCaller_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-P04 | Fuzz all callers | false | 0 | Positive | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenZeroBps_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-P05 | Fuzz all callers | false | Positive | 0 | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenZeroCap_whenRewardQuoted] |

## Arithmetic failures

| ID | Caller | Arithmetic condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N03 | Fuzz all callers | Required backing Math.mulDiv quotient exceeds MAX256; earlier configuration lookup valid | `Panic(0x11)` | No state writes, cache updates or token movements | Covered: [test][test_whenRequiredBackingOverflows_reverts] |

[test_givenDisabled_whenCalled_reverts]: keeperReward.t.sol#L29
[test_givenInactiveAndDisabled_whenCalled_reverts]: keeperReward.t.sol#L43
[test_givenInactive_whenCalled_reverts]: keeperReward.t.sol#L36
[test_givenOperational_whenCalled]: keeperReward.t.sol#L19
[test_givenProtocolCaller_whenRewardQuoted]: keeperReward.t.sol#L272
[test_givenReEnabled_whenCalled]: keeperReward.t.sol#L52
[test_givenZeroBps_whenRewardQuoted]: keeperReward.t.sol#L294
[test_givenZeroCap_whenRewardQuoted]: keeperReward.t.sol#L317
[test_whenAboveBacking]: keeperReward.t.sol#L153
[test_whenAbovePercentBoundary]: keeperReward.t.sol#L99
[test_whenAtBacking]: keeperReward.t.sol#L144
[test_whenAtPercentBoundary]: keeperReward.t.sol#L90
[test_whenBelowBacking]: keeperReward.t.sol#L135
[test_whenBelowPercentBoundary]: keeperReward.t.sol#L81
[test_whenCapAbovePercent]: keeperReward.t.sol#L126
[test_whenCapBelowPercent]: keeperReward.t.sol#L108
[test_whenCapEqualsPercent]: keeperReward.t.sol#L117
[test_whenFractionalShareReward]: keeperReward.t.sol#L207
[test_whenFractionalUnderlyingReward]: keeperReward.t.sol#L162
[test_whenRequiredBackingOverflows_reverts]: keeperReward.t.sol#L340
[test_whenRewardLeavesBackingRemainder]: keeperReward.t.sol#L171
[test_whenShareCollateralIsZero]: keeperReward.t.sol#L250
[test_whenShareConversionUsesAnyRepresentableOutput]: keeperReward.t.sol#L225
[test_whenShareOutputMaximum]: keeperReward.t.sol#L240
[test_whenSharesAboveUnity]: keeperReward.t.sol#L198
[test_whenSharesAtUnity]: keeperReward.t.sol#L189
[test_whenSharesBelowUnity]: keeperReward.t.sol#L180
[test_whenZeroCollateralOutputEndpoints]: keeperReward.t.sol#L261
[test_whenZeroShareOutput]: keeperReward.t.sol#L216
