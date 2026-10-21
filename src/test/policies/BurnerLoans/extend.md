# extend revenue routing scenario plan

Only branch-added fee routing/defer behavior; existing maturity and risk cases remain in extend.t.sol.

BL must be Kernel-active before this action or its executable preview can proceed. All success/input/transfer rows assume BL active. Inactive rejection is tested with otherwise valid inputs and retained caller authorization, for each routing flag; disabled BL remains a separate case.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Use existing action-specific authorized callers, guards and previews; these plans assess only behavior introduced by this branch, not full parent-function coverage. Token amounts use native base units; preview debt uses 9-decimal OHM. `MAX` means `type(uint256).max` for maxFee and fee quantities. Newly introduced payout buckets are described in [transferPendingPayout](./transferPendingPayout.md).

BL state separates Kernel membership from local enablement. The asset/position state records originations, existing debt, maturity and eligibility because extend requires an enabled origination market and a live extendable position. `sendFeesToDistributor=false` selects the current Treasury; `true` selects the current nonzero Revenue Distributor. RD lifecycle and asset-listing state are not consulted by the direct fee transfer. Unless a row varies them, BL is Kernel-active and locally enabled, originations are enabled, and the position, prices, term count, maturity, health and authorization are valid.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Required previewExtend behavior is BL active/enabled; it does not enforce caller authorization or maxFee. Compare preview with action effects where executable; authoritative debt/custody/recipient balances and pending indexes are independent assertions. Fuzz only within reachable action domains; supplement with exact fee zero/one and semantic fee/rounding limits when they affect the new payout behavior.

## Lifecycle

| ID | Caller | BL Kernel | BL local | Asset originations/position | `sendFeesToDistributor` | Selected fee destination state | Fee/action state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-L01 | Position owner or authorized operator separately | Active | Enabled | Originations enabled; live eligible debt position | `true` | Current RD is Kernel-active but locally disabled | Valid positive-fee extension | extend succeeds; fee transfer does not invoke RD lifecycle guards | RD receives exact fee; BL debt/maturity and pending reserve correct | Covered: [destination-state and caller matrix][test_givenDistributorUnavailable_extensionStillPaysExactFee] |
| EXT-L05 | Position owner or authorized operator separately | Inactive after deactivation | Enabled | Originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or nonzero RD respectively | Valid positive-fee extension | BurnerLoans_PolicyInactive() in action and executable preview | Unchanged maturity, debt, fee reserve, allowance, custody and recipients; no collection, payout or events | Covered: [inactive action and preview][test_givenPolicyInactive_whenExtendIsPreviewedOrExecuted_reverts] |
| EXT-L02 | Position owner or authorized operator separately | Active | Enabled | Originations enabled; live eligible debt position | `true` | Current RD is Kernel-inactive but locally enabled | Valid positive-fee extension | extend succeeds; fee transfer does not invoke RD lifecycle guards | RD receives exact fee; BL debt/maturity and pending reserve correct | Covered: [destination-state and caller matrix][test_givenDistributorUnavailable_extensionStillPaysExactFee] |
| EXT-L03 | Position owner or authorized operator separately | Active | Enabled | Originations enabled; live eligible debt position | `true` | Current RD is active/enabled but fee token is NeverListed | Valid positive-fee extension | Extension succeeds | RD receives exact fee; maturity advances; no pending fee | Covered: [owner and operator][test_givenFeeTokenUnlistedByDistributor_extensionStillPaysDistributor] |
| EXT-L04 | Position owner or authorized operator separately | Active | Disabled | Originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or nonzero RD respectively | Otherwise-valid positive-fee extension | NotEnabled() in preview and execution | Maturity, fee reserve and custody unchanged; no payout | Covered: [lifecycle route and caller matrix][test_givenExtensionLifecycleGuard_rollsBackEveryRouteAndCaller] |
| EXT-L06 | Position owner or authorized operator separately | Active | Enabled | Live eligible debt position created before originations are disabled | `false`; `true` separately | Current Treasury or nonzero RD respectively; destination state is not consulted | Otherwise-valid term count and `maxFee_` | BurnerLoans_AssetOriginationsDisabled(asset) in preview and execution | Maturity, debt, fee reserve, allowance, custody and recipient balances unchanged; no fee collection, payout or events | Covered: [lifecycle route and caller matrix][test_givenExtensionLifecycleGuard_rollsBackEveryRouteAndCaller] |
| EXT-L07 | Position owner or authorized operator separately | Inactive | Disabled | Originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or nonzero RD respectively | Otherwise-valid positive-fee extension | NotEnabled() before the new activity check, in preview and execution | Maturity, debt, fee reserve, allowance, custody and recipients unchanged; no collection, payout or events | Covered: [guard precedence][test_givenDisabledAndPolicyInactive_extendAndPreviewUseLocalGuard] |

