# BurnerLoansLens.getUnhealthyBorrowersBoundedFor coverage plan

Scope: `BLLENS-UNHEALTHY`. This permissionless, read-only actor-aware scan selects positive debt
whose maturity is strictly after now and whose priced health is below1e18. Maturity equality belongs
exclusively to expiry discovery. Existing combined seizable getters retain their union behavior.

Validate asset/start before shortcuts; empty markets and zero limits need no economic reads.
Otherwise acquire the same eager Risk snapshot as combined priced discovery, including all-expired
pages. Count bounds inspected list entries, result limit bounds selected borrowers, and offsets
index the shared active-borrower list. Clip before allocation/addition; MAX means uint256.max.
Quote custody and actor reward once for a nonempty aggregate; propagate all dependency failures.
Core lifecycle does not gate these views. Lens has no local lifecycle. Static views make no transfers,
state changes or logs, so settlement callbacks/accounting invariants belong to Seize and Task tests.

| ID | Caller / actor | Positions / inputs | Expected selection / effects | Test |
| --- | --- | --- | --- | --- |
| BLLENS-UNHEALTHY-P01 | Fuzz caller; protocol actor | Expired, healthy, underwater and debt-free positions | Only unexpired positive unhealthy debt; no health evaluation of expired/debt-free entries; combined and expired APIs remain distinct | Covered: [test][test_givenMixedPage_whenQueried_thenExpiredDebtIsExcluded], [test][test_givenMixedDebtAndMaturityBoundaries_whenQueried], [test][test_givenMissingPosition_whenQueried], [test][test_givenAllExpired_givenHealthReadFails_whenQueried] |
| BLLENS-UNHEALTHY-N01 | Any caller | Maturity now-1, now, now+1, MAX48; principal0,1,MAX128; health0,1e18-1,1e18,1e18+1,MAX256 | Equality is expired; health equality is healthy; retain both immediately adjacent unhealthy boundaries | Covered: [test][test_givenMixedDebtAndMaturityBoundaries_whenQueried], [test][test_givenUnhealthyPositions_whenHealthBelowOne], [test][test_givenHealthyPositions_whenHealthAtOrAboveOne], [test][test_whenHealthBoundarySeedsQueried], [test][test_givenAllExpired_givenHealthReadFails_whenQueried] |
| BLLENS-UNHEALTHY-N02 | Fuzz caller | Valid starts0..N-1; count/results fuzz0..MAX256; deterministic0,1,N,N+1,MAX seeds | Exact bounded selection, early result cap, first unexamined cursor and end0; no skipped candidate | Covered: [test][test_givenMixedPage_whenLimitsFuzzed], [test][test_givenMixedPage_whenLimitBoundarySeedsQueried] |
| BLLENS-UNHEALTHY-N03 | Any caller | Empty market or zero count/results with valid start | Empty result; retain start; no snapshot, health or quote reads | Covered: [test][test_givenEmptyMarket_whenQueried], [test][test_givenZeroLimit_whenQueried] |
| BLLENS-UNHEALTHY-I01 | Any caller | Start>=N; empty start>0; seed N,MAX256 with zero and nonzero limits | Exact InvalidStart(start,N) before shortcut | Covered: [test][test_givenInvalidStart_whenQueried_reverts], [test][test_givenInvalidStart_whenBoundariesSeeded_reverts] |
| BLLENS-UNHEALTHY-I02 | Fuzz caller | Unregistered zero/nonzero asset, including zero limits | Exact AssetNotConfigured(asset) | Covered: [test][test_givenUnregisteredAsset_whenQueried_reverts], [test][test_whenZeroAssetQueried_reverts] |
| BLLENS-UNHEALTHY-D01 | Any caller | FLOAN count/index/position error | Exact dependency error propagates | Covered: [test][test_givenCountFailure_whenQueried_reverts], [test][test_givenIndexFailure_whenQueried_reverts], [test][test_givenPositionFailure_whenQueried_reverts] |
| BLLENS-UNHEALTHY-D02 | Any caller | Snapshot failure on mixed or all-expired page; health read fails on unexpired debt | Exact error propagates; no partial quote or classification | Covered: [test][test_givenSnapshotFailure_whenQueried_reverts], [test][test_givenHealthFailure_whenQueried_reverts] |
| BLLENS-UNHEALTHY-D03 | Any caller | Custody or keeper reward quote fails after selection | Exact quote error propagates | Covered: [test][test_givenCustodyQuoteFailure_whenQueried_reverts], [test][test_givenRewardQuoteFailure_whenQueried_reverts] |
| BLLENS-UNHEALTHY-A01 | Independently fuzz caller/ordinary actor including0; protocol actor seizer-only, HEART-only, both | Two selected borrowers with arbitrary aggregate quote | Aggregate debt/collateral forwarded once; actor roles choose protocol exemption independently of caller; exact quote returned | Covered: [test][test_givenOrdinaryActor_whenQuoted], [test][test_givenProtocolCaller_whenZeroOrdinaryActorQuoted], [test][test_givenProtocolActor_whenRoleClassesFuzzed], [test][test_givenSeizerOnlyActor_whenQuoted], [test][test_givenHeartOnlyActor_whenQuoted], [test][test_givenBothProtocolRoles_whenQuoted] |
| BLLENS-UNHEALTHY-L01 | Fuzz caller | Core active/enabled independently false/true, then restored | Same priced selection while Core disabled/inactive and after restoration; Risk/dependency failures still propagate | Covered: [test][test_givenCoreLifecycle_whenQueried] |

