# BurnerLoansLens.getSeizableBorrowers coverage plan

Sources: [getSeizableBorrowers](../../../policies/burnerloans/BurnerLoansLens.sol#L144), [getSeizableBorrowersFor](../../../policies/burnerloans/BurnerLoansLens.sol#L156).

## Domains and notation

Scenario scope: `BLLENS-SEIZABLE`. Lens is a plain read-only helper without Kernel membership or IEnabler. SeizerTask owns operational control. Core is its immutable read dependency. All cases assert no writes or committed events. `MAXn=2**n-1`.

Target APIs: `getSeizableBorrowers(asset,start,count)` and `getSeizableBorrowersFor(actor,asset,start,count)`. Both use uint256 start/count. N is the current **total active borrower count**, independent of the requested page size. Start is a zero-based offset and count is the maximum number of borrowers examined, not the number of eligible results.

Scan forward without wrapping. For a nonempty list require start<N, examine min(count,N-start) borrowers, and return every eligible borrower in traversal order. Clamp count before allocation or addition so MAX256 cannot cause an oversized allocation or start+count overflow. Return the next unexamined index, or 0 when the end is reached; that 0 starts a **subsequent call**, never a wrap within this call. A valid count=0 returns empty borrowers, cursor=start and reward0 without pricing. An empty market accepts only start=0 and returns empty borrowers, cursor0 and reward0.

Keep the returned cursor so callers can identify a clipped final page without another borrower-count read. For example, N=5,start=2,count=4 examines only indices 2,3,4 and returns cursor0; raw start+count would be 6, outside the list.

Out-of-range start rejects before count=0/empty-list shortcuts or pricing. Expected product-owned error for implementation: `BurnerLoansLens_InvalidStart(start,N)`. The bound is N, not the count argument: start=3,count=1 is valid when N=4. No Lens return cap or seizure-batch cap applies.

The implementation uses the forward-only signature and validates the current canonical borrower count. Lens remains plain and its reads are independent of Core lifecycle. No Inventory lifecycle or solvency gate is added.

For **every row**, prank only the convenience call as caller C. Then call `getSeizableBorrowersFor(C,asset,start,count)` directly from the test contract, without a prank, under identical relevant state. Require the same borrowers, cursor and reward, or the same exact revert data. The For consistency column records this paired assertion. C is an explicit reward actor, never a forwarded authorization identity. Role-specific rows control C's grants independently of the unpranked test contract.

Consumer integration: the Seize execution batch limit remains separate. SeizerTask must request a count no larger than the batch it can settle and must not discard candidates while advancing its cursor. It must also handle a cursor made invalid by repayment/default shrinking the borrower list: validate/reset before scanning or recover explicitly from InvalidStart; retaining an invalid cursor indefinitely would strand future scans. Lens performs no automatic normalization. A larger manual scan may need several seizure transactions; an aggregate reward quote need not equal separately rounded chunk quotes.

## Core lifecycle independence

Core flags do not gate the query; actual read dependencies work. Lens has no lifecycle flags.

| ID | Caller | Core active | Core enabled | Execution | Effects | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-L01 | Fuzz all callers | true | true | Same result as corresponding successful read | No writes or logs | Same exact tuple; actor=C, no prank | Covered: [test_givenActiveEnabledCore_whenQueried][test_givenActiveEnabledCore_whenQueried] |
| BLLENS-SEIZABLE-L02 | Fuzz all callers | true | false | Same result as corresponding successful read | No writes or logs | Same exact tuple; actor=C, no prank | Covered: [test_givenActiveDisabledCore_whenQueried][test_givenActiveDisabledCore_whenQueried] |
| BLLENS-SEIZABLE-L03 | Fuzz all callers | false | true | Same result as corresponding successful read | No writes or logs | Same exact tuple; actor=C, no prank | Covered: [test_givenInactiveEnabledCore_whenQueried][test_givenInactiveEnabledCore_whenQueried] |
| BLLENS-SEIZABLE-L04 | Fuzz all callers | false | false | Same result as corresponding successful read | No writes or logs | Same exact tuple; actor=C, no prank | Covered: [test_givenInactiveDisabledCore_whenQueried][test_givenInactiveDisabledCore_whenQueried] |

## Invalid asset inputs

Use an ordinary reward actor; other dependencies work. Admission does not invent a count maximum. Fuzz page arguments independently for an unknown asset to prove market lookup precedes bounds and zero-work shortcuts.

| ID | Caller | Asset | start | count | Execution | Effects | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-I01 | Fuzz all callers | Nonzero unregistered asset | Fuzz 0..MAX256; seed 0,1,MAX256 | Independently fuzz 0..MAX256; seed 0,1,MAX256 | BurnerLoansCore_AssetNotConfigured(asset) | No writes or pricing reads; asset rejection precedes page validation | Same exact error; actor=C, no prank | Covered: [test_whenUnknownAsset_revertsBeforeBounds][test_whenUnknownAsset_revertsBeforeBounds] |
| BLLENS-SEIZABLE-I02 | Fuzz all callers | Zero asset, unregistered | 0 | 1 | BurnerLoansCore_AssetNotConfigured(0) | No writes | Same exact error; actor=C, no prank | Covered: [test_whenZeroAsset_reverts][test_whenZeroAsset_reverts] |

## Invalid start indices

Asset is registered. Range checks precede empty/count-zero shortcuts and do not invoke Risk. Mock FLOAN's borrower count for these bounds-only cases so N can reach MAX256 without allocating a borrower array. No borrower-index, snapshot, reward or withdrawal-preview read is permitted. N=0 is fixed in the empty-market case; population size is fuzzed independently in the nonempty case.

Fuzz count independently over 0..MAX256 in both cases. For each selected invalid (N,start), guarantee count=0,1,MAX256 without changing N or start, and require identical revert data. This proves count does not change start validation, including zero-work shortcuts and potential start+count overflow.

| ID | Caller | N | start | count | Expected error | Effects | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-I03 | Fuzz all callers | Fuzz 1..MAX256; seed 1,4,MAX256 | Independently fuzz N..MAX256; seed N,MAX256 and N+1 when representable; guarantee (N,start)=(4,4),(4,5),(4,MAX256) | Independently fuzz 0..MAX256; guarantee 0,1,MAX256 for the same N,start | BurnerLoansLens_InvalidStart(start,N) | Nonempty population rejects invalid start before any work, regardless of count | Same exact error; actor=C, no prank | Covered: [test_givenNonemptyPopulation_whenStartIsOutOfRange_reverts][test_givenNonemptyPopulation_whenStartIsOutOfRange_reverts]; [test_givenEqualCount_whenInvalidStartSeeded_reverts][test_givenEqualCount_whenInvalidStartSeeded_reverts]; [test_givenAboveCount_whenInvalidStartSeeded_reverts][test_givenAboveCount_whenInvalidStartSeeded_reverts]; [test_givenMaximumStart_whenInvalidStartSeeded_reverts][test_givenMaximumStart_whenInvalidStartSeeded_reverts]; [test_givenMaximumPopulation_whenInvalidStartSeeded_reverts][test_givenMaximumPopulation_whenInvalidStartSeeded_reverts]; [test_givenOneBorrower_whenInvalidStartSeeded_reverts][test_givenOneBorrower_whenInvalidStartSeeded_reverts] |
| BLLENS-SEIZABLE-I04 | Fuzz all callers | 0 | Fuzz 1..MAX256; seed 1,MAX256 | Independently fuzz 0..MAX256; guarantee 0,1,MAX256 for the same start | BurnerLoansLens_InvalidStart(start,0) | Empty market rejects invalid start before any work, regardless of count | Same exact error; actor=C, no prank | Covered: [test_givenEmptyPopulation_whenStartIsNonzero_reverts][test_givenEmptyPopulation_whenStartIsNonzero_reverts]; [test_givenEmptyPopulation_whenOneStartSeeded_reverts][test_givenEmptyPopulation_whenOneStartSeeded_reverts]; [test_givenEmptyPopulation_whenMaximumStartSeeded_reverts][test_givenEmptyPopulation_whenMaximumStartSeeded_reverts] |

## Empty and zero-work scans

Keep these separate from price failures. Configure snapshot, withdrawal-preview and reward calls to reject if reached.

| ID | Caller | N | start | count | Returned borrowers; cursor; reward | Dependency reads | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-P03 | Fuzz all callers | 0 | 0 | Fuzz 0..MAX256; seed 0,1,MAX256 | []; 0; 0 | Only canonical market/count reads; no snapshot/reward/withdrawal preview | Same exact tuple; actor=C, no prank | Covered: [test_givenEmptyMarket_whenQueried][test_givenEmptyMarket_whenQueried]; [test_givenEmptyMarket_whenCount0Seeded][test_givenEmptyMarket_whenCount0Seeded]; [test_givenEmptyMarket_whenCount1Seeded][test_givenEmptyMarket_whenCount1Seeded]; [test_givenEmptyMarket_whenCountMaximumSeeded][test_givenEmptyMarket_whenCountMaximumSeeded] |
| BLLENS-SEIZABLE-N02 | Fuzz all callers | Fuzz 1..MAX256; seed 1,4,MAX256 | Independently fuzz 0..N-1; seed 0,N-1 | 0 | []; start; 0 | Mock canonical count; no borrower-index/snapshot/reward/withdrawal-preview read | Same exact tuple; actor=C, no prank | Covered: [test_givenZeroCount_whenStartIsValid][test_givenZeroCount_whenStartIsValid]; [test_givenZeroCount_whenFirstOfOneSeeded][test_givenZeroCount_whenFirstOfOneSeeded]; [test_givenZeroCount_whenLastOfFourSeeded][test_givenZeroCount_whenLastOfFourSeeded]; [test_givenZeroCount_whenLastOfMaximumSeeded][test_givenZeroCount_whenLastOfMaximumSeeded] |

## Fixed pagination and eligibility cases

Canonical ordered fixture: index0 Alice (expired debt10e9,collateral100e6), index1 Bob (healthy debt20e9), index2 Carol (unexpired unhealthy debt30e9,collateral300e6), index3 Dave (healthy debt40e9). Prices are valid. Use a controlled Risk for health and reward handoff; check exact candidates visited and use one shared snapshot. Pagination values and expected arrays are hard-coded.

| ID | Caller | N | start | count | Returned borrowers | Next cursor | Selected debt; collateral | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-N04 | Fuzz all callers | 4 | 0 | 1 | [Alice] | 1 | 10e9;100e6 | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenFirstBorrowerScanned][test_givenCanonicalList_whenFirstBorrowerScanned] |
| BLLENS-SEIZABLE-N05 | Fuzz all callers | 4 | 0 | 2 | [Alice] | 2 | 10e9;100e6; healthy Bob still consumes scan budget | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenHealthyConsumesBudgetScanned][test_givenCanonicalList_whenHealthyConsumesBudgetScanned] |
| BLLENS-SEIZABLE-N06 | Fuzz all callers | 4 | 0 | 3 | [Alice,Carol] | 3 | 40e9;400e6 | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenFirstThreeScanned][test_givenCanonicalList_whenFirstThreeScanned] |
| BLLENS-SEIZABLE-N03 | Fuzz all callers | 4 | 0 | Fuzz 4..MAX256; guarantee 4,5,MAX256 | [Alice,Carol]; scan exactly four entries | 0 | 40e9;400e6; allocate at most four slots | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenExactPopulationCountScanned][test_givenCanonicalList_whenExactPopulationCountScanned]; [test_givenCanonicalList_whenAbovePopulationCountScanned][test_givenCanonicalList_whenAbovePopulationCountScanned]; [test_givenCanonicalList_whenMaximumPopulationCountScanned][test_givenCanonicalList_whenMaximumPopulationCountScanned]; [test_givenCanonicalList_whenLargeCountFuzzed][test_givenCanonicalList_whenLargeCountFuzzed] |
| BLLENS-SEIZABLE-N07 | Fuzz all callers | 4 | 2 | 2 | [Carol]; scan Carol,Dave | 0 | 30e9;300e6 | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenFinalTwoScanned][test_givenCanonicalList_whenFinalTwoScanned] |
| BLLENS-SEIZABLE-N08 | Fuzz all callers | 4 | 3 | 3 | []; scan Dave only, since he is healthy | 0 | 0;0; reward0 | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenHealthyFinalBorrowerScanned][test_givenCanonicalList_whenHealthyFinalBorrowerScanned] |
| BLLENS-SEIZABLE-N12 | Fuzz all callers | 4 | 3 | 1 | []; only healthy Dave examined | 0 | 0;0; start may exceed requested count | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenStartExceedsCountScanned][test_givenCanonicalList_whenStartExceedsCountScanned] |
| BLLENS-SEIZABLE-N11 | Fuzz all callers | 4 | 1 | MAX256 | [Carol]; scan Bob,Carol,Dave only | 0 | 30e9;300e6; clamp count to remaining three | Same exact tuple; actor=C, no prank | Covered: [test_givenCanonicalList_whenMaximumSuffixCountScanned][test_givenCanonicalList_whenMaximumSuffixCountScanned] |

