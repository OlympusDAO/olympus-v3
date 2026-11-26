# BurnerLoansRisk.health coverage plan

Sources: [health](../../../policies/burnerloans/BurnerLoansRisk.sol#L322), [validateHealth](../../../policies/burnerloans/BurnerLoansRisk.sol#L337).

## Domains and notation

Scenario scope: `BLRISK-HEALTH`. Permissionless calculations require Risk active and enabled. Supply a uint32 canonical FLOAN market ID; Risk reads configuration directly from FLOAN, without Core calls. Position amounts are uint256 token units. Snapshot USD fields share PRICE's decimal scale; health is always WAD. Inputs are operation-local snapshots, without stored provenance or another price read.

validateHealth is the shared current/final position threshold wrapper used by borrowing, extension and withdrawal. In every applicable row below, call health and validateHealth under the same state/snapshot. The Validation column specifies both contexts: current uses finalPosition=false, final uses true. A below-WAD raw health quote is valid, but the wrapper rejects it. No writes, cache refresh, token calls or logs occur.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-HEALTH-L01 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-HEALTH-L02 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts], [test][test_givenDisabled_whenHealthValidated_reverts] |
| BLRISK-HEALTH-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts], [test][test_givenInactive_whenHealthValidated_reverts] |
| BLRISK-HEALTH-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts], [test][test_givenInactiveAndDisabled_whenHealthValidated_reverts] |

## Calculation branches

| ID | Caller | Debt / market / snapshot | health return | Validation | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-HEALTH-P01 | Fuzz all callers | Debt=0; missing market; zero snapshot | MAX256; no market lookup | Both contexts return MAX256 | Covered: [test][test_whenDebtIsZero], [test][test_whenDebtAndCollateralEndpoints] |
| BLRISK-HEALTH-P02 | Fuzz all callers | Debt>0; valid market; synthetic zero debt-price/backing requirement | MAX256 | Both contexts return MAX256; snapshot provenance is not authenticated | Covered: [test][test_whenRequirementIsZero], [test][test_whenDebtAndCollateralEndpoints] |
| BLRISK-HEALTH-P03 | Fuzz all callers | Valid positive requirement; unhealthy position | H below 1e18 | Current: BurnerLoans_UnhealthyPosition(H); final: BurnerLoans_UnhealthyFinalPosition(H) | Covered: [test][test_whenPositionIsUnhealthy_revertsValidation] |
| BLRISK-HEALTH-P07 | Fuzz all callers | Positive debt; representable requirement; exact healthy boundary | 1e18 | Both contexts return 1e18 | Covered: [test][test_whenPositionIsExactlyHealthy], [test][test_whenSnapshotFieldsAreMaximum] |
| BLRISK-HEALTH-P08 | Fuzz all callers | Positive debt; healthy position | H above 1e18 | Both contexts return H | Covered: [test][test_whenPositionIsHealthy] |
| BLRISK-HEALTH-P09 | Fixed caller | Same exact economic inputs at PRICE decimals 6,8,18,36; distinct fixtures | Same independently expected WAD health | Same accepted value or threshold error | Covered: [test][test_whenExactEconomicsUse6PriceDecimals], [test][test_whenExactEconomicsUse8PriceDecimals], [test][test_whenExactEconomicsUse18PriceDecimals], [test][test_whenExactEconomicsUse36PriceDecimals] |
| BLRISK-HEALTH-P10 | Fixed caller | Inexact conversions at PRICE decimals 6,8,18,36; distinct fixtures | Hand-calculated WAD health at each precision | Same accepted value or threshold error; rounding may differ across scales | Covered: [test][test_whenInexactEconomicsUse6PriceDecimals], [test][test_whenInexactEconomicsUse8PriceDecimals], [test][test_whenInexactEconomicsUse18PriceDecimals], [test][test_whenInexactEconomicsUse36PriceDecimals] |

## Fixed requirement and health boundaries

OHM decimals=9, collateral decimals=6, debt=1e9, OHM price=2e18, collateral price=1e18, maxLtvBps=10000, backingMultiplierBps=10000. The market requirement is $2. At backing prices $1/$2/$3, backing requirement is $1/$2/$3 respectively. Hard-code expected integers; include the following working in test comments. Do not compute expected values with LoanMath or copy the implementation's max/formula logic.