## Fee distribution

| ID | Caller | BL state | Asset originations/position | `sendFeesToDistributor` | Live fee recipient | Fee and transfer state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-P01 | Position owner or authorized operator separately | Active/enabled | Originations enabled; live eligible debt position | `false` | Current Treasury | Positive previewed fee; no prior pending fee; exact collection; destination accepts transfer | extend succeeds; exact fee is paid to Treasury | Independent fee, debt/maturity, custody and Treasury deltas; exact payout event | Covered: [authorized callers and routing][test_givenValidPositiveFeeExtension_routesExactFeeForEveryAuthorizedCaller] |
| EXT-P04 | Position owner or authorized operator separately | Active/enabled | Originations enabled; live eligible debt position | `true` | Current nonzero RD | Positive previewed fee; no prior pending fee; exact collection; destination accepts transfer | extend succeeds; exact fee is paid to RD | Independent fee, debt/maturity, custody and RD deltas; exact payout event | Covered: [authorized callers and routing][test_givenValidPositiveFeeExtension_routesExactFeeForEveryAuthorizedCaller] |

## Invalid fee inputs

| ID | Caller | BL state | Asset originations/position | `sendFeesToDistributor` | Fee recipient | Fee and `maxFee_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-I03 | Position owner or authorized operator separately | Active/enabled | Originations enabled; otherwise-valid live debt position | `false`; `true` separately | Current Treasury or RD respectively | Positive previewed fee; `maxFee_=fee-1`; fuzz `maxFee_` in `[0, fee-1]` | BurnerLoans_FeeExceedsMax(fee,maxFee) | No fee collection or payout; loan state unchanged; preview still quotes fee | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_extensionRollsBackEveryRouteAndCaller] |

## Numeric extremes

| ID | Caller | BL and asset/position state | `sendFeesToDistributor` | Fee recipient | Fee boundary and prior pending state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-N01 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or RD respectively | Positive previewed fee; `maxFee_=fee`, then `MAX`; fuzz `[fee, MAX]`; no prior pending fee | Same successful extension and fee for every accepted `maxFee_` | Exact fee paid to selected destination; cap does not change allocation | Covered: [exact and maximum fee caps][test_givenValidPositiveFeeExtension_routesExactFeeForEveryAuthorizedCaller] |
| EXT-N02 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or RD respectively | Configured fee is zero; preserve zero/positive pre-existing pending fee | Extension succeeds without a new fee collection or payout | Existing fee reserve remains untouched | Covered: [zero fee with optional reserve][test_givenZeroConfiguredFee_extensionDoesNotTouchExistingFeeReserve] |
| EXT-N03 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false` | Current Treasury | Smallest positive rounded fee is 1; no prior pending fee | Extension succeeds and routes one token base unit | Exact collection and Treasury delivery | Covered: [one-unit route matrix][test_givenOneUnitExtensionFee_routesExactUnit] |
| EXT-N04 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `true` | Current nonzero RD | Smallest positive rounded fee is 1; no prior pending fee | Extension succeeds and routes one token base unit | Exact collection and RD delivery | Covered: [one-unit route matrix][test_givenOneUnitExtensionFee_routesExactUnit] |

## Fee collection failures

| ID | Caller | BL and asset/position state | `sendFeesToDistributor` | Fee recipient | Payer/token collection state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-I01 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or RD respectively | Positive fee; sufficient balance; allowance=0 | ERC20InsufficientAllowance(BL,0,fee); preview remains available | Rollback loan action, fee reserve, custody and recipients | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_extensionRollsBackEveryRouteAndCaller] |
| EXT-I04 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or RD respectively | Positive fee; sufficient allowance; fee balance=fee-1 | ERC20InsufficientBalance(payer,fee-1,fee); preview remains available | Rollback loan action, fee reserve, allowance, custody and recipients | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_extensionRollsBackEveryRouteAndCaller] |
| EXT-I02 | Position owner or authorized operator separately | BL active/enabled; originations enabled; live eligible debt position | `false`; `true` separately | Current Treasury or RD respectively | Incoming fee token credits an amount different from requested; use one representative inexact receipt because SafeERC20Exact owns return-shape coverage | SafeERC20Exact_InexactTransferFrom(token, BL, expected, received) | Rollback loan action, collected fee, allowance, reserve and custody | Covered: [inexact fee receipt rollback][test_givenInexactIncomingFee_extensionRevertsAndRollsBack] |