## Population transitions and unrestricted results

Each fixture isolates one behavior; no ordering promise survives independent FLOAN swap-and-pop mutations between calls.

| ID | Caller | Population / transition | Execution / return | Effects / handoff | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-P04 | Fuzz all callers | N=51, all expired; each debt1e9 and collateral10e6; start=0,count=51 | All 51 unique borrowers; cursor0; no wrapping | No InvalidBatch from Lens; one aggregate reward quote | Same exact tuple; actor=C, no prank | Covered: [test_givenFiftyOneExpiredBorrowers_whenScanned][test_givenFiftyOneExpiredBorrowers_whenScanned] |
| BLLENS-SEIZABLE-P05 | Fuzz all callers | N=1 healthy; start=0,count=1 | [];cursor0;reward0 | No withdrawal preview or keeperReward call | Same exact tuple; actor=C, no prank | Covered: [test_givenOneHealthyBorrower_whenScanned][test_givenOneHealthyBorrower_whenScanned] |
| BLLENS-SEIZABLE-P06 | Fuzz all callers | N=1 expired; start=0,count=1; Risk returns reward0 | One borrower;cursor0;reward0 | Zero reward does not suppress eligible borrower | Same exact tuple; actor=C, no prank | Covered: [test_givenOneExpiredBorrower_whenRewardIsZero][test_givenOneExpiredBorrower_whenRewardIsZero] |
| BLLENS-SEIZABLE-P07 | Fuzz all callers | Canonical borrower fixture contains stale zero-debt candidate | Exclude it; consume its scanned slot | No debt-free reward or collateral contribution | Same exact tuple; actor=C, no prank | Covered: [test_givenStaleZeroDebtCandidate_whenScanned][test_givenStaleZeroDebtCandidate_whenScanned] |
| BLLENS-SEIZABLE-P08 | Fuzz all callers | First page start0,count2 returns cursor2; repay Alice, making N=3 and ordered list Dave,Bob,Carol; query start2,count2 | [Carol]; cursor0; only final entry scanned | No stale cached array or wrap to Dave/Bob | Same exact tuple; actor=C, no prank | Covered: [test_givenBorrowerRepaid_whenFinalPageScanned][test_givenBorrowerRepaid_whenFinalPageScanned] |
| BLLENS-SEIZABLE-P17 | Fuzz all callers | First page start0,count3 returns cursor3; repay Alice, reducing N from4 to3; query saved start3,count1 | BurnerLoansLens_InvalidStart(3,3) | No stale cursor normalization; no pricing | Same exact error; actor=C, no prank | Covered: [test_givenBorrowerRepaid_whenSavedCursorIsInvalid_reverts][test_givenBorrowerRepaid_whenSavedCursorIsInvalid_reverts] |
| BLLENS-SEIZABLE-P18 | Fuzz all callers | After the invalid-cursor rejection, caller retries with start0,count3 on Dave,Bob,Carol | [Carol]; cursor0 | Eligible remaining borrower is reachable after explicit reset | Same exact tuple; actor=C, no prank | Covered: [test_givenRejectedSavedCursor_whenCallerResets][test_givenRejectedSavedCursor_whenCallerResets] |
| BLLENS-SEIZABLE-P09 | Fuzz all callers | Same borrower has debt in another asset market | Only selected market canonical position is evaluated | No cross-market debt/collateral contamination | Same exact tuple; actor=C, no prank | Covered: [test_givenBorrowerInOtherMarket_whenScanned][test_givenBorrowerInOtherMarket_whenScanned] |

