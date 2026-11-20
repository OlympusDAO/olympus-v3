# BurnerLoansLens.getActiveBorrowers coverage plan

Source: [getActiveBorrowers](../../../policies/burnerloans/BurnerLoansLens.sol#L74).

## Domains and notation

Scenario scope: `BLLENS-BORROWERS`. Lens remains a plain helper, without Kernel membership or IEnabler; SeizerTask owns operational control. Core is its immutable read dependency. All queries are read-only and emit no events. `MAXn=2**n-1`.

Active means at least one outstanding debt position in the selected FLOAN market; collateral alone does not qualify. Array order is not promised. Assert the unique borrower set and array length, and independently check the co-located `assetActiveDebtOhm(asset)` result. Principal amounts below use 9-decimal OHM.

## Core lifecycle independence

Core activity and local enablement do not gate these read-only queries. Read dependencies otherwise work; fuzz the caller. Lens itself has neither state.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-BORROWERS-L01 | Fuzz all callers | true | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveEnabledCore_whenQueried][test_givenActiveEnabledCore_whenQueried] |
| BLLENS-BORROWERS-L02 | Fuzz all callers | true | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveDisabledCore_whenQueried][test_givenActiveDisabledCore_whenQueried] |
| BLLENS-BORROWERS-L03 | Fuzz all callers | false | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveEnabledCore_whenQueried][test_givenInactiveEnabledCore_whenQueried] |
| BLLENS-BORROWERS-L04 | Fuzz all callers | false | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveDisabledCore_whenQueried][test_givenInactiveDisabledCore_whenQueried] |

## Invalid inputs

Other dependencies work. Test each query independently.

| ID | Caller | Asset | Execution for both getters | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-BORROWERS-I01 | Fuzz all callers | Nonzero unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No writes | Covered: [test_whenUnknownAsset_reverts][test_whenUnknownAsset_reverts] |
| BLLENS-BORROWERS-I02 | Fuzz all callers | Zero address, unregistered | BurnerLoansCore_AssetNotConfigured(0) | No writes | Covered: [test_whenZeroAsset_reverts][test_whenZeroAsset_reverts] |

## Borrower membership and debt transitions

Alice, Bob and Carol are distinct borrowers. Every transition below is a separate fixture. Read authoritative FLOAN membership and market principal; do not calculate totals from Lens itself.

| ID | Caller | Selected market state / transition | Returned set; length | assetActiveDebtOhm | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-BORROWERS-P01 | Fuzz all callers | Registered market without positions | {}; 0 | 0 | Covered: [test_givenEmptyMarket_whenQueried][test_givenEmptyMarket_whenQueried] |
| BLLENS-BORROWERS-P04 | Fuzz all callers | Alice has collateral only | {}; 0 | 0 | Covered: [test_givenCollateralOnly_whenQueried][test_givenCollateralOnly_whenQueried] |
| BLLENS-BORROWERS-P05 | Fuzz all callers | Alice owes 100e9 | {Alice}; 1 | 100e9 | Covered: [test_givenSingleDebt_whenQueried][test_givenSingleDebt_whenQueried] |
| BLLENS-BORROWERS-P06 | Fuzz all callers | Alice owes 100e9; Bob owes 200e9 | {Alice,Bob}; 2 | 300e9 | Covered: [test_givenTwoBorrowers_whenQueried][test_givenTwoBorrowers_whenQueried] |
| BLLENS-BORROWERS-P07 | Fuzz all callers | Alice owes 100e9 then borrows another 50e9 | {Alice}; 1 | 150e9; no duplicate membership | Covered: [test_givenRepeatedBorrow_whenQueried][test_givenRepeatedBorrow_whenQueried] |
| BLLENS-BORROWERS-P08 | Fuzz all callers | Alice repays 40e9 of 100e9 | {Alice}; 1 | 60e9 | Covered: [test_givenPartialRepayment_whenQueried][test_givenPartialRepayment_whenQueried] |
| BLLENS-BORROWERS-P09 | Fuzz all callers | Alice/Bob/Carol owe 100e9/200e9/300e9; repay Alice completely | {Bob,Carol}; 2; no stale Alice after swap-and-pop | 500e9 | Covered: [test_givenFullRepayment_whenQueried][test_givenFullRepayment_whenQueried] |
| BLLENS-BORROWERS-P10 | Fuzz all callers | Alice/Bob/Carol owe 100e9/200e9/300e9; default Bob completely | {Alice,Carol}; 2; no stale Bob after swap-and-pop | 400e9 | Covered: [test_givenDefault_whenQueried][test_givenDefault_whenQueried] |
| BLLENS-BORROWERS-P11 | Fuzz all callers | Alice fully repays then starts a new 70e9 debt episode | {Alice}; 1 | 70e9; closed episode contributes zero | Covered: [test_givenReopenedDebt_whenQueried][test_givenReopenedDebt_whenQueried] |
| BLLENS-BORROWERS-P03 | Fuzz all callers | Asset X: Alice owes 100e9; asset Y: Bob owes 200e9; query X | {Alice}; 1 | 100e9; other market excluded | Covered: [test_givenDifferentBorrowerInOtherMarket_whenQueried][test_givenDifferentBorrowerInOtherMarket_whenQueried] |
| BLLENS-BORROWERS-P12 | Fuzz all callers | Asset X: Alice owes 100e9; same Alice owes 500e9 against Y; query X | {Alice}; 1 | 100e9; borrower identity does not merge markets | Covered: [test_givenSameBorrowerInOtherMarket_whenQueried][test_givenSameBorrowerInOtherMarket_whenQueried] |
| BLLENS-BORROWERS-P13 | Fuzz all callers | Controlled FLOAN fixture: Alice has two debt positions of 50e9 and 70e9 in selected market | {Alice}; 1 | 120e9; aggregate includes both positions | Covered: [test_givenTwoPositions_whenQueried][test_givenTwoPositions_whenQueried] |
| BLLENS-BORROWERS-P14 | Fuzz all callers | Same two-position FLOAN fixture; close only the 50e9 position | {Alice}; 1 | 70e9; membership remains until last debt closes | Covered: [test_givenTwoPositionsOneClosed_whenQueried][test_givenTwoPositionsOneClosed_whenQueried] |