| ID | Caller | Backing price | Collateral raw units | Working | health return | Validation | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-HEALTH-N03 | Fixed caller | 1e18 | 1999999 | $1.999999 / $2 = 0.9999995 | 999999500000000000 | Current/final unhealthy errors with this H | Covered: [test][test_givenMarketRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation] |
| BLRISK-HEALTH-P04 | Fixed caller | 1e18 | 2000000 | $2 / $2 = 1 | 1000000000000000000 | Both contexts accept | Covered: [test][test_givenMarketRequirementBinds_whenCollateralEqualsRequirement] |
| BLRISK-HEALTH-N04 | Fixed caller | 1e18 | 2000001 | $2.000001 / $2 = 1.0000005 | 1000000500000000000 | Both contexts accept | Covered: [test][test_givenMarketRequirementBinds_whenCollateralIsOneUnitAbove] |
| BLRISK-HEALTH-N05 | Fixed caller | 2e18 | 1999999 | Equal requirements; $1.999999 / $2 | 999999500000000000 | Current/final unhealthy errors with this H | Covered: [test][test_givenRequirementsEqual_whenCollateralIsOneUnitBelow_revertsValidation] |
| BLRISK-HEALTH-P05 | Fixed caller | 2e18 | 2000000 | Equal requirements; $2 / $2 | 1000000000000000000 | Both contexts accept | Covered: [test][test_givenRequirementsEqual_whenCollateralEqualsRequirement] |
| BLRISK-HEALTH-N06 | Fixed caller | 2e18 | 2000001 | Equal requirements; $2.000001 / $2 | 1000000500000000000 | Both contexts accept | Covered: [test][test_givenRequirementsEqual_whenCollateralIsOneUnitAbove] |
| BLRISK-HEALTH-N07 | Fixed caller | 3e18 | 2999999 | floor(2999999 * 1e18 / 3000000) | 999999666666666666 | Current/final unhealthy errors with this H | Covered: [test][test_givenBackingRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation] |
| BLRISK-HEALTH-P06 | Fixed caller | 3e18 | 3000000 | Backing binds; $3 / $3 | 1000000000000000000 | Both contexts accept | Covered: [test][test_givenBackingRequirementBinds_whenCollateralEqualsRequirement] |
| BLRISK-HEALTH-N08 | Fixed caller | 3e18 | 3000001 | floor(3000001 * 1e18 / 3000000) | 1000000333333333333 | Both contexts accept | Covered: [test][test_givenBackingRequirementBinds_whenCollateralIsOneUnitAbove] |

## Invalid market inputs

| ID | Caller | Market | health error | Validation | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-HEALTH-P11 | Fuzz all callers | Missing market ID; debt>0 | FLOAN_InvalidMarket(id) | Same exact error | Covered: [test][test_whenMarketMissing_reverts] |
| BLRISK-HEALTH-I01 | Fuzz all callers | Existing market uses another debt token; debt>0 | BurnerLoansRisk_InvalidMarket(id) | Same exact error | Covered: [test][test_whenMarketDebtTokenDiffers_reverts] |

## Arithmetic limits

| ID | Caller | Arithmetic boundary | health error | Validation | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-HEALTH-N01 | Fixed caller | Full-precision quotient exceeds MAX256 after representable preceding operations | `Panic(0x11)` | Same exact error | Covered: [test][test_whenHealthQuotientOverflows_reverts] |
| BLRISK-HEALTH-N02 | Fixed caller | Round-up floor equals MAX256 with nonzero remainder | `Panic(0x11)` | Same exact error | Covered: [test][test_whenBackingRoundUpOverflows_thenFeeAndHealthRevert], [test][test_whenBackingRoundUpOverflows_reverts] |

- [x] Review expectations and complete remaining domains.
- [x] Map focused tests with reciprocal scenario IDs.

## Backing lifecycle acceptance

Nonzero-debt health and validateHealth require current oracle readiness even
with a captured snapshot. They do not reread backing. Zero-debt health retains
its max-uint shortcut; own Risk lifecycle checks still apply.

| ID | Caller | Scenario | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-HEALTH-D01 | Test caller (permissionless API) | Oracle active/enabled vary independently; exclude true/true | PolicyDependency_NotActive(oracle); no committed changes | Covered: [test][test_givenBackingUnavailable_whenConsumed_reverts] |
| BLRISK-HEALTH-D02 | Test caller (permissionless API) | Deterministic oracle states: active/disabled, inactive/enabled, inactive/disabled | PolicyDependency_NotActive(oracle) for each seed | Covered: [test][test_givenBackingLifecycleBoundaries_whenConsumed_reverts] |
| BLRISK-HEALTH-D03 | Test caller (permissionless API) | Oracle disabled; nonzero debt; both final-position flag values | PolicyDependency_NotActive(oracle) | Covered: [test][test_givenBackingDisabled_whenHealthValidated_reverts] |
| BLRISK-HEALTH-D04 | Test caller (permissionless API) | Oracle disabled; debt=0 for health and validateHealth | Both return uint256.max without backing consumption | Covered: [test][test_givenBackingDisabled_whenDebtFreeHealthValidated] |

