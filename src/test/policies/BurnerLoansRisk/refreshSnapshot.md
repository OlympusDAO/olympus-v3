# BurnerLoansRisk.refreshSnapshot coverage plan

Source: [refreshSnapshot](../../../policies/burnerloans/BurnerLoansRisk.sol#L232). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-REFRESH` identifies this contract/function.

Permissionless, Risk active and enabled; no Core lifecycle dependency. Snapshot OHM/collateral/backing values use current Kernel PRICE decimals; cache activity/enabled, pair updatedAt and max age are independent. Backing oracle native precision is 18.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFRESH-L03 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-REFRESH-L04 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts] |
| BLRISK-REFRESH-L05 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts] |
| BLRISK-REFRESH-L06 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts] |

## Cache dependency lifecycle

Fixed for this table: Accounting / events: Independent value calculation; no state, token or event changes.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-REFRESH-L01 | Fuzz all callers | Cache inactive; no local cache enablement query | Direct PRICE pair | Covered: [test][test_givenInactiveCache_whenPricesRead] |
| BLRISK-REFRESH-L02 | Fuzz all callers | Cache active but locally disabled | Direct PRICE pair | Covered: [test][test_givenDisabledCache_whenPricesRead] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFRESH-I01 | Fuzz all callers | Cache address=0 | Direct PRICE pair; no cache calls | Independent value calculation; no state, token or event changes | Covered: [test][test_givenNoCache_whenPricesRead] |
| BLRISK-REFRESH-I02 | Fuzz all callers | Injected mock cache returns valid prices with updatedAt=0 | Use returned pair | Risk performs no additional timestamp rejection after refresh | Covered: [test][test_givenCacheTimestampZero_whenPricesRead] |
| BLRISK-REFRESH-I03 | Fuzz all callers | cached branch; OHM price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCachedOhmZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I04 | Fuzz all callers | cached branch; OHM valid, collateral price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCachedCollateralZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I05 | Fuzz all callers | direct branch; OHM price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenDirectOhmZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I06 | Fuzz all callers | direct branch; OHM valid, collateral price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenDirectCollateralZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I07 | Fuzz all callers | Direct branch; OHM timestamp=0; earlier observation valid | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenOhmTimestampZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I08 | Fuzz all callers | Direct branch; OHM observation age=frequency+1 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenOhmStale_whenPricesRead_reverts] |
| BLRISK-REFRESH-I09 | Fuzz all callers | Direct branch; collateral timestamp=0; earlier observation valid | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCollateralTimestampZero_whenPricesRead_reverts] |
| BLRISK-REFRESH-I10 | Fuzz all callers | Direct branch; collateral observation age=frequency+1 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCollateralStale_whenPricesRead_reverts] |
| BLRISK-REFRESH-I11 | Fuzz all callers | Valid pair; backing=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenZeroBacking_whenPricesRead_reverts], [test][test_givenBackingFailure_whenRefreshed_reverts] |

## Numeric boundaries and arithmetic

Unsupported PRICE precision is rejected by configureDependencies during activation/module replacement. The unsupported-decimal read case below simulates subsequent dependency drift to verify the retained runtime safeguard.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFRESH-N01 | Fuzz all callers | Valid pair; representable backing18 in 1..MAX256; PRICE decimals 0,6,18,36 as distinct deterministic seeds | backingPrice=ceil(backing18*10**decimals/1e18) | Exactly one backing read; USD fields share PRICE scale | Covered: [test][test_whenBackingUses0PriceDecimals], [test][test_whenBacking0BoundarySeeds], [test][test_whenBackingUses6PriceDecimals], [test][test_whenBacking6BoundarySeeds], [test][test_whenBackingUses18PriceDecimals], [test][test_whenBacking18BoundarySeeds], [test][test_whenBackingUses36PriceDecimals], [test][test_whenBacking36BoundarySeeds] |
| BLRISK-REFRESH-N02 | Fuzz all callers | After successful configuration, simulate PRICE decimals changing to 78..MAX8; seed 78,MAX8 | LoanMath_UnsupportedDecimals(decimals) | Unchanged; no committed logs | Covered: [test][test_whenPriceScaleCannotFit_reverts], [test][test_whenUnsupportedScaleBoundaries_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFRESH-P01 | Fuzz all callers | Operational cache; valid prices returned by cachePriceIfNecessary | Use returned pair | Call cache exactly once; preserve its successful maintenance writes | Covered: [test][test_givenStaleCache_whenRefreshed] |
| BLRISK-REFRESH-P02 | Fuzz all callers | Direct branch; OHM observation age=frequency | Accept observation | Independent value calculation; no state, token or event changes | Covered: [test][test_givenOhmAtObservationDeadline_whenPricesRead] |
| BLRISK-REFRESH-P03 | Fuzz all callers | Direct branch; collateral observation age=frequency | Accept observation | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCollateralAtObservationDeadline_whenPricesRead] |
| BLRISK-REFRESH-P04 | Fuzz all callers | Backing conversion quotient does not fit uint256 | `Panic(0x11)` | Unchanged; no committed logs | Covered: [test][test_whenBackingConversionOverflows_reverts] |
| BLRISK-REFRESH-P05 | Fuzz all callers | Cache dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenCacheFailure_whenPricesRead_reverts] |
| BLRISK-REFRESH-P06 | Fuzz all callers | PRICE dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenPriceFailure_whenPricesRead_reverts] |
| BLRISK-REFRESH-P07 | Fuzz all callers | Backing oracle dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenOracleFailure_whenPricesRead_reverts] |
| BLRISK-REFRESH-P08 | Fuzz all callers | Kernel PRICE replaced between successful calls | Resolve current PRICE module | No stale stored module binding | Covered: [test][test_givenPriceModuleUpgrade_whenPricesRead] |