## Reward actor and custody handoff

Use start=0,count=4 in the canonical fixture: Alice and Carol contribute debt40e9 and collateral400e6. Mock withdrawal preview to return independently chosen output O and Risk.keeperReward to return R; assert exact snapshot, asset, debt, collateral, O and protocol flag. Real reward arithmetic belongs in Risk tests, not a copied Lens oracle.

| ID | Caller | Actor / output mode | Expected quote / calls | For consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-P01 | Fuzz caller outside HEART/SEIZER roles | Ordinary caller actor; direct custody O=77; mocked R=17 | protocol=false; return exactly17 | Same exact tuple; actor=C, no prank | Covered: [test_givenOrdinary_whenRewardQuoted][test_givenOrdinary_whenRewardQuoted] |
| BLLENS-SEIZABLE-P10 | HEART_ROLE holder | Caller is HEART actor; direct custody O=77 | protocol=true; real Risk reward0; eligible borrowers retained | Same exact tuple; actor=C, no prank | Covered: [test_givenHeart_whenRewardQuoted][test_givenHeart_whenRewardQuoted] |
| BLLENS-SEIZABLE-P11 | BURNER_LOANS_SEIZER_ROLE holder | Caller is SEIZER actor; direct custody O=77 | protocol=true; reward0; eligible borrowers retained | Same exact tuple; actor=C, no prank | Covered: [test_givenSeizer_whenRewardQuoted][test_givenSeizer_whenRewardQuoted] |
| BLLENS-SEIZABLE-P12 | Caller holding both protocol roles | Caller is reward actor | protocol=true; no doubled allocation | Same exact tuple; actor=C, no prank | Covered: [test_givenBothRoles_whenRewardQuoted][test_givenBothRoles_whenRewardQuoted] |
| BLLENS-SEIZABLE-P13 | Fuzz caller outside HEART/SEIZER roles | Ordinary caller actor; vault underlying withdrawal O=41; mocked R=13 | Use underlying output41, not nominal collateral or shares; return13 | Same exact tuple; actor=C, no prank | Covered: [test_givenUnderlying_whenRewardQuoted][test_givenUnderlying_whenRewardQuoted] |
| BLLENS-SEIZABLE-P14 | Fuzz caller outside HEART/SEIZER roles | Ordinary caller actor; withdrawAsShares=true; O=7 shares; mocked R=2 | Use share output7; quote2 raw share units | Same exact tuple; actor=C, no prank | Covered: [test_givenShares_whenRewardQuoted][test_givenShares_whenRewardQuoted] |
| BLLENS-SEIZABLE-P15 | Fuzz caller outside HEART/SEIZER roles | Ordinary caller actor; direct output77; mocked reward1 | Return one raw unit exactly | Same exact tuple; actor=C, no prank | Covered: [test_givenOneUnitReward_whenRewardQuoted][test_givenOneUnitReward_whenRewardQuoted] |
| BLLENS-SEIZABLE-P16 | Fuzz caller outside HEART/SEIZER roles | Ordinary caller actor; direct output77; mocked reward0 | Return0; keep all eligible borrowers | Same exact tuple; actor=C, no prank | Covered: [test_givenZeroReward_whenRewardQuoted][test_givenZeroReward_whenRewardQuoted] |

