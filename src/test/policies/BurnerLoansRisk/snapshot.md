# BurnerLoansRisk.snapshot coverage plan

Source: [snapshot](../../../policies/burnerloans/BurnerLoansRisk.sol#L196). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-SNAPSHOT` identifies this contract/function.

Permissionless, Risk active and enabled; no Core lifecycle dependency. Snapshot OHM/collateral/backing values use current Kernel PRICE decimals; cache activity/enabled, pair updatedAt and max age are independent. Backing oracle native precision is 18.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-L03 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-SNAPSHOT-L04 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts] |
| BLRISK-SNAPSHOT-L05 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts] |
| BLRISK-SNAPSHOT-L06 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts] |

## Cache dependency lifecycle

Fixed for this table: Accounting / events: Independent value calculation; no state, token or event changes.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-L01 | Fuzz all callers | Cache inactive; no local cache enablement query | Direct PRICE pair | Covered: [test][test_givenInactiveCache_whenPricesRead] |
| BLRISK-SNAPSHOT-L02 | Fuzz all callers | Cache active but locally disabled | Direct PRICE pair | Covered: [test][test_givenDisabledCache_whenPricesRead] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-I01 | Fuzz all callers | Cache address=0 | Direct PRICE pair; no cache calls | Independent value calculation; no state, token or event changes | Covered: [test][test_givenNoCache_whenPricesRead] |
| BLRISK-SNAPSHOT-I02 | Fuzz all callers | Operational cache; updatedAt=0 | Direct PRICE fallback | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCacheTimestampZero_whenPricesRead] |
| BLRISK-SNAPSHOT-I03 | Fuzz all callers | cached branch; OHM price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCachedOhmZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I04 | Fuzz all callers | cached branch; OHM valid, collateral price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCachedCollateralZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I05 | Fuzz all callers | direct branch; OHM price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenDirectOhmZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I06 | Fuzz all callers | direct branch; OHM valid, collateral price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenDirectCollateralZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I07 | Fuzz all callers | Direct branch; OHM timestamp=0; earlier observation valid | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenOhmTimestampZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I08 | Fuzz all callers | Direct branch; OHM observation age=frequency+1 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenOhmStale_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I09 | Fuzz all callers | Direct branch; collateral timestamp=0; earlier observation valid | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCollateralTimestampZero_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I10 | Fuzz all callers | Direct branch; collateral observation age=frequency+1 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenCollateralStale_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-I11 | Fuzz all callers | Valid pair; backing=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_givenZeroBacking_whenPricesRead_reverts] |

## Numeric boundaries and arithmetic

Unsupported PRICE precision is rejected by configureDependencies during activation/module replacement. The unsupported-decimal read case below simulates subsequent dependency drift to verify the retained runtime safeguard.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-N01 | Fuzz all callers | Valid pair; representable backing18 in 1..MAX256; PRICE decimals 0,6,18,36 as distinct deterministic seeds | backingPrice=ceil(backing18*10**decimals/1e18) | Exactly one backing read; USD fields share PRICE scale | Covered: [test][test_whenBackingUses0PriceDecimals], [test][test_whenBacking0BoundarySeeds], [test][test_whenBackingUses6PriceDecimals], [test][test_whenBacking6BoundarySeeds], [test][test_whenBackingUses18PriceDecimals], [test][test_whenBacking18BoundarySeeds], [test][test_whenBackingUses36PriceDecimals], [test][test_whenBacking36BoundarySeeds] |
| BLRISK-SNAPSHOT-N02 | Fuzz all callers | After successful configuration, simulate PRICE decimals changing to 78..MAX8; seed 78,MAX8 | LoanMath_UnsupportedDecimals(decimals) | Unchanged; no committed logs | Covered: [test][test_whenPriceScaleCannotFit_reverts], [test][test_whenUnsupportedScaleBoundaries_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-P01 | Fuzz all callers | Operational cache; nonzero updatedAt; now<updatedAt+maxAge | Use cached pair | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCacheFresh_whenPricesRead] |
| BLRISK-SNAPSHOT-P02 | Fuzz all callers | Operational cache; now=updatedAt+maxAge | Use cached pair | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCacheAtDeadline_whenPricesRead] |
| BLRISK-SNAPSHOT-P03 | Fuzz all callers | Operational cache; now=updatedAt+maxAge+1 | Direct PRICE fallback | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCacheExpired_whenPricesRead] |
| BLRISK-SNAPSHOT-P04 | Fuzz all callers | Operational cache; updatedAt>now | Use cached pair under current source behavior | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCacheFuture_whenPricesRead] |
| BLRISK-SNAPSHOT-P05 | Fuzz all callers | Direct branch; OHM observation age=frequency | Accept observation | Independent value calculation; no state, token or event changes | Covered: [test][test_givenOhmAtObservationDeadline_whenPricesRead] |
| BLRISK-SNAPSHOT-P06 | Fuzz all callers | Direct branch; collateral observation age=frequency | Accept observation | Independent value calculation; no state, token or event changes | Covered: [test][test_givenCollateralAtObservationDeadline_whenPricesRead] |
| BLRISK-SNAPSHOT-P07 | Fuzz all callers | Backing conversion quotient does not fit uint256 | `Panic(0x11)` | Unchanged; no committed logs | Covered: [test][test_whenBackingConversionOverflows_reverts] |
| BLRISK-SNAPSHOT-P08 | Fuzz all callers | Cache dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenCacheFailure_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-P09 | Fuzz all callers | PRICE dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenPriceFailure_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-P10 | Fuzz all callers | Backing oracle dependency reverts with configured custom error | Exact configured dependency error | Unchanged; no committed logs | Covered: [test][test_givenOracleFailure_whenPricesRead_reverts] |
| BLRISK-SNAPSHOT-P11 | Fuzz all callers | Kernel PRICE replaced between successful calls | Resolve current PRICE module | No stale stored module binding | Covered: [test][test_givenPriceModuleUpgrade_whenPricesRead] |

