# BurnerLoansLens.getSeizableBorrowersBoundedFor coverage plan

Source: [getSeizableBorrowersBoundedFor](../../../policies/burnerloans/BurnerLoansLens.sol).

Scenario scope: `BLLENS-BOUNDED`. Plain permissionless Lens: caller and reward actor are independent. Core's lifecycle does not gate reads. Risk and custody reads follow the existing scan requirements. `start`, `count` and `maxResults` are uint256; count and result cap vary independently through their entire ranges, including MAX256. No state writes or logs.

The scan examines only the remaining forward suffix. Stop immediately when the result cap is reached: never select a larger page and discard candidates. The returned cursor is the first unexamined index, or zero at the end. An empty market, zero count or zero result cap avoids pricing work after asset/start validation. The existing unbounded scan APIs retain their behavior.

The fixed borrower list is `[Alice eligible, Bob healthy, Carol eligible, Dave healthy]`, at
indices 0..3. `count` bounds entries examined, including healthy borrowers. `maxResults` bounds
eligible borrowers returned. Those limits are independent: count=4 and maxResults=1 return only
Alice and cursor 1. The next page starts at Bob, skips him, and finds Carol. Scanning all four,
truncating the result to Alice, and reporting an end cursor would lose Carol from pagination.
The immediate-stop test also proves Bob is not read during that first page.

Positive-page tests mock the aggregate keeper reward to 7, whether one or two borrowers are
selected. This proves forwarding of the selected page's quote; it is not a per-borrower reward
formula. Reward arithmetic is tested separately.

## Successful execution and boundaries

| ID | Caller / actor | Inputs / pre-state | Return and effects | Test |
| --- | --- | --- | --- | --- |
| BLLENS-BOUNDED-P01 | Independently fuzz caller and actor | Populated market; start=0; count=0; result cap fuzz 0..MAX256 | Empty results, cursor=0, reward=0; no scan/pricing work | Covered: [test][test_whenScanLimitZero_whenStartingAtZero] |
| BLLENS-BOUNDED-P02 | Independently fuzz caller and actor | Start=0; count fuzz 2..MAX256; result cap=1 | Return Alice, cursor=1, mocked aggregate reward=7; stop before reading Bob at index 1, leaving Carol unexamined at index 2 | Covered: [range][test_whenResultLimitOne_whenScanLimitGreaterThanOne], [no extra read][test_givenEligibleFirstBorrower_whenResultLimitOne] |
| BLLENS-BOUNDED-P08 | Independently fuzz caller and actor | Start=0; count fuzz 4..MAX256; result cap=2 | Return Alice,Carol; cursor=3; mocked aggregate reward=7; stop before the end | Covered: [test][test_whenScanLimitAtLeastFour_whenResultLimitTwo] |
| BLLENS-BOUNDED-P09 | Independently fuzz caller and actor | Start=0; count=1; result cap=1 | Both limits reached together; return Alice, cursor=1, reward=7 | Covered: [test][test_whenScanAndResultLimitsAreOne] |
| BLLENS-BOUNDED-P10 | Independently fuzz caller and actor | Start=0; count=1; result cap fuzz 2..MAX256 | Scan bound reached first; return Alice, cursor=1, reward=7 | Covered: [test][test_whenScanLimitOne_whenResultLimitGreaterThanOne] |
| BLLENS-BOUNDED-P11 | Independently fuzz caller and actor | Start=0; count=2; result cap fuzz 2..MAX256 | Inspect Alice and healthy Bob; return Alice, cursor=2, reward=7 | Covered: [test][test_whenScanLimitTwo_whenResultLimitAtLeastTwo] |
| BLLENS-BOUNDED-P12 | Independently fuzz caller and actor | Start=0; count=3; result cap=2 | Both limits reached together; return Alice,Carol; cursor=3; reward=7 | Covered: [test][test_whenScanLimitThree_whenResultLimitTwo] |
| BLLENS-BOUNDED-P13 | Independently fuzz caller and actor | Start=0; count=3; result cap fuzz 3..MAX256 | Scan bound reached first; return Alice,Carol; cursor=3; reward=7 | Covered: [test][test_whenScanLimitThree_whenResultLimitGreaterThanTwo] |
| BLLENS-BOUNDED-P14 | Independently fuzz caller and actor | Start=0; count fuzz 4..MAX256; result cap fuzz 3..MAX256 | Reach population end before result cap; return Alice,Carol; cursor=0; reward=7 | Covered: [test][test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo] |
| BLLENS-BOUNDED-P15 | Independently fuzz caller and actor | Start=0; count fuzz 1..MAX256; result cap=0 | Empty results, cursor=0, reward=0; no scan/pricing work | Covered: [test][test_whenResultLimitZero_whenScanLimitPositive] |
| BLLENS-BOUNDED-P16 | Independently fuzz caller and actor | Count=4 and result cap=1 on successive pages, starting at 0 and resuming at each returned cursor | Pages are Alice/cursor 1, Carol/cursor 3, then empty/cursor 0; neither eligible borrower is skipped or repeated | Covered: [test][test_givenResultLimitReached_whenResuming] |
| BLLENS-BOUNDED-N01 | Permissionless caller | Independently seed count/cap 0,1,2,3,4,MAX256; retain all 36 original pairs, plus zero caller/actor with maximum bounds | Explicit drivers check fixed expected pages and cursors; no runtime outcome selection | Covered: [zero][test_whenZeroLimitBoundariesSeeded], [one result][test_whenSingleResultLimitBoundariesSeeded], [two results][test_whenTwoResultsLimitBoundariesSeeded], [zero identities][test_whenCallerAndActorAreZero_whenBothLimitsMaximum] |
| BLLENS-BOUNDED-P03 | Fuzz all callers | Fuzz valid start and full-width count; result cap MAX256 | Exact agreement with existing actor-aware scan | Covered: [test][test_whenStartVaries_thenUnlimitedResultsAgreeWithExistingScan] |
| BLLENS-BOUNDED-P04 | Permissionless caller | Core independently active/inactive and enabled/disabled | Same bounded page; no upstream lifecycle requirement | Covered: [test][test_givenCoreUnavailable_whenScanned_thenNoUpstreamLifecycleGate] |
| BLLENS-BOUNDED-P05 | Permissionless caller | Empty market; start zero; arbitrary count/cap | Empty results, zero cursor/reward; no pricing reads | Covered: [test][test_givenEmptyMarket_whenScanned_thenNoPricingReads] |
| BLLENS-BOUNDED-P06 | Permissionless caller | Populated market, valid nonzero start; result cap zero | Empty results, unchanged start, zero reward; no scan/pricing reads | Covered: [test][test_givenPopulatedMarket_whenResultLimitZero_thenNoPricingReads] |
| BLLENS-BOUNDED-P07 | Permissionless caller | Populated market, valid nonzero start; scan cap zero | Empty results, unchanged start, zero reward; no scan/pricing reads | Covered: [test][test_givenPopulatedMarket_whenScanLimitZero_thenNoPricingReads] |