## Reward actor independent of the For caller

The paired HEART row above already tests an ordinary unpranked test contract querying for a HEART actor. These rows isolate the opposite role partition and the zero identity. Keep the same paired-call pattern, rather than a separate For suite.

| ID | Convenience caller C | Unpranked For caller | For actor | Expected classification | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-A02 | Ordinary caller without protocol roles | Test contract holds HEART_ROLE | C | protocol=false for both calls; test contract role is not forwarded | Same exact tuple; actor=C, no prank | Covered: [test_givenTestContractHasHeartRole_whenOrdinaryActorQuoted][test_givenTestContractHasHeartRole_whenOrdinaryActorQuoted] |
| BLLENS-SEIZABLE-A03 | Zero address without protocol roles, using vm.prank(0) only for convenience call | Ordinary test contract | Zero address | Ordinary classification for both; no ZeroAddress rejection | Same exact tuple; actor=C, no prank | Covered: [test_whenZeroActorQuoted][test_whenZeroActorQuoted] |

## Dependency failures

All unvaried dependencies work. Nonempty scans currently obtain a snapshot before checking candidate expiry; keep that failure ordering rather than promising price-free bulk scans.

| ID | Caller | Failing dependency read | Execution | Effects | For consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-SEIZABLE-P02 | Fuzz all callers | Risk.snapshot rejects with SnapshotReadFailed() | Exact SnapshotReadFailed(), including expired-only nonempty scan | No writes | Same exact error; actor=C, no prank | Covered: [test_givenSnapshotFailure_whenScanned_reverts][test_givenSnapshotFailure_whenScanned_reverts]; [test_givenExpiredOnlyList_whenSnapshotFails_reverts][test_givenExpiredOnlyList_whenSnapshotFails_reverts] |
| BLLENS-SEIZABLE-T01 | Fuzz all callers | Eligible selection; DM withdrawal preview rejects with WithdrawalPreviewFailed() | Exact WithdrawalPreviewFailed() | No writes | Same exact error; actor=C, no prank | Covered: [test_givenWithdrawalFailure_whenScanned_reverts][test_givenWithdrawalFailure_whenScanned_reverts] |
| BLLENS-SEIZABLE-T02 | Fuzz all callers | Eligible selection; Risk.keeperReward rejects with RewardQuoteFailed() | Exact RewardQuoteFailed() | No writes | Same exact error; actor=C, no prank | Covered: [test_givenRewardFailure_whenScanned_reverts][test_givenRewardFailure_whenScanned_reverts] |
| BLLENS-SEIZABLE-T03 | Fuzz all callers | Unexpired candidate; Risk.health rejects with RiskHealthFailed() | Exact RiskHealthFailed() | No writes | Same exact error; actor=C, no prank | Covered: [test_givenHealthFailure_whenScanned_reverts][test_givenHealthFailure_whenScanned_reverts] |

