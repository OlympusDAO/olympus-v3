# BurnerLoansLens.isSeizable coverage plan

Source: [isSeizable](../../../policies/burnerloans/BurnerLoansLens.sol#L114).

## Domains and notation

Scenario scope: `BLLENS-IS-SEIZABLE`. Lens is a plain read-only helper without Kernel membership or IEnabler. SeizerTask owns operational control. Core is its immutable read dependency. All cases assert no writes or committed events. `MAXn=2**n-1`.

Permissionless canonical position query. Zero debt and expiry are separate short circuits. A debt-free/missing position is not seizable; a debt-bearing position is seizable at expiry equality or while unexpired with health below 1e18. Use mock Risk for the boolean boundary cases.

## Core lifecycle independence

Core flags do not gate the query; actual read dependencies work. Lens has no lifecycle flags.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-IS-SEIZABLE-L01 | Fuzz all callers | true | true | Same result as corresponding successful read | No writes or logs | Covered: [test_givenActiveEnabledCore_whenQueried][test_givenActiveEnabledCore_whenQueried] |
| BLLENS-IS-SEIZABLE-L02 | Fuzz all callers | true | false | Same result as corresponding successful read | No writes or logs | Covered: [test_givenActiveDisabledCore_whenQueried][test_givenActiveDisabledCore_whenQueried] |
| BLLENS-IS-SEIZABLE-L03 | Fuzz all callers | false | true | Same result as corresponding successful read | No writes or logs | Covered: [test_givenInactiveEnabledCore_whenQueried][test_givenInactiveEnabledCore_whenQueried] |
| BLLENS-IS-SEIZABLE-L04 | Fuzz all callers | false | false | Same result as corresponding successful read | No writes or logs | Covered: [test_givenInactiveDisabledCore_whenQueried][test_givenInactiveDisabledCore_whenQueried] |

## Invalid inputs

Risk and other services are usable; market lookup happens before absent-position handling.

| ID | Caller | Asset | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-IS-SEIZABLE-I01 | Fuzz all callers | Nonzero unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No writes | Covered: [test_whenUnknownAsset_reverts][test_whenUnknownAsset_reverts] |
| BLLENS-IS-SEIZABLE-I02 | Fuzz all callers | Zero unregistered asset | BurnerLoansCore_AssetNotConfigured(0) | No writes | Covered: [test_whenZeroAsset_reverts][test_whenZeroAsset_reverts] |

## Debt and expiry states

Expiry E is a fixed valid timestamp. Configure Risk.snapshot and health to reject if the branch should skip them.

| ID | Caller | Position / time | Expected result | Risk reads | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-IS-SEIZABLE-P01 | Fuzz all callers | Registered asset; no borrower position | false | None | Covered: [test_givenNoPosition_whenQueried][test_givenNoPosition_whenQueried] |
| BLLENS-IS-SEIZABLE-P06 | Fuzz all callers | Collateral-only position; principal0 | false | None | Covered: [test_givenCollateralOnly_whenQueried][test_givenCollateralOnly_whenQueried] |
| BLLENS-IS-SEIZABLE-P02 | Fuzz all callers | Principal100e9; now=E | true | None; expiry equality qualifies | Covered: [test_givenExactExpiry_whenQueried][test_givenExactExpiry_whenQueried] |
| BLLENS-IS-SEIZABLE-P07 | Fuzz all callers | Principal100e9; now=E+1 | true | None; invalid prices do not prevent expired classification | Covered: [test_givenPastExpiry_whenQueried][test_givenPastExpiry_whenQueried] |
| BLLENS-IS-SEIZABLE-P08 | Fuzz all callers | Principal100e9; now=E-1; mock H=2e18 | false | Current snapshot/health used before expiry | Covered: [test_givenBeforeExpiry_whenQueried][test_givenBeforeExpiry_whenQueried] |

## Fixed unexpired health boundaries

Principal100e9, now=E-1, valid snapshot. Only mock H varies; do not reproduce Risk math.

| ID | Caller | Mock H | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-IS-SEIZABLE-P03 | Fuzz all callers | 0 | true | No writes | Covered: [test_givenZeroHealth_whenQueried][test_givenZeroHealth_whenQueried] |
| BLLENS-IS-SEIZABLE-N01 | Fuzz all callers | 1e18-1 | true | No writes | Covered: [test_givenBelowOne_whenQueried][test_givenBelowOne_whenQueried] |
| BLLENS-IS-SEIZABLE-P04 | Fuzz all callers | 1e18 | false | No writes | Covered: [test_givenExactlyOne_whenQueried][test_givenExactlyOne_whenQueried] |
| BLLENS-IS-SEIZABLE-P05 | Fuzz all callers | 1e18+1 | false | No writes | Covered: [test_givenAboveOne_whenQueried][test_givenAboveOne_whenQueried] |
| BLLENS-IS-SEIZABLE-N02 | Fuzz all callers | MAX256 | false; no narrowing | No writes | Covered: [test_givenMaximumHealth_whenQueried][test_givenMaximumHealth_whenQueried] |

## Dependency failures

Positive, unexpired debt; other reads work.

| ID | Caller | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-IS-SEIZABLE-T01 | Fuzz all callers | Risk.snapshot reverts with SnapshotReadFailed() | Exact SnapshotReadFailed() | No writes | Covered: [test_givenSnapshotFailure_whenQueried_reverts][test_givenSnapshotFailure_whenQueried_reverts] |
| BLLENS-IS-SEIZABLE-T02 | Fuzz all callers | Snapshot valid; Risk.health reverts with RiskHealthFailed() | Exact RiskHealthFailed() | No writes | Covered: [test_givenHealthFailure_whenQueried_reverts][test_givenHealthFailure_whenQueried_reverts] |

The legacy boolean-query cases inform debt-free, exact-expiry and health-boundary assertions. No legacy test is a Covered mapping for the Lens API by itself.

- [x] Review these expectations.
- [x] Implement focused tests and update Test mappings.

[test_givenAboveOne_whenQueried]: ./isSeizable.t.sol#L131
[test_givenActiveDisabledCore_whenQueried]: ./isSeizable.t.sol#L27
[test_givenActiveEnabledCore_whenQueried]: ./isSeizable.t.sol#L20
[test_givenBeforeExpiry_whenQueried]: ./isSeizable.t.sol#L103
[test_givenBelowOne_whenQueried]: ./isSeizable.t.sol#L117
[test_givenCollateralOnly_whenQueried]: ./isSeizable.t.sol#L80
[test_givenExactExpiry_whenQueried]: ./isSeizable.t.sol#L87
[test_givenExactlyOne_whenQueried]: ./isSeizable.t.sol#L124
[test_givenHealthFailure_whenQueried_reverts]: ./isSeizable.t.sol#L159
[test_givenInactiveDisabledCore_whenQueried]: ./isSeizable.t.sol#L41
[test_givenInactiveEnabledCore_whenQueried]: ./isSeizable.t.sol#L34
[test_givenMaximumHealth_whenQueried]: ./isSeizable.t.sol#L138
[test_givenNoPosition_whenQueried]: ./isSeizable.t.sol#L74
[test_givenPastExpiry_whenQueried]: ./isSeizable.t.sol#L95
[test_givenSnapshotFailure_whenQueried_reverts]: ./isSeizable.t.sol#L145
[test_givenZeroHealth_whenQueried]: ./isSeizable.t.sol#L110
[test_whenUnknownAsset_reverts]: ./isSeizable.t.sol#L48
[test_whenZeroAsset_reverts]: ./isSeizable.t.sol#L61