## Transfers

| ID | Caller | BL and asset/position state | `sendFeesToDistributor` | Live fee recipient | Prior pending fee | Outgoing token behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-T02 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `false` | Current Treasury | Fuzz zero/positive | Representative ordinary transfer failure after exact fee collection; SafeERC20 owns false/revert return-shape coverage | Extension succeeds; combined Treasury-routed fee is pending | Loan action retained; fee debt/custody/indexes conserved; PayoutDeferred | Covered: [deferred fee route and caller matrix][test_givenFeeDestinationRejects_extensionDefersCombinedFeeExactly] |
| EXT-T04 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `true` | Current nonzero RD | Fuzz zero/positive | Representative ordinary transfer failure after exact fee collection; SafeERC20 owns false/revert return-shape coverage | Extension succeeds; combined RD-routed fee is pending | Loan action retained; fee debt/custody/indexes conserved; PayoutDeferred | Covered: [deferred fee route and caller matrix][test_givenFeeDestinationRejects_extensionDefersCombinedFeeExactly] |

## Callbacks

| ID | Caller | BL and asset/position state | `sendFeesToDistributor` / recipient | Callback phase | Callback behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-C01 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `false`/Treasury and `true`/RD separately | Incoming collection | Fee token catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer action succeeds | Exactly one loan mutation; callback sees the old fee reserve | Covered: [callback phase matrix][test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy] |
| EXT-C04 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `false`/Treasury and `true`/RD separately | Outgoing payout | Fee token catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer action succeeds | Exactly one payment; callback sees the newly accrued fee before debit | Covered: [callback phase matrix][test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy] |
| EXT-C02 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `false`/Treasury and `true`/RD separately | Incoming collection | Fee token propagates nested guarded-call failure | Whole action reverts with controlled callback error | Loan mutation, collected fee, reserve and custody roll back | Covered: [callback phase matrix][test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy] |
| EXT-C03 | Position owner or authorized operator separately | BL active/enabled; valid positive-fee extension | `false`/Treasury and `true`/RD separately | Outgoing payout | Fee token propagates nested guarded-call failure | extend succeeds; outgoing fee deferred | Loan mutation retained; collected fee remains pending; failed transfer has no movement | Covered: [callback phase matrix][test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy] |

## Pending fees and routing changes

| ID | Caller | BL and asset/position state | Prior pending fee | Routing flag transition and live recipient | New fee/transfer state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXT-P02 | Position owner | BL active/enabled; originations enabled; live eligible debt position | Positive fee deferred under either prior flag | Change or retain `sendFeesToDistributor`; live recipient is current Treasury or RD | Later extension collects a positive fee and outgoing transfer accepts | Both fees use live routing | Reserve and token index clear without double-counting | Covered: [all flag transitions][test_givenDeferredFee_laterExtensionSweepsBothToLiveDestination] |

[test_givenPolicyInactive_whenExtendIsPreviewedOrExecuted_reverts]: ./extend.t.sol#L1502
[test_givenFeeTokenUnlistedByDistributor_extensionStillPaysDistributor]: ./extend.t.sol#L100
[test_givenOneUnitExtensionFee_routesExactUnit]: ./extend.t.sol#L138
[test_givenDeferredFee_laterExtensionSweepsBothToLiveDestination]: ./extend.t.sol#L186
[test_givenDisabledAndPolicyInactive_extendAndPreviewUseLocalGuard]: ./extend.t.sol#L1550
[test_givenValidPositiveFeeExtension_routesExactFeeForEveryAuthorizedCaller]: ./extend.t.sol#L43
[test_givenZeroConfiguredFee_extensionDoesNotTouchExistingFeeReserve]: ./extend.t.sol#L498
[test_givenInexactIncomingFee_extensionRevertsAndRollsBack]: ./extend.t.sol#L561
[test_givenFeeTokenCallback_extensionHandlesIncomingAndOutgoingReentrancy]: ./extend.t.sol#L622
[test_givenDistributorUnavailable_extensionStillPaysExactFee]: ./extend.t.sol#L236
[test_givenExtensionLifecycleGuard_rollsBackEveryRouteAndCaller]: ./extend.t.sol#L297
[test_givenRejectedFeeInput_extensionRollsBackEveryRouteAndCaller]: ./extend.t.sol#L354
[test_givenFeeDestinationRejects_extensionDefersCombinedFeeExactly]: ./extend.t.sol#L433
