# BurnerLoansCore.registerMarket coverage plan

Source: [registerMarket](../../../policies/burnerloans/BurnerLoansCore.sol#L716). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-MARKET` identifies this contract/function.

Only the exact selected Config address may register/synchronize a market. Core trusts Config's validated FLOAN setup; Config's activity, enablement, Kernel and interface do not enter Core admission. Core must be Kernel-active and locally enabled before caller admission or registry changes. Unchanged means registry, FLOAN, positions, tokens and logs unchanged. Core's nonReentrant guard precedes caller checks.

## Authorization

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-MARKET-A01 | Fuzz all callers excluding the selected configOperator; seed ADMIN without operator authority | Valid or invalid asset/market/mode | ConfigOperator_Unauthorized(caller) | Unchanged | Covered: [test][test_givenUnauthorized_whenRegistered_reverts], [test][test_givenAdminWithoutConfigOperatorAuthority_whenRegistered_reverts] |
| BLCORE-MARKET-A02 | Selected Config | Valid canonical market already configured in FLOAN | Success without Config state reads | Registry effects below | Covered: [test][test_givenNewAsset_whenRegistered] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-MARKET-L01 | Selected Config | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenNewAsset_whenRegistered] |
| BLCORE-MARKET-L02 | Selected Config | true | false | NotEnabled() before new registration, changed-mode updates or unchanged no-ops | Unchanged; no registry, module or event changes | Covered: [test][test_givenCoreDisabled_whenRegistered_reverts], [test][test_givenExistingAssetAndDisabledCore_whenModeUpdated_reverts] |
| BLCORE-MARKET-L03 | Selected Config | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenRegistered_reverts] |
| BLCORE-MARKET-L04 | Selected Config | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenRegistered_reverts] |

## Upstream Config independence

Core active and enabled. Use the selected Config address and valid market. No upstream linked-policy guard is used.

| ID | Caller | Config active | Config enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-MARKET-D01 | Selected Config | true | true | Success | Same registry update; no Config lifecycle calls | Covered: [test][test_givenConfigUnavailable_whenRegistered] |
| BLCORE-MARKET-D02 | Selected Config | true | false | Success | Same registry update; no Config lifecycle calls | Covered: [test][test_givenConfigUnavailable_whenRegistered] |
| BLCORE-MARKET-D03 | Selected Config | false | true | Success | Same registry update; no Config lifecycle calls | Covered: [test][test_givenConfigUnavailable_whenRegistered] |
| BLCORE-MARKET-D04 | Selected Config | false | false | Success | Same registry update; no Config lifecycle calls | Covered: [test][test_givenConfigUnavailable_whenRegistered] |

## Invalid inputs

| ID | Caller | Pre-state / input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-MARKET-I01 | Selected Config | Registered asset; proposed market differs from stored market | BurnerLoansCore_MarketMismatch(asset,storedMarket,proposedMarket) | Unchanged | Covered: [test][test_givenExistingAsset_whenMarketIdChanges_reverts] |

Core must be active and enabled for every registration or mode update, including unchanged inputs.

## Registration and configuration transitions

| ID | Caller | Asset state | Input domain | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-MARKET-P01 | Selected Config | Absent | Fuzz uint32 market 0..MAX32; seed 0,1,MAX32; shares false/true | Success | Register once; AssetRegistered; count/index/id/mode exact | Covered: [test][test_givenNewAsset_whenRegistered], [test][test_whenMarketIdBoundarySeeds] |
| BLCORE-MARKET-P02 | Selected Config | Registered | Same ID; changed mode | Success | Mode updates; no duplicate asset/index/event; no FLOAN write | Covered: [test][test_givenExistingAsset_whenModeUpdated] |
| BLCORE-MARKET-P03 | Selected Config | Registered | Same ID and mode | No-op (required) | No writes or events | Covered: [test][test_givenExistingAsset_whenModeUpdated] |

## Shared assertions

Integration through production Config proves facility/manager/schema pairing. Trusted direct Core tests establish that validation is not duplicated. Different market ID rejects before any registry update. Use the proposed Core-owned `BurnerLoansCore_MarketMismatch(address asset,uint32 storedMarket,uint32 proposedMarket)` error instead of the current generic settlement error. Config Kernel/identity correctness belongs to governance/Config installation, not a reverse Core check.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

[test_givenConfigUnavailable_whenRegistered]: registerMarket.t.sol#L78
[test_givenCoreDisabled_whenRegistered_reverts]: registerMarket.t.sol#L150
[test_givenCoreInactive_whenRegistered_reverts]: registerMarket.t.sol#L65
[test_givenExistingAssetAndDisabledCore_whenModeUpdated_reverts]: registerMarket.t.sol#L170
[test_givenExistingAsset_whenMarketIdChanges_reverts]: registerMarket.t.sol#L92
[test_givenExistingAsset_whenModeUpdated]: registerMarket.t.sol#L113
[test_givenNewAsset_whenRegistered]: registerMarket.t.sol#L40
[test_givenUnauthorized_whenRegistered_reverts]: registerMarket.t.sol#L19
[test_givenAdminWithoutConfigOperatorAuthority_whenRegistered_reverts]: registerMarket.t.sol#L34
[test_whenMarketIdBoundarySeeds]: registerMarket.t.sol#L54