## Dependency failures

Each fault is isolated with valid asset registration.

| ID | Caller | Failing read | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-BORROWERS-T01 | Fuzz all callers | FLOAN.getActiveBorrowers returns malformed dynamic-array ABI | Empty ABI-decode revert; mock supplies no typed error | No writes | Covered: [test_givenMalformedBorrowerArray_whenQueried_reverts][test_givenMalformedBorrowerArray_whenQueried_reverts] |
| BLLENS-BORROWERS-T02 | Fuzz all callers | FLOAN.getActiveBorrowers reverts with controlled FloanReadFailed() | Exact FloanReadFailed() | No writes | Covered: [test_givenBorrowerReadFailure_whenQueried_reverts][test_givenBorrowerReadFailure_whenQueried_reverts] |
| BLLENS-BORROWERS-T03 | Fuzz all callers | FLOAN.getMarketPrincipalDue reverts with controlled FloanReadFailed() | assetActiveDebtOhm bubbles exact error | No writes | Covered: [test_givenPrincipalReadFailure_whenQueried_reverts][test_givenPrincipalReadFailure_whenQueried_reverts] |

- [x] Review the scenarios.
- [x] Implement focused tests and update Test mappings.

[test_givenActiveDisabledCore_whenQueried]: ./getActiveBorrowers.t.sol#L27
[test_givenActiveEnabledCore_whenQueried]: ./getActiveBorrowers.t.sol#L21
[test_givenBorrowerReadFailure_whenQueried_reverts]: ./getActiveBorrowers.t.sol#L195
[test_givenCollateralOnly_whenQueried]: ./getActiveBorrowers.t.sol#L80
[test_givenDefault_whenQueried]: ./getActiveBorrowers.t.sol#L124
[test_givenDifferentBorrowerInOtherMarket_whenQueried]: ./getActiveBorrowers.t.sol#L142
[test_givenEmptyMarket_whenQueried]: ./getActiveBorrowers.t.sol#L75
[test_givenFullRepayment_whenQueried]: ./getActiveBorrowers.t.sol#L115
[test_givenInactiveDisabledCore_whenQueried]: ./getActiveBorrowers.t.sol#L39
[test_givenInactiveEnabledCore_whenQueried]: ./getActiveBorrowers.t.sol#L33
[test_givenMalformedBorrowerArray_whenQueried_reverts]: ./getActiveBorrowers.t.sol#L182
[test_givenPartialRepayment_whenQueried]: ./getActiveBorrowers.t.sol#L108
[test_givenPrincipalReadFailure_whenQueried_reverts]: ./getActiveBorrowers.t.sol#L207
[test_givenReopenedDebt_whenQueried]: ./getActiveBorrowers.t.sol#L133
[test_givenRepeatedBorrow_whenQueried]: ./getActiveBorrowers.t.sol#L100
[test_givenSameBorrowerInOtherMarket_whenQueried]: ./getActiveBorrowers.t.sol#L149
[test_givenSingleDebt_whenQueried]: ./getActiveBorrowers.t.sol#L87
[test_givenTwoBorrowers_whenQueried]: ./getActiveBorrowers.t.sol#L93
[test_givenTwoPositionsOneClosed_whenQueried]: ./getActiveBorrowers.t.sol#L169
[test_givenTwoPositions_whenQueried]: ./getActiveBorrowers.t.sol#L156
[test_whenUnknownAsset_reverts]: ./getActiveBorrowers.t.sol#L45
[test_whenZeroAsset_reverts]: ./getActiveBorrowers.t.sol#L60