## Shared assertions

Assert each snapshot field against independently calculated prices/backing conversion. Cache maxAge at the exact boundary; stale view fallback and refresh may legitimately differ because maintenance changes price. A future updatedAt is currently accepted by the freshness expression: record source behavior rather than inventing future-timestamp rejection.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Port production PriceCache pair orientation with collateral address below AND above OHM; max age UINT48_MAX; stale/disabled/inactive cache fallback; zero/stale production Chainlink feeds; six PRICE decimals with fractional backing conversion; malformed/reverting cached pair; future timestamps as current source behavior.

[test_givenCacheAtDeadline_whenPricesRead]: snapshot.t.sol#L188
[test_givenCacheExpired_whenPricesRead]: snapshot.t.sol#L195
[test_givenCacheFailure_whenPricesRead_reverts]: snapshot.t.sol#L439
[test_givenCacheFresh_whenPricesRead]: snapshot.t.sol#L181
[test_givenCacheFuture_whenPricesRead]: snapshot.t.sol#L202
[test_givenCacheTimestampZero_whenPricesRead]: snapshot.t.sol#L100
[test_givenCachedCollateralZero_whenPricesRead_reverts]: snapshot.t.sol#L115
[test_givenCachedOhmZero_whenPricesRead_reverts]: snapshot.t.sol#L107
[test_givenCollateralAtObservationDeadline_whenPricesRead]: snapshot.t.sol#L216
[test_givenCollateralStale_whenPricesRead_reverts]: snapshot.t.sol#L165
[test_givenCollateralTimestampZero_whenPricesRead_reverts]: snapshot.t.sol#L157
[test_givenDirectCollateralZero_whenPricesRead_reverts]: snapshot.t.sol#L133
[test_givenDirectOhmZero_whenPricesRead_reverts]: snapshot.t.sol#L125
[test_givenDisabledCache_whenPricesRead]: snapshot.t.sol#L82
[test_givenDisabled_whenCalled_reverts]: snapshot.t.sol#L27
[test_givenInactiveAndDisabled_whenCalled_reverts]: snapshot.t.sol#L41
[test_givenInactiveCache_whenPricesRead]: snapshot.t.sol#L64
[test_givenInactive_whenCalled_reverts]: snapshot.t.sol#L34
[test_givenNoCache_whenPricesRead]: snapshot.t.sol#L56
[test_givenOhmAtObservationDeadline_whenPricesRead]: snapshot.t.sol#L209
[test_givenOhmStale_whenPricesRead_reverts]: snapshot.t.sol#L149
[test_givenOhmTimestampZero_whenPricesRead_reverts]: snapshot.t.sol#L141
[test_givenOperational_whenCalled]: snapshot.t.sol#L21
[test_givenOracleFailure_whenPricesRead_reverts]: snapshot.t.sol#L463
[test_givenPriceFailure_whenPricesRead_reverts]: snapshot.t.sol#L451
[test_givenPriceModuleUpgrade_whenPricesRead]: snapshot.t.sol#L475
[test_givenReEnabled_whenCalled]: snapshot.t.sol#L50
[test_givenZeroBacking_whenPricesRead_reverts]: snapshot.t.sol#L173
[test_whenBacking0BoundarySeeds]: snapshot.t.sol#L242
[test_whenBacking18BoundarySeeds]: snapshot.t.sol#L329
[test_whenBacking36BoundarySeeds]: snapshot.t.sol#L370
[test_whenBacking6BoundarySeeds]: snapshot.t.sol#L288
[test_whenBackingConversionOverflows_reverts]: snapshot.t.sol#L430
[test_whenBackingUses0PriceDecimals]: snapshot.t.sol#L223
[test_whenBackingUses18PriceDecimals]: snapshot.t.sol#L315
[test_whenBackingUses36PriceDecimals]: snapshot.t.sol#L356
[test_whenBackingUses6PriceDecimals]: snapshot.t.sol#L269
[test_whenPriceScaleCannotFit_reverts]: snapshot.t.sol#L419
[test_whenUnsupportedScaleBoundaries_reverts]: snapshot.t.sol#L424