Legacy scans had separate check/return limits and circular traversal. Their eligibility and zero-work assertions inform these cases; the agreed forward-only pagination deliberately changes their wrap expectations. No legacy test is a Covered mapping by itself.

- [x] Review these expectations.
- [x] Implement focused tests and update Test mappings.

[test_givenAboveCount_whenInvalidStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L133
[test_givenActiveDisabledCore_whenQueried]: ./getSeizableBorrowers.t.sol#L34
[test_givenActiveEnabledCore_whenQueried]: ./getSeizableBorrowers.t.sol#L25
[test_givenBorrowerInOtherMarket_whenScanned]: ./getSeizableBorrowersIntegration.t.sol#L71
[test_givenBorrowerRepaid_whenFinalPageScanned]: ./getSeizableBorrowersIntegration.t.sol#L23
[test_givenBorrowerRepaid_whenSavedCursorIsInvalid_reverts]: ./getSeizableBorrowersIntegration.t.sol#L32
[test_givenBothRoles_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L550
[test_givenCanonicalList_whenAbovePopulationCountScanned]: ./getSeizableBorrowers.t.sol#L342
[test_givenCanonicalList_whenExactPopulationCountScanned]: ./getSeizableBorrowers.t.sol#L333
[test_givenCanonicalList_whenFinalTwoScanned]: ./getSeizableBorrowers.t.sol#L279
[test_givenCanonicalList_whenFirstBorrowerScanned]: ./getSeizableBorrowers.t.sol#L252
[test_givenCanonicalList_whenFirstThreeScanned]: ./getSeizableBorrowers.t.sol#L270
[test_givenCanonicalList_whenHealthyConsumesBudgetScanned]: ./getSeizableBorrowers.t.sol#L261
[test_givenCanonicalList_whenHealthyFinalBorrowerScanned]: ./getSeizableBorrowers.t.sol#L288
[test_givenCanonicalList_whenLargeCountFuzzed]: ./getSeizableBorrowers.t.sol#L360
[test_givenCanonicalList_whenMaximumPopulationCountScanned]: ./getSeizableBorrowers.t.sol#L351
[test_givenCanonicalList_whenMaximumSuffixCountScanned]: ./getSeizableBorrowers.t.sol#L324
[test_givenCanonicalList_whenStartExceedsCountScanned]: ./getSeizableBorrowers.t.sol#L306
[test_givenEmptyMarket_whenCount0Seeded]: ./getSeizableBorrowers.t.sol#L198
[test_givenEmptyMarket_whenCount1Seeded]: ./getSeizableBorrowers.t.sol#L204
[test_givenEmptyMarket_whenCountMaximumSeeded]: ./getSeizableBorrowers.t.sol#L210
[test_givenEmptyMarket_whenQueried]: ./getSeizableBorrowers.t.sol#L192
[test_givenEmptyPopulation_whenMaximumStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L186
[test_givenEmptyPopulation_whenOneStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L180
[test_givenEmptyPopulation_whenStartIsNonzero_reverts]: ./getSeizableBorrowers.t.sol#L161
[test_givenEqualCount_whenInvalidStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L126
[test_givenExpiredOnlyList_whenSnapshotFails_reverts]: ./getSeizableBorrowers.t.sol#L671
[test_givenFiftyOneExpiredBorrowers_whenScanned]: ./getSeizableBorrowers.t.sol#L370
[test_givenHealthFailure_whenScanned_reverts]: ./getSeizableBorrowers.t.sol#L650
[test_givenHeart_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L504
[test_givenInactiveDisabledCore_whenQueried]: ./getSeizableBorrowers.t.sol#L52
[test_givenInactiveEnabledCore_whenQueried]: ./getSeizableBorrowers.t.sol#L43
[test_givenMaximumPopulation_whenInvalidStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L147
[test_givenMaximumStart_whenInvalidStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L140
[test_givenNonemptyPopulation_whenStartIsOutOfRange_reverts]: ./getSeizableBorrowers.t.sol#L100
[test_givenOneBorrower_whenInvalidStartSeeded_reverts]: ./getSeizableBorrowers.t.sol#L154
[test_givenOneExpiredBorrower_whenRewardIsZero]: ./getSeizableBorrowers.t.sol#L494
[test_givenOneHealthyBorrower_whenScanned]: ./getSeizableBorrowers.t.sol#L384
[test_givenOneUnitReward_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L478
[test_givenOrdinary_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L411
[test_givenRejectedSavedCursor_whenCallerResets]: ./getSeizableBorrowersIntegration.t.sol#L52
[test_givenRewardFailure_whenScanned_reverts]: ./getSeizableBorrowers.t.sol#L632
[test_givenSeizer_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L527
[test_givenShares_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L436
[test_givenSnapshotFailure_whenScanned_reverts]: ./getSeizableBorrowers.t.sol#L591
[test_givenStaleZeroDebtCandidate_whenScanned]: ./getSeizableBorrowers.t.sol#L402
[test_givenTestContractHasHeartRole_whenOrdinaryActorQuoted]: ./getSeizableBorrowers.t.sol#L574
[test_givenUnderlying_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L419
[test_givenWithdrawalFailure_whenScanned_reverts]: ./getSeizableBorrowers.t.sol#L609
[test_givenZeroCount_whenFirstOfOneSeeded]: ./getSeizableBorrowers.t.sol#L231
[test_givenZeroCount_whenLastOfFourSeeded]: ./getSeizableBorrowers.t.sol#L238
[test_givenZeroCount_whenLastOfMaximumSeeded]: ./getSeizableBorrowers.t.sol#L245
[test_givenZeroCount_whenStartIsValid]: ./getSeizableBorrowers.t.sol#L216
[test_givenZeroReward_whenRewardQuoted]: ./getSeizableBorrowers.t.sol#L486
[test_whenUnknownAsset_revertsBeforeBounds]: ./getSeizableBorrowers.t.sol#L61
[test_whenZeroActorQuoted]: ./getSeizableBorrowers.t.sol#L584
[test_whenZeroAsset_reverts]: ./getSeizableBorrowers.t.sol#L86
