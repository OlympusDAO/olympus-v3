# BurnerLoansLens.getAssetCollateralStatus coverage plan

Source: [getAssetCollateralStatus](../../../policies/burnerloans/BurnerLoansLens.sol#L127).

## Domains and notation

Scenario scope: `BLLENS-COLLATERAL-STATUS`. Lens remains a plain helper, without Kernel membership or IEnabler; SeizerTask owns operational control. Core is its immutable read dependency. All queries are read-only and emit no events. `MAXn=2**n-1`.

Reads DepositManager (DM) under operator=Core, never under Lens or the external caller. Result fields are shares S, held assets A, borrowed coverage B, liabilities L, solvent and claimableYield Y. Custody examples use raw asset units. Deposit periods must be configured but may be disabled. Unit fixtures stub DM ledger/yield reads independently; real-DM integrations prove mode conversion and yield behavior.

## Core lifecycle independence

Core activity and local enablement do not gate these read-only queries. Read dependencies otherwise work; fuzz the caller. Lens itself has neither state.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-L03 | Fuzz all callers | true | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveEnabledCore_whenStatusRead][test_givenActiveEnabledCore_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-L04 | Fuzz all callers | true | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveDisabledCore_whenStatusRead][test_givenActiveDisabledCore_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-L05 | Fuzz all callers | false | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveEnabledCore_whenStatusRead][test_givenInactiveEnabledCore_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-L06 | Fuzz all callers | false | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveDisabledCore_whenStatusRead][test_givenInactiveDisabledCore_whenStatusRead] |

## Invalid asset inputs

DM is operational; no price lookup is needed.

| ID | Caller | Asset | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-I01 | Fuzz all callers | Nonzero unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No DM read or write | Covered: [test_whenUnknownAsset_reverts][test_whenUnknownAsset_reverts] |
| BLLENS-COLLATERAL-STATUS-I02 | Fuzz all callers | Zero asset, unregistered | BurnerLoansCore_AssetNotConfigured(0) | No DM read or write | Covered: [test_whenZeroAsset_reverts][test_whenZeroAsset_reverts] |

## DepositManager readiness and period state

Asset is registered on Core. Each failure varies one DM condition.

| ID | Caller | DM / period condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-L01 | Fuzz all callers | DM locally disabled | BurnerLoansCore_InvalidDepositManager(DM) | No writes | Covered: [test_givenDisabledCustody_whenStatusRead_reverts][test_givenDisabledCustody_whenStatusRead_reverts] |
| BLLENS-COLLATERAL-STATUS-D01 | Fuzz all callers | DM enabled; asset configuration absent | BurnerLoansCore_InvalidDepositManager(DM) | No writes | Covered: [test_givenUnconfiguredAsset_whenStatusRead_reverts][test_givenUnconfiguredAsset_whenStatusRead_reverts] |
| BLLENS-COLLATERAL-STATUS-D02 | Fuzz all callers | DM asset configured; Core deposit period absent | BurnerLoansCore_InvalidDepositManager(DM) | No writes | Covered: [test_givenMissingPeriod_whenStatusRead_reverts][test_givenMissingPeriod_whenStatusRead_reverts] |
| BLLENS-COLLATERAL-STATUS-L02 | Fuzz all callers | DM enabled; Core period configured but disabled | Same exact status as corresponding period-enabled fixture | Period flag does not prohibit status reads; no writes | Covered: [test_givenDisabledPeriod_whenStatusRead][test_givenDisabledPeriod_whenStatusRead] |

## Solvency boundaries

DM unit fixture returns the stated independent S/A/B/L/Y. Solvency uses A>=L or B>=L-A; the Lens must not form an overflowing A+B. For the small examples, S=A and Y=0 unless listed otherwise.