## Backing availability regressions

Local policy and ordinary dependencies are active/enabled; callers satisfy the
existing action authorization. Each fault varies backing readiness independently.
Rejection preserves authoritative accounting, custody and emitted logs.

| ID | Scenario | Expected execution and preview | Test |
| --- | --- | --- | --- |
| BLRISK-HEALTH-D05 | Capture backing, fail backing getter, pause and restore oracle | Ready captured health=2e18; paused calculation: PolicyDependency_NotActive(oracle); restored health=2e18 | Covered: [test][test_givenCapturedBacking_whenGetterFails_thenHealthUsesCapture] |

[test_givenBackingRequirementBinds_whenCollateralEqualsRequirement]: health.t.sol#L121
[test_givenBackingRequirementBinds_whenCollateralIsOneUnitAbove]: health.t.sol#L127
[test_givenBackingRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation]: health.t.sol#L112
[test_givenDisabled_whenCalled_reverts]: health.t.sol#L145
[test_givenDisabled_whenHealthValidated_reverts]: health.t.sol#L180
[test_givenInactiveAndDisabled_whenCalled_reverts]: health.t.sol#L159
[test_givenInactiveAndDisabled_whenHealthValidated_reverts]: health.t.sol#L200
[test_givenInactive_whenCalled_reverts]: health.t.sol#L152
[test_givenInactive_whenHealthValidated_reverts]: health.t.sol#L190
[test_givenMarketRequirementBinds_whenCollateralEqualsRequirement]: health.t.sol#L82
[test_givenMarketRequirementBinds_whenCollateralIsOneUnitAbove]: health.t.sol#L88
[test_givenMarketRequirementBinds_whenCollateralIsOneUnitBelow_revertsValidation]: health.t.sol#L73
[test_givenOperational_whenCalled]: health.t.sol#L133
[test_givenReEnabled_whenCalled]: health.t.sol#L168
[test_givenRequirementsEqual_whenCollateralEqualsRequirement]: health.t.sol#L100
[test_givenRequirementsEqual_whenCollateralIsOneUnitAbove]: health.t.sol#L106
[test_givenRequirementsEqual_whenCollateralIsOneUnitBelow_revertsValidation]: health.t.sol#L94
[test_whenBackingRoundUpOverflows_reverts]: health.t.sol#L364
[test_whenBackingRoundUpOverflows_thenFeeAndHealthRevert]: fee.t.sol#L74
[test_whenDebtAndCollateralEndpoints]: health.t.sol#L525
[test_whenDebtIsZero]: health.t.sol#L259
[test_whenExactEconomicsUse18PriceDecimals]: health.t.sol#L438
[test_whenExactEconomicsUse36PriceDecimals]: health.t.sol#L475
[test_whenExactEconomicsUse6PriceDecimals]: health.t.sol#L380
[test_whenExactEconomicsUse8PriceDecimals]: health.t.sol#L409
[test_whenHealthQuotientOverflows_reverts]: health.t.sol#L351
[test_whenInexactEconomicsUse18PriceDecimals]: health.t.sol#L456
[test_whenInexactEconomicsUse36PriceDecimals]: health.t.sol#L493
[test_whenInexactEconomicsUse6PriceDecimals]: health.t.sol#L394
[test_whenInexactEconomicsUse8PriceDecimals]: health.t.sol#L423
[test_whenMarketDebtTokenDiffers_reverts]: health.t.sol#L334
[test_whenMarketMissing_reverts]: health.t.sol#L322
[test_whenPositionIsExactlyHealthy]: health.t.sol#L311
[test_whenPositionIsHealthy]: health.t.sol#L316
[test_whenPositionIsUnhealthy_revertsValidation]: health.t.sol#L283
[test_whenRequirementIsZero]: health.t.sol#L271
[test_whenSnapshotFieldsAreMaximum]: health.t.sol#L512
[test_givenBackingUnavailable_whenConsumed_reverts]: ./health.t.sol#L553
[test_givenBackingLifecycleBoundaries_whenConsumed_reverts]: ./health.t.sol#L567
[test_givenBackingDisabled_whenHealthValidated_reverts]: ./health.t.sol#L577
[test_givenBackingDisabled_whenDebtFreeHealthValidated]: ./health.t.sol#L589

[test_givenCapturedBacking_whenGetterFails_thenHealthUsesCapture]: ./health.t.sol#L604
