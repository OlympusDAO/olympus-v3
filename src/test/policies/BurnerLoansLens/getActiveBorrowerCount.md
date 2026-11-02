# BurnerLoansLens.getActiveBorrowerCount coverage plan

This permissionless getter returns FLOAN's current active-borrower count for the asset's canonical market. It remains available across all Core active/enabled combinations and reads no Risk, prices, positions or full borrower array. It allocates no array proportional to population. The task uses the count to normalize a stale cursor before scanning.

| ID | Caller | State/input | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLLENS-COUNT-A01 | Fuzz every caller | Registered asset; any canonical count | Exact count, independent of caller; no writes | Covered: [test][test_givenCoreLifecycle_whenCountQueried] |
| BLLENS-COUNT-L01 | Fuzz every caller | Core active/enabled independently false/true; seed all four combinations | Same count; no lifecycle admission | Covered: [test][test_givenCoreLifecycle_whenCountQueried], [test][test_whenLifecycleAndCountBoundariesSeeded] |
| BLLENS-COUNT-N01 | Fuzz every caller | Count fuzz 0..MAX256; seed 0,1,MAX256 | Forward the uint256 count without truncation or full-array reads | Covered: [test][test_givenCoreLifecycle_whenCountQueried], [test][test_whenLifecycleAndCountBoundariesSeeded] |
| BLLENS-COUNT-I01 | Fuzz every caller | Unregistered address including zero | BurnerLoansCore_AssetNotConfigured(asset) | Covered: [test][test_whenAssetUnregistered_reverts], [test][test_whenZeroAsset_reverts] |
| BLLENS-COUNT-P01 | Any viewer | Empty market, two borrowers, one fully repaid, remaining borrower defaulted | Counts 0,2,1,0 from authoritative FLOAN state | Covered: [test][test_givenBorrowerDebtChanges_whenCountQueried_thenLiveCount] |
| BLLENS-COUNT-T01 | Any viewer | FLOAN count getter reverts | Exact dependency error propagates | Covered: [test][test_givenCountReadFails_whenQueried_reverts] |

[test_givenCoreLifecycle_whenCountQueried]: ./getActiveBorrowerCount.t.sol#L13
[test_whenLifecycleAndCountBoundariesSeeded]: ./getActiveBorrowerCount.t.sol#L29
[test_whenAssetUnregistered_reverts]: ./getActiveBorrowerCount.t.sol#L50
[test_whenZeroAsset_reverts]: ./getActiveBorrowerCount.t.sol#L63
[test_givenBorrowerDebtChanges_whenCountQueried_thenLiveCount]: ./getActiveBorrowerCount.t.sol#L68
[test_givenCountReadFails_whenQueried_reverts]: ./getActiveBorrowerCount.t.sol#L88