| ID | Caller | Held A | Borrowed B | Liabilities L | Expected solvent | Expected Y | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-P01 | Fuzz all callers | 100 | 0 | 100 | true; equality | 0 | Covered: [test_givenEquality_whenStatusRead][test_givenEquality_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P02 | Fuzz all callers | 99 | 0 | 100 | false; one raw unit short | 0 | Covered: [test_givenOneUnitDeficit_whenStatusRead][test_givenOneUnitDeficit_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P03 | Fuzz all callers | 101 | 0 | 100 | true; one raw unit surplus | 0; DM yield buffer retained | Covered: [test_givenOneUnitSurplus_whenStatusRead][test_givenOneUnitSurplus_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P04 | Fuzz all callers | 60 | 40 | 100 | true; borrowed coverage supplies the difference | 0 | Covered: [test_givenBorrowedEquality_whenStatusRead][test_givenBorrowedEquality_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P05 | Fuzz all callers | 60 | 39 | 100 | false; coverage one raw unit short | 0 | Covered: [test_givenBorrowedDeficit_whenStatusRead][test_givenBorrowedDeficit_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P06 | Fuzz all callers | 60 | 41 | 100 | true; coverage one raw unit above | 0 | Covered: [test_givenBorrowedSurplus_whenStatusRead][test_givenBorrowedSurplus_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P07 | Fuzz all callers | 0 | 0 | 0 | true; empty namespace | 0 | Covered: [test_givenEmptyNamespace_whenStatusRead][test_givenEmptyNamespace_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-N01 | Fuzz all callers | MAX256 | MAX256 | MAX256 | true; do not add A+B | Mock Y=0 independently; DM arithmetic tested in DM suite | Covered: [test_givenMaximumValues_whenStatusRead][test_givenMaximumValues_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-N02 | Fuzz all callers | MAX256-1 | 1 | MAX256 | true; compare against one-unit difference | Mock Y=0 independently | Covered: [test_givenMaximumEquality_whenStatusRead][test_givenMaximumEquality_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-N03 | Fuzz all callers | MAX256-1 | 0 | MAX256 | false; exact maximum-liability deficit | Mock Y=0 independently | Covered: [test_givenMaximumDeficit_whenStatusRead][test_givenMaximumDeficit_whenStatusRead] |

## Custody modes and operator isolation

Use the real DM where indicated; assert every status field. Different modes are separate fixtures.

| ID | Caller | Fixture | Expected status / handoff | Test |
| --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-P08 | Fuzz all callers | Direct payout; real DM holds 102, borrowed 0, liabilities 100 | S=102,A=102,B=0,L=100,solvent=true,Y=1; DM one-unit buffer | Covered: [test_givenRealDirectCustody_whenStatusRead][test_givenRealDirectCustody_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P09 | Fuzz all callers | Synchronous vault; 3 shares represent 4 assets after donation; liabilities 3 | S=3,A=4,B=0,L=3,solvent=true,Y=0; expose both share and asset units | Covered: [test_givenRealVaultDonation_whenStatusRead][test_givenRealVaultDonation_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P10 | Fuzz all callers | Supported asynchronous/share-required payout; DM reports S=7,A=14,B=0,L=10,Y=3 | Return exact six fields; no redemption or assumed share=asset conversion | Covered: [test_givenShareRequired_whenStatusRead][test_givenShareRequired_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P11 | Fuzz all callers | External-share payout; DM reports S=5,A=15,B=0,L=10,Y=4 | Return exact six fields; no redemption | Covered: [test_givenExternalShares_whenStatusRead][test_givenExternalShares_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P12 | Fuzz all callers | Core namespace has A=102,L=100; different operator has different shares/debt/liabilities | Only Core namespace S/A/B/L/Y returned; token-wide or other-operator totals excluded | Covered: [test_givenOtherOperator_whenStatusRead][test_givenOtherOperator_whenStatusRead] |
| BLLENS-COLLATERAL-STATUS-P13 | Fuzz all callers | Mock DM returns Y=MAX256 independently of other status fields | Forward Y unchanged; no narrowing or locally duplicated yield calculation | Covered: [test_givenMaximumYield_whenStatusRead][test_givenMaximumYield_whenStatusRead] |

## Dependency failures

Other reads work; controlled mocks give stable typed errors.

| ID | Caller | Failing read | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-COLLATERAL-STATUS-T01 | Fuzz all callers | DM.getOperatorAssets reverts with CustodyReadFailed() | Exact CustodyReadFailed() | No writes | Covered: [test_givenLedgerFailure_whenStatusRead_reverts][test_givenLedgerFailure_whenStatusRead_reverts] |
| BLLENS-COLLATERAL-STATUS-T02 | Fuzz all callers | DM.maxClaimYield reverts with YieldReadFailed() | Exact YieldReadFailed(); no partial tuple | No writes | Covered: [test_givenYieldFailure_whenStatusRead_reverts][test_givenYieldFailure_whenStatusRead_reverts] |

- [x] Review the scenarios.
- [x] Implement focused tests and update Test mappings.

[test_givenActiveDisabledCore_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L32
[test_givenActiveEnabledCore_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L25
[test_givenBorrowedDeficit_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L182
[test_givenBorrowedEquality_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L176
[test_givenBorrowedSurplus_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L188
[test_givenDisabledCustody_whenStatusRead_reverts]: ./getAssetCollateralStatus.t.sol#L89
[test_givenDisabledPeriod_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L142
[test_givenEmptyNamespace_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L194
[test_givenEquality_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L158
[test_givenExternalShares_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L264
[test_givenInactiveDisabledCore_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L46
[test_givenInactiveEnabledCore_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L39
[test_givenLedgerFailure_whenStatusRead_reverts]: ./getAssetCollateralStatus.t.sol#L308
[test_givenMaximumDeficit_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L228
[test_givenMaximumEquality_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L214
[test_givenMaximumValues_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L200
[test_givenMaximumYield_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L286
[test_givenMissingPeriod_whenStatusRead_reverts]: ./getAssetCollateralStatus.t.sol#L120
[test_givenOneUnitDeficit_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L164
[test_givenOneUnitSurplus_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L170
[test_givenOtherOperator_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L292
[test_givenRealDirectCustody_whenStatusRead]: ./getAssetCollateralStatusIntegration.t.sol#L27
[test_givenRealVaultDonation_whenStatusRead]: ./getAssetCollateralStatusIntegration.t.sol#L54
[test_givenShareRequired_whenStatusRead]: ./getAssetCollateralStatus.t.sol#L242
[test_givenUnconfiguredAsset_whenStatusRead_reverts]: ./getAssetCollateralStatus.t.sol#L102
[test_givenYieldFailure_whenStatusRead_reverts]: ./getAssetCollateralStatus.t.sol#L324
[test_whenUnknownAsset_reverts]: ./getAssetCollateralStatus.t.sol#L53
[test_whenZeroAsset_reverts]: ./getAssetCollateralStatus.t.sol#L71