[test_givenMixedPage_whenQueried_thenExpiredDebtIsExcluded]: getUnhealthyBorrowersBoundedFor.t.sol#L38
[test_givenMixedDebtAndMaturityBoundaries_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L56
[test_givenMissingPosition_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L69
[test_givenAllExpired_givenHealthReadFails_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L261
[test_givenUnhealthyPositions_whenHealthBelowOne]: getUnhealthyBorrowersBoundedFor.t.sol#L83
[test_givenHealthyPositions_whenHealthAtOrAboveOne]: getUnhealthyBorrowersBoundedFor.t.sol#L90
[test_whenHealthBoundarySeedsQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L97
[test_givenMixedPage_whenLimitsFuzzed]: getUnhealthyBorrowersBoundedFor.t.sol#L106
[test_givenMixedPage_whenLimitBoundarySeedsQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L131
[test_givenEmptyMarket_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L145
[test_givenZeroLimit_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L153
[test_givenInvalidStart_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L166
[test_givenInvalidStart_whenBoundariesSeeded_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L174
[test_givenUnregisteredAsset_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L184
[test_whenZeroAssetQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L196
[test_givenCountFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L207
[test_givenIndexFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L218
[test_givenPositionFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L233
[test_givenSnapshotFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L245
[test_givenHealthFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L274
[test_givenCustodyQuoteFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L286
[test_givenRewardQuoteFailure_whenQueried_reverts]: getUnhealthyBorrowersBoundedFor.t.sol#L298
[test_givenOrdinaryActor_whenQuoted]: getUnhealthyBorrowersBoundedFor.t.sol#L310
[test_givenProtocolCaller_whenZeroOrdinaryActorQuoted]: getUnhealthyBorrowersBoundedFor.t.sol#L319
[test_givenProtocolActor_whenRoleClassesFuzzed]: getUnhealthyBorrowersBoundedFor.t.sol#L325
[test_givenSeizerOnlyActor_whenQuoted]: getUnhealthyBorrowersBoundedFor.t.sol#L343
[test_givenHeartOnlyActor_whenQuoted]: getUnhealthyBorrowersBoundedFor.t.sol#L348
[test_givenBothProtocolRoles_whenQuoted]: getUnhealthyBorrowersBoundedFor.t.sol#L353
[test_givenCoreLifecycle_whenQueried]: getUnhealthyBorrowersBoundedFor.t.sol#L358
