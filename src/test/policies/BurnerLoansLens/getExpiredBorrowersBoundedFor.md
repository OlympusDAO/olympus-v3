# BurnerLoansLens.getExpiredBorrowersBoundedFor coverage plan

Source: [getExpiredBorrowersBoundedFor](../../../policies/burnerloans/BurnerLoansLens.sol#L189). Scope: `BLLENS-EXPIRED`.

## Discovery decision and acceptance criteria

Add one explicit expired-only For method returning borrowers, a cursor and the aggregate keeper
reward quote for an explicit actor. Existing priced discovery APIs retain their exact pricing, eligibility and aggregate
reward semantics, including propagating snapshot failures for all-expired pages. Lazy snapshots alone
cannot pass an unexpired prefix during an outage; silently changing priced scans to partial results
would make their completeness and reward contract ambiguous.

Selection reads Core's market and FLOAN borrower/position records. It selects outstanding
principal with `now >= maturity` and skips unexpired debt without evaluating health. For a nonempty
selection, quote one aggregate custody redemption and Risk keeper reward for actor, as with the
existing For variants. HEART-only, seizer-only and overlapping protocol actors receive zero without
snapshot or health reads. Risk owns all reward pricing: ordinary actors need prices when reward
calculation needs them, while zero configured BPS or a zero reward cap returns zero without prices.
This preserves the existing Risk quotation contract instead of recreating execution admission in
Lens. The maturity selection and reward estimate do not promise that Seize can execute: ordinary
Seize and its preview still require valid prices even for zero configured rewards, as well as their
own lifecycle, authorization, solvency and custody checks. Custody and Risk quote failures propagate;
Lens never converts a failed quote into zero. Empty results require no economic reads. Caller and
actor are independent, including zero identities. A quote conveys no execution authority.

Pagination matches bounded priced discovery: validate asset and start before shortcuts; examine at
most min(count,N-start) entries in the active borrower list, stop at maxResults, and return the first unexamined index
or zero at the end. No wrap within a call. Zero limits preserve start. MAX means uint256.max.
Lens has no lifecycle; Core lifecycle does not gate these borrower views. Unchanged means no writes,
token movements or logs. Callback/accounting invariants belong to unchanged Seize/Core settlement;
this method makes only static reads.

| ID | Caller | Positions / inputs | Return / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-EXPIRED-P01 | Fuzz all addresses | Unexpired prefix, expired suffix, debt-free entry; protocol actor | Only expired debt in list order; unexpired never classified | Unchanged; no snapshot/health reads | Covered: [test][test_givenMixedPage_whenQueried]; [test][test_givenMissingPosition_whenQueried] |
| BLLENS-EXPIRED-P02 | All addresses | All expired / all unexpired | All debt / empty; cursor reaches zero | Unchanged | Covered: [test][test_givenAllExpired_whenQueried]; [test][test_givenAllUnexpired_whenQueried] |
| BLLENS-EXPIRED-N01 | All addresses | Maturity before, equal to, after now; debt zero, one, MAX128 | Only positive debt at/before now | Unchanged | Covered: [test][test_givenMixedPage_whenQueried]; [test][test_givenAllUnexpired_whenQueried] |
| BLLENS-EXPIRED-N02 | Fuzz all addresses | count and result limits 0,1,2,N,N+1,MAX; fuzz 0..MAX; start 0..N-1 | Clipped bounded suffix; stop without dropping candidates; precise cursor | Unchanged | Covered: [test][test_givenResultCapReached_whenQueried]; [test][test_givenMixedPage_whenLimitsFuzzed]; [test][test_givenMixedPage_whenLimitBoundariesSeeded] |
| BLLENS-EXPIRED-N03 | All addresses | Empty list; count/results 0,1,MAX | Empty; cursor zero; no position reads | Unchanged | Covered: [test][test_givenEmptyMarket_whenQueried] |
| BLLENS-EXPIRED-I01 | All addresses | Nonempty start >=N; empty start>0; seeds N,MAX; zero limits too | BurnerLoansLens_InvalidStart(start,N) | Unchanged | Covered: [test][test_givenInvalidStart_whenQueried_reverts]; [test][test_givenInvalidStart_whenBoundarySeedsQueried_reverts] |
| BLLENS-EXPIRED-I02 | All addresses | Unregistered zero/nonzero asset; zero limits too | BurnerLoansCore_AssetNotConfigured(asset) | Unchanged | Covered: [test][test_givenUnregisteredAsset_whenQueried_reverts]; [test][test_whenZeroAssetQueried_reverts] |
| BLLENS-EXPIRED-D01 | All addresses | FLOAN count/index/position read fails | Exact dependency error propagates | Unchanged | Covered: [test][test_givenCountFailure_whenQueried_reverts]; [test][test_givenIndexFailure_whenQueried_reverts]; [test][test_givenPositionFailure_whenQueried_reverts] |
| BLLENS-EXPIRED-L01 | Fuzz all addresses | Core active/enabled independently false/true, then restored | Same expired selection | Unchanged | Covered: [test][test_givenCoreLifecycle_whenQueried] |
| BLLENS-EXPIRED-A01 | Fuzz caller; actor HEART only, seizer only or both | Expired selection during outage | Same expired borrowers; zero reward without snapshot/health reads | Unchanged | Covered: [test][test_givenProtocolActorRoles_givenSnapshotFailure_whenQueried] |
| BLLENS-EXPIRED-A02 | Independently fuzz caller and ordinary actor, including zero; seed protocol caller | Prices valid; selected debt/collateral aggregated once | Exact ordinary keeper quote; caller roles do not affect actor reward | Unchanged | Covered: [test][test_givenOrdinaryActor_whenQuoted]; [test][test_givenProtocolCaller_whenZeroOrdinaryActorQuoted] |
| BLLENS-EXPIRED-D02 | Ordinary actor | Risk reward pricing fails, or zero configured BPS/cap bypasses prices | Propagate required reward-price error; return exact zero quote when Risk needs no prices; Seize preview still rejects the outage | Unchanged | Covered: [test][test_givenZeroRewardQuote_givenOrdinaryActor_givenSnapshotFailure_whenQueried]; [test][test_givenZeroRewardConfig_givenOutage_whenOrdinaryExpiredQuoteRequested] |
| BLLENS-EXPIRED-D03 | Protocol actor | Custody preview fails | Exact custody error | Unchanged | Covered: [test][test_givenWithdrawalQuoteFailure_whenQueried_reverts] |
| BLLENS-EXPIRED-D04 | Protocol actor | Risk keeper reward fails | Exact Risk error | Unchanged | Covered: [test][test_givenRewardQuoteFailure_whenQueried_reverts] |
| BLLENS-EXPIRED-A03 | Ordinary actor | Real priced expiry quote followed by unchanged Seize execution | Lens reward equals Seize preview and actual keeper-token delta | Expired principal fully settled | Covered: [test][test_givenPricesAvailable_whenOrdinaryExpiredQuoteSettled] |

## Work checklist

- [x] Choose and document behavior before implementation.
- [x] Add actor/reward regression tests before the API revision.
- [x] Implement the actor-aware bounded selection and task call.
- [x] Delegate reward pricing solely to Risk; verify zero-configuration quote/execution distinction.
- [x] Run revised focused suites, mapping checks, lint and size checks.

[test_givenInvalidStart_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L38

[test_givenInvalidStart_whenBoundarySeedsQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L46

[test_givenUnregisteredAsset_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L56

[test_givenCountFailure_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L68

[test_givenIndexFailure_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L79

[test_givenPositionFailure_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L91

[test_givenMixedPage_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L103

[test_givenMissingPosition_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L127

[test_givenResultCapReached_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L142

[test_whenZeroAssetQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L156

[test_givenAllExpired_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L167

[test_givenAllUnexpired_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L176

[test_givenMixedPage_whenLimitsFuzzed]: ./getExpiredBorrowersBoundedFor.t.sol#L185

[test_givenMixedPage_whenLimitBoundariesSeeded]: ./getExpiredBorrowersBoundedFor.t.sol#L212

[test_givenEmptyMarket_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L227

[test_givenCoreLifecycle_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L242

[test_givenProtocolActorRoles_givenSnapshotFailure_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L257

[test_givenOrdinaryActor_whenQuoted]: ./getExpiredBorrowersBoundedFor.t.sol#L286

[test_givenProtocolCaller_whenZeroOrdinaryActorQuoted]: ./getExpiredBorrowersBoundedFor.t.sol#L295

[test_givenZeroRewardQuote_givenOrdinaryActor_givenSnapshotFailure_whenQueried]: ./getExpiredBorrowersBoundedFor.t.sol#L301

[test_givenWithdrawalQuoteFailure_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L322

[test_givenRewardQuoteFailure_whenQueried_reverts]: ./getExpiredBorrowersBoundedFor.t.sol#L334

[test_givenPricesAvailable_whenOrdinaryExpiredQuoteSettled]: ../BurnerLoansSeizerTask/integration/executeOracleOutage.t.sol#L592

[test_givenZeroRewardConfig_givenOutage_whenOrdinaryExpiredQuoteRequested]: ../BurnerLoansSeizerTask/integration/executeOracleOutage.t.sol#L550
