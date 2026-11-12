# BurnerLoansRisk.keeperReward coverage plan

Source: [keeperReward](../../../policies/burnerloans/BurnerLoansRisk.sol#L463). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

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

Use zero debt and a ready live snapshot. In shares mode collateral=100 raw underlying units, keeperRewardBps=100 and maxKeeperReward=100: the pre-conversion reward is exactly 1 underlying unit. These cases isolate conversion rounding with fixed inputs.

| ID | Caller | Collateral | Output shares | Expected reward shares | Working | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N15 | Fixed caller | 100 | 50 | 0 | floor(50 * 1 / 100)=0 | Covered: [test][test_whenSharesBelowUnity] |
| BLRISK-KEEPER-REWARD-N16 | Fixed caller | 100 | 100 | 1 | 100 * 1 / 100=1 | Covered: [test][test_whenSharesAtUnity] |
| BLRISK-KEEPER-REWARD-N17 | Fixed caller | 100 | 200 | 2 | 200 * 1 / 100=2 | Covered: [test][test_whenSharesAboveUnity] |

## Percentage, cap and backing boundaries

Fixed caller; ordinary underlying-output mode unless specified. Use 9-decimal OHM and 6-decimal collateral. debt=1e9 raw OHM, live OHM/collateral prices=1e18, backing=1e12 and backingMultiplierBps=10000: the rounded backing reservation is exactly 1 raw underlying unit. Hard-code each expected integer and show the raw-unit arithmetic in test comments.

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

Use the fixed fixtures in [seize's payout rounding cases](../BurnerLoansSeize/seize.md#fixed-payout-rounding-and-zero-output-cases). Use a fixed caller; hard-code the expected integer reward rather than deriving it with LoanMath/FullMath or the implementation under test. For underlying cases principal=1e9 raw OHM units, OHM decimals=9, underlying decimals=6, live OHM/collateral prices=1e18, backing=1e12 and backingMultiplierBps=10000 and maxKeeperReward=1000 underlying units; required backing is exactly 1 underlying unit after rounding up.

| ID | Caller | Output mode | Collateral / output | keeperRewardBps | Expected return | Required proof | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N04 | Fixed caller | Underlying | 99 / 99 | 100 | 0 | A 0.99-unit percentage reward rounds down; settlement remainder is 99 | Covered: [test][test_whenFractionalUnderlyingReward] |
| BLRISK-KEEPER-REWARD-N05 | Fixed caller | Shares | 100 underlying / 1 share | 100 | 0 shares | Underlying reward is 1; conversion of 0.01 share rounds down; settlement remainder is 1 share | Covered: [test][test_whenFractionalShareReward] |
| BLRISK-KEEPER-REWARD-N06 | Fixed caller | Underlying | 2 / 2 | 9999 | 1 | Integer reward and backing cap leave Treasury remainder 1; do not independently floor a percentage-only Treasury fraction to zero | Covered: [test][test_whenRewardLeavesBackingRemainder] |
| BLRISK-KEEPER-REWARD-N07 | Fixed caller | Shares | 100 underlying / 0 shares | 100 | 0 shares | Zero output cannot create a keeper allocation; no division or token arithmetic failure | Covered: [test][test_whenZeroShareOutput] |

## Zero-reward branches

Registered market. These branches require no snapshot or pricing dependency calls; lifecycle and canonical configuration validation still run.

| ID | Caller | protocolCaller_ | keeperRewardBps | maxKeeperReward | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-P03 | Fuzz all callers | true | Positive | Positive | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenProtocolCaller_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-P04 | Fuzz all callers | false | 0 | Positive | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenZeroBps_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-P05 | Fuzz all callers | false | Positive | 0 | Return 0 after market lookup | No price refresh, reward arithmetic or writes/logs | Covered: [test][test_givenZeroCap_whenRewardQuoted] |

## Arithmetic failures

| ID | Caller | Arithmetic condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-N03 | Fuzz all callers | Required backing Math.mulDiv quotient exceeds MAX256; earlier configuration lookup valid | `Panic(0x11)` | No state writes, cache updates or token movements | Covered: [test][test_whenRequiredBackingOverflows_reverts] |

## Backing lifecycle acceptance

Backing-dependent rewards require current oracle Kernel/membership/enablement.
Protocol callers and zero reward configurations keep their existing zero-reward
shortcuts, which do not consume backing.

| ID | Caller | Scenario | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-D01 | Test caller (permissionless API) | Oracle active/enabled vary independently; exclude true/true | PolicyDependency_NotActive(oracle); no committed changes | Covered: [test][test_givenBackingUnavailable_whenConsumed_reverts] |
| BLRISK-KEEPER-REWARD-D02 | Test caller (permissionless API) | Deterministic oracle states: active/disabled, inactive/enabled, inactive/disabled | PolicyDependency_NotActive(oracle) for each seed | Covered: [test][test_givenBackingLifecycleBoundaries_whenConsumed_reverts] |

## Reward price ownership

The function receives no caller-supplied snapshot. After lifecycle and canonical-market validation,
protocol callers and zero reward configurations return zero without pricing. Other rewards read
Risk's current cached/live snapshot using the market's underlying collateral token. All calls
preserve storage, balances and cache observations. The public Seize action retains its ordinary
keeper pricing admission, including zero configured rewards.

For the fixed positive-reward cases below, principal=10e9 OHM, collateral/output=100e6 units,
backing=$35 per OHM, multiplier=10000 BPS, keeperRewardBps=1000 and maxKeeperReward=100e6.
A $4 collateral price reserves ceil(10 * 35 / 4)=87.5 assets, leaving 12.5 assets of surplus.
The 10% reward is 10e6 units, below surplus; independent expected reward is 10e6.

| ID | Caller | protocolCaller_ | Pricing source / condition | Return / error | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-KEEPER-REWARD-P07 | Test caller; API remains permissionless | false | Fresh operational cache: collateral=$4 while live collateral=$1; backing ready | 10e6; no live PRICE.getPrice reads; cached snapshot is not refreshed | Covered: [test][test_givenFreshCachedPrices_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-P08 | Test caller; API remains permissionless | false | Cache unset; live collateral=$4 and backing ready | 10e6; reads its own live snapshot | Covered: [test][test_givenLivePrices_whenRewardQuoted] |
| BLRISK-KEEPER-REWARD-I01 | Fuzz all callers | Fuzz false/true | Absent canonical market; marketId=MAX32 | FLOAN_InvalidMarket(MAX32) before pricing | Covered: [test][test_givenMissingMarket_whenRewardQuoted_reverts] |
| BLRISK-KEEPER-REWARD-I03 | Test caller; API remains permissionless | false | Cache unset; PRICE returns zero collateral price and a fresh timestamp | BurnerLoans_InvalidPrice(); no writes | Covered: [test][test_givenInvalidLivePrice_whenRewardQuoted_reverts] |

[test_givenDisabled_whenCalled_reverts]: keeperReward.t.sol#L31
[test_givenInactiveAndDisabled_whenCalled_reverts]: keeperReward.t.sol#L51
[test_givenInactive_whenCalled_reverts]: keeperReward.t.sol#L41
[test_givenOperational_whenCalled]: keeperReward.t.sol#L25
[test_givenProtocolCaller_whenRewardQuoted]: keeperReward.t.sol#L326
[test_givenReEnabled_whenCalled]: keeperReward.t.sol#L61
[test_givenZeroBps_whenRewardQuoted]: keeperReward.t.sol#L344
[test_givenZeroCap_whenRewardQuoted]: keeperReward.t.sol#L363
[test_whenAboveBacking]: keeperReward.t.sol#L211
[test_whenAbovePercentBoundary]: keeperReward.t.sol#L157
[test_whenAtBacking]: keeperReward.t.sol#L202
[test_whenAtPercentBoundary]: keeperReward.t.sol#L148
[test_whenBelowBacking]: keeperReward.t.sol#L193
[test_whenBelowPercentBoundary]: keeperReward.t.sol#L139
[test_whenCapAbovePercent]: keeperReward.t.sol#L184
[test_whenCapBelowPercent]: keeperReward.t.sol#L166
[test_whenCapEqualsPercent]: keeperReward.t.sol#L175
[test_whenFractionalShareReward]: keeperReward.t.sol#L265
[test_whenFractionalUnderlyingReward]: keeperReward.t.sol#L220
[test_whenRequiredBackingOverflows_reverts]: keeperReward.t.sol#L382
[test_whenRewardLeavesBackingRemainder]: keeperReward.t.sol#L229
[test_whenShareCollateralIsZero]: keeperReward.t.sol#L308
[test_whenShareConversionUsesAnyRepresentableOutput]: keeperReward.t.sol#L283
[test_whenShareOutputMaximum]: keeperReward.t.sol#L298
[test_whenSharesAboveUnity]: keeperReward.t.sol#L256
[test_whenSharesAtUnity]: keeperReward.t.sol#L247
[test_whenSharesBelowUnity]: keeperReward.t.sol#L238
[test_whenZeroCollateralOutputEndpoints]: keeperReward.t.sol#L319
[test_whenZeroShareOutput]: keeperReward.t.sol#L274

[test_givenBackingUnavailable_whenConsumed_reverts]: ./keeperReward.t.sol#L390

[test_givenBackingLifecycleBoundaries_whenConsumed_reverts]: ./keeperReward.t.sol#L404

[test_givenFreshCachedPrices_whenRewardQuoted]: keeperReward.t.sol#L85
[test_givenLivePrices_whenRewardQuoted]: keeperReward.t.sol#L103
[test_givenMissingMarket_whenRewardQuoted_reverts]: keeperReward.t.sol#L73
[test_givenInvalidLivePrice_whenRewardQuoted_reverts]: keeperReward.t.sol#L120