## Rejections

| ID | Input / competing condition | Exact result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLLENS-BOUNDED-I01 | Unregistered asset, including zero; arbitrary start/count/cap | BurnerLoansCore_AssetNotConfigured(asset) before bounds | No pricing reads or writes | Covered: [test][test_whenAssetIsUnknown_reverts] |
| BLLENS-BOUNDED-I02 | Fuzz start outside nonempty population through MAX256, or nonzero start in empty market; count/cap independently include zero/MAX256; seed maximum start and population explicitly | BurnerLoansLens_InvalidStart(start,population) before zero-limit shortcut | No pricing reads or writes | Covered: [test][test_whenStartIsInvalid_reverts], [test][test_givenEmptyMarket_whenStartNonzero_reverts], [seeds][test_whenMaximumStartBoundariesSeeded_reverts] |

- [x] Review expected independent bounds and cursor semantics.
- [x] Implement fuzz tests and boundary seed driver.
- [x] Map compatible rows to passing tests.

[test_whenScanLimitZero_whenStartingAtZero]: ./getSeizableBorrowersBoundedFor.t.sol#L17
[test_whenResultLimitOne_whenScanLimitGreaterThanOne]: ./getSeizableBorrowersBoundedFor.t.sol#L89
[test_givenEligibleFirstBorrower_whenResultLimitOne]: ./getSeizableBorrowersBoundedFor.t.sol#L176
[test_whenScanLimitAtLeastFour_whenResultLimitTwo]: ./getSeizableBorrowersBoundedFor.t.sol#L138
[test_whenScanAndResultLimitsAreOne]: ./getSeizableBorrowersBoundedFor.t.sol#L40
[test_whenScanLimitOne_whenResultLimitGreaterThanOne]: ./getSeizableBorrowersBoundedFor.t.sol#L53
[test_whenScanLimitTwo_whenResultLimitAtLeastTwo]: ./getSeizableBorrowersBoundedFor.t.sol#L71
[test_whenScanLimitThree_whenResultLimitTwo]: ./getSeizableBorrowersBoundedFor.t.sol#L107
[test_whenScanLimitThree_whenResultLimitGreaterThanTwo]: ./getSeizableBorrowersBoundedFor.t.sol#L120
[test_whenScanLimitAtLeastFour_whenResultLimitGreaterThanTwo]: ./getSeizableBorrowersBoundedFor.t.sol#L156
[test_whenResultLimitZero_whenScanLimitPositive]: ./getSeizableBorrowersBoundedFor.t.sol#L28
[test_givenResultLimitReached_whenResuming]: ./getSeizableBorrowersBoundedFor.t.sol#L198
[test_whenZeroLimitBoundariesSeeded]: ./getSeizableBorrowersBoundedFor.t.sol#L223
[test_whenSingleResultLimitBoundariesSeeded]: ./getSeizableBorrowersBoundedFor.t.sol#L240
[test_whenTwoResultsLimitBoundariesSeeded]: ./getSeizableBorrowersBoundedFor.t.sol#L257
[test_whenCallerAndActorAreZero_whenBothLimitsMaximum]: ./getSeizableBorrowersBoundedFor.t.sol#L293
[test_whenStartVaries_thenUnlimitedResultsAgreeWithExistingScan]: ./getSeizableBorrowersBoundedFor.t.sol#L303
[test_givenCoreUnavailable_whenScanned_thenNoUpstreamLifecycleGate]: ./getSeizableBorrowersBoundedFor.t.sol#L330
[test_givenEmptyMarket_whenScanned_thenNoPricingReads]: ./getSeizableBorrowersBoundedFor.t.sol#L392
[test_givenPopulatedMarket_whenResultLimitZero_thenNoPricingReads]: ./getSeizableBorrowersBoundedFor.t.sol#L447
[test_givenPopulatedMarket_whenScanLimitZero_thenNoPricingReads]: ./getSeizableBorrowersBoundedFor.t.sol#L460
[test_whenAssetIsUnknown_reverts]: ./getSeizableBorrowersBoundedFor.t.sol#L353
[test_whenStartIsInvalid_reverts]: ./getSeizableBorrowersBoundedFor.t.sol#L371
[test_givenEmptyMarket_whenStartNonzero_reverts]: ./getSeizableBorrowersBoundedFor.t.sol#L405
[test_whenMaximumStartBoundariesSeeded_reverts]: ./getSeizableBorrowersBoundedFor.t.sol#L423
