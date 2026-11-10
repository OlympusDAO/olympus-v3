# BurnerLoansRisk.snapshot coverage plan

Source: [snapshot](../../../policies/burnerloans/BurnerLoansRisk.sol#L201). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

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

## Backing lifecycle acceptance

Both fresh cached prices and live PRICE reads require a same-Kernel, active and
enabled backing policy immediately before backing acquisition. Getter failures
still propagate independently; restoration uses current backing, not cached backing.

| ID | Caller | Scenario | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-SNAPSHOT-D01 | Test caller (permissionless API) | Oracle active/enabled vary independently; exclude true/true | PolicyDependency_NotActive(oracle); no committed changes | Covered: [test][test_givenBackingUnavailable_whenConsumed_reverts] |
| BLRISK-SNAPSHOT-D02 | Test caller (permissionless API) | Deterministic oracle states: active/disabled, inactive/enabled, inactive/disabled | PolicyDependency_NotActive(oracle) for each seed | Covered: [test][test_givenBackingLifecycleBoundaries_whenConsumed_reverts] |
| BLRISK-SNAPSHOT-D03 | Test caller (permissionless API) | Fresh cached prices; pause oracle, change backing to 2e18, restore enablement | Paused call: PolicyDependency_NotActive(oracle); restored snapshot backing=2e18 | Covered: [test][test_givenFreshCache_whenBackingPaused_thenRestored] |
| BLRISK-SNAPSHOT-D04 | Test caller (permissionless API) | Oracle isEnabled() returns noncanonical bool word 2 | PolicyDependency_InvalidDependency(oracle) | Covered: [test][test_givenBackingMalformedEnabled_whenConsumed_reverts] |

## Backing availability regressions

Local policy and ordinary dependencies are active/enabled; callers satisfy the
existing action authorization. Each fault varies backing readiness independently.
Rejection preserves authoritative accounting, custody and emitted logs.

| ID | Scenario | Expected execution and preview | Test |
| --- | --- | --- | --- |
| BLRISK-SNAPSHOT-D05 | Oracle migrated alone; old Kernel still records active membership | PolicyDependency_KernelMismatch(oracle,old Kernel,new Kernel) | Covered: [test][test_givenMigratedOracle_whenOldKernelMembershipRemains_reverts] |
| BLRISK-SNAPSHOT-D06 | Risk and oracle moved; new Kernel activates Risk before oracle | PolicyDependency_NotActive(oracle), then backing=1e18 after oracle activation | Covered: [test][test_givenKernelMigration_whenOracleReactivated_thenPricingRestored] |

## Stateful readiness

The handler varies oracle Kernel membership and enablement independently, alongside
Risk pause/enable and authorized configuration. An already-enabled Risk may remain
enabled during an oracle outage, but snapshot consumption must reject; restoration
permits consumption again. Local Risk disablement retains its own guard.

| ID | Sequence | Expected invariant | Test |
| --- | --- | --- | --- |
| BLRISK-SNAPSHOT-S01 | Arbitrary oracle active/enabled and Risk lifecycle/configuration actions | Enabled Risk consumes backing only while its oracle is active and enabled | Covered: [invariant][invariant_backingConsumptionRequiresReadiness] |

[test_givenCacheAtDeadline_whenPricesRead]: snapshot.t.sol#L190
[test_givenCacheExpired_whenPricesRead]: snapshot.t.sol#L197
[test_givenCacheFailure_whenPricesRead_reverts]: snapshot.t.sol#L425
[test_givenCacheFresh_whenPricesRead]: snapshot.t.sol#L183
[test_givenCacheFuture_whenPricesRead]: snapshot.t.sol#L204
[test_givenCacheTimestampZero_whenPricesRead]: snapshot.t.sol#L102
[test_givenCachedCollateralZero_whenPricesRead_reverts]: snapshot.t.sol#L117
[test_givenCachedOhmZero_whenPricesRead_reverts]: snapshot.t.sol#L109
[test_givenCollateralAtObservationDeadline_whenPricesRead]: snapshot.t.sol#L218
[test_givenCollateralStale_whenPricesRead_reverts]: snapshot.t.sol#L167
[test_givenCollateralTimestampZero_whenPricesRead_reverts]: snapshot.t.sol#L159
[test_givenDirectCollateralZero_whenPricesRead_reverts]: snapshot.t.sol#L135
[test_givenDirectOhmZero_whenPricesRead_reverts]: snapshot.t.sol#L127
[test_givenDisabledCache_whenPricesRead]: snapshot.t.sol#L84
[test_givenDisabled_whenCalled_reverts]: snapshot.t.sol#L29
[test_givenInactiveAndDisabled_whenCalled_reverts]: snapshot.t.sol#L43
[test_givenInactiveCache_whenPricesRead]: snapshot.t.sol#L66
[test_givenInactive_whenCalled_reverts]: snapshot.t.sol#L36
[test_givenNoCache_whenPricesRead]: snapshot.t.sol#L58
[test_givenOhmAtObservationDeadline_whenPricesRead]: snapshot.t.sol#L211
[test_givenOhmStale_whenPricesRead_reverts]: snapshot.t.sol#L151
[test_givenOhmTimestampZero_whenPricesRead_reverts]: snapshot.t.sol#L143
[test_givenOperational_whenCalled]: snapshot.t.sol#L23
[test_givenOracleFailure_whenPricesRead_reverts]: snapshot.t.sol#L449
[test_givenPriceFailure_whenPricesRead_reverts]: snapshot.t.sol#L437
[test_givenPriceModuleUpgrade_whenPricesRead]: snapshot.t.sol#L461
[test_givenReEnabled_whenCalled]: snapshot.t.sol#L52
[test_givenZeroBacking_whenPricesRead_reverts]: snapshot.t.sol#L175
[test_whenBacking0BoundarySeeds]: snapshot.t.sol#L240
[test_whenBacking18BoundarySeeds]: snapshot.t.sol#L319
[test_whenBacking36BoundarySeeds]: snapshot.t.sol#L356
[test_whenBacking6BoundarySeeds]: snapshot.t.sol#L282
[test_whenBackingConversionOverflows_reverts]: snapshot.t.sol#L416
[test_whenBackingUses0PriceDecimals]: snapshot.t.sol#L225
[test_whenBackingUses18PriceDecimals]: snapshot.t.sol#L309
[test_whenBackingUses36PriceDecimals]: snapshot.t.sol#L346
[test_whenBackingUses6PriceDecimals]: snapshot.t.sol#L267
[test_whenPriceScaleCannotFit_reverts]: snapshot.t.sol#L405
[test_whenUnsupportedScaleBoundaries_reverts]: snapshot.t.sol#L410
[test_givenBackingUnavailable_whenConsumed_reverts]: ./snapshot.t.sol#L472
[test_givenBackingLifecycleBoundaries_whenConsumed_reverts]: ./snapshot.t.sol#L486
[test_givenFreshCache_whenBackingPaused_thenRestored]: ./snapshot.t.sol#L496
[test_givenBackingMalformedEnabled_whenConsumed_reverts]: ./snapshot.t.sol#L515
[test_givenMigratedOracle_whenOldKernelMembershipRemains_reverts]: ./snapshot.t.sol#L531
[test_givenKernelMigration_whenOracleReactivated_thenPricingRestored]: ./snapshot.t.sol#L548

[invariant_backingConsumptionRequiresReadiness]: ./setConfigOperator.invariant.t.sol#L50