## Callbacks and reentrancy

Fixed for this table: Accounting / events: Risk stores no position state. Action-level scenarios below and in the corresponding action plans prove reload/validation after the unguarded cache call; transfer callbacks during Core settlement are a separate boundary.

| ID | Caller | Callback / nested call | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-REFRESH-C01 | Fuzz all callers | Authorized cache callback changes canonical loan state | Snapshot completes | Covered: [test][test_givenAuthorizedCacheCallback_whenCanonicalMarketChanges] |

## Shared assertions

Assert each snapshot field against independently calculated prices/backing conversion. Cache maxAge at the exact boundary; stale view fallback and refresh may legitimately differ because maintenance changes price. A future updatedAt is currently accepted by the freshness expression: record source behavior rather than inventing future-timestamp rejection.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Port one refresh call and one backing read per priced action with cache getter deliberately reverting; pair orientation both address orders, fresh cache round unchanged, stale round refreshed, and rollback of refresh on failed settlement. Debt-bearing deposits and partial repayments each capture one snapshot; debt-free deposits and full repayments perform no pricing calls.

[test_givenAuthorizedCacheCallback_whenCanonicalMarketChanges]: refreshSnapshot.t.sol#L516
[test_givenBackingFailure_whenRefreshed_reverts]: refreshSnapshot.t.sol#L210
[test_givenCacheFailure_whenPricesRead_reverts]: refreshSnapshot.t.sol#L469
[test_givenCacheTimestampZero_whenPricesRead]: refreshSnapshot.t.sol#L103
[test_givenCachedCollateralZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L118
[test_givenCachedOhmZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L110
[test_givenCollateralAtObservationDeadline_whenPricesRead]: refreshSnapshot.t.sol#L241
[test_givenCollateralStale_whenPricesRead_reverts]: refreshSnapshot.t.sol#L168
[test_givenCollateralTimestampZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L160
[test_givenDirectCollateralZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L136
[test_givenDirectOhmZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L128
[test_givenDisabledCache_whenPricesRead]: refreshSnapshot.t.sol#L85
[test_givenDisabled_whenCalled_reverts]: refreshSnapshot.t.sol#L30
[test_givenInactiveAndDisabled_whenCalled_reverts]: refreshSnapshot.t.sol#L44
[test_givenInactiveCache_whenPricesRead]: refreshSnapshot.t.sol#L67
[test_givenInactive_whenCalled_reverts]: refreshSnapshot.t.sol#L37
[test_givenNoCache_whenPricesRead]: refreshSnapshot.t.sol#L59
[test_givenOhmAtObservationDeadline_whenPricesRead]: refreshSnapshot.t.sol#L234
[test_givenOhmStale_whenPricesRead_reverts]: refreshSnapshot.t.sol#L152
[test_givenOhmTimestampZero_whenPricesRead_reverts]: refreshSnapshot.t.sol#L144
[test_givenOperational_whenCalled]: refreshSnapshot.t.sol#L24
[test_givenOracleFailure_whenPricesRead_reverts]: refreshSnapshot.t.sol#L493
[test_givenPriceFailure_whenPricesRead_reverts]: refreshSnapshot.t.sol#L481
[test_givenPriceModuleUpgrade_whenPricesRead]: refreshSnapshot.t.sol#L505
[test_givenReEnabled_whenCalled]: refreshSnapshot.t.sol#L53
[test_givenStaleCache_whenRefreshed]: refreshSnapshot.t.sol#L184
[test_givenZeroBacking_whenPricesRead_reverts]: refreshSnapshot.t.sol#L176
[test_whenBacking0BoundarySeeds]: refreshSnapshot.t.sol#L267
[test_whenBacking18BoundarySeeds]: refreshSnapshot.t.sol#L354
[test_whenBacking36BoundarySeeds]: refreshSnapshot.t.sol#L400
[test_whenBacking6BoundarySeeds]: refreshSnapshot.t.sol#L313
[test_whenBackingConversionOverflows_reverts]: refreshSnapshot.t.sol#L460
[test_whenBackingUses0PriceDecimals]: refreshSnapshot.t.sol#L248
[test_whenBackingUses18PriceDecimals]: refreshSnapshot.t.sol#L340
[test_whenBackingUses36PriceDecimals]: refreshSnapshot.t.sol#L381
[test_whenBackingUses6PriceDecimals]: refreshSnapshot.t.sol#L294
[test_whenPriceScaleCannotFit_reverts]: refreshSnapshot.t.sol#L449
[test_whenUnsupportedScaleBoundaries_reverts]: refreshSnapshot.t.sol#L454
