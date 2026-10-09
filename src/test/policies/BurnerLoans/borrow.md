# borrow revenue routing scenario plan

Only branch-added fee collection/routing/defer behavior; existing parent borrow risk, debt and collateral cases remain in borrow.t.sol. Scenario tags therefore identify evidence for this plan, not every pre-existing regression test in that file.

BL must be Kernel-active before this action or its executable preview can proceed. All success/input/transfer rows assume BL active. Inactive rejection is tested with otherwise valid inputs and retained caller authorization, for each routing flag; disabled BL remains a separate case.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Use existing action-specific authorized callers, guards and previews; these plans assess only behavior introduced by this branch, not full parent-function coverage. Token amounts use native base units; preview debt uses 9-decimal OHM. `MAX` means `type(uint256).max` for maxFee and fee quantities. Newly introduced payout buckets are described in [transferPendingPayout](./transferPendingPayout.md).

BL state separates Kernel membership from local enablement. Inventory state likewise separates Kernel activity from local enablement because borrow and preview validate both. `sendFeesToDistributor=false` selects the current Treasury; `true` selects the current nonzero Revenue Distributor. RD lifecycle and asset-listing state are not consulted by the direct fee transfer. Unless a row varies them, BL and Inventory are Kernel-active and locally enabled, asset originations are enabled, and the borrower position, prices, caps, collateral and authorization are valid.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Required previewBorrow behavior is BL active/enabled and Inventory enabled/active; it does not enforce caller authorization or maxFee. Compare preview with action effects where executable; authoritative debt/custody/recipient balances and pending indexes are independent assertions. Fuzz only within reachable action domains; supplement with exact fee zero/one and semantic fee/rounding limits when they affect the new payout behavior.

## Lifecycle

| ID | Caller | BL Kernel | BL local | Inventory Kernel/local | Asset/loan state | `sendFeesToDistributor` | Selected fee destination state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-L01 | Borrower or authorized operator separately | Active | Enabled | Active/enabled | Valid positive-fee borrow; originations enabled | `true` | Current RD is Kernel-active but locally disabled | borrow succeeds; fee transfer does not invoke RD lifecycle guards | RD receives exact fee; BL debt/maturity and pending reserve correct | Covered: [destination-state and caller matrix][test_givenDistributorUnavailableOrTokenUnlisted_borrowStillPaysExactFee] |
| BOR-L05 | Borrower or authorized operator separately | Inactive after deactivation | Enabled | Active/enabled | Valid positive-fee borrow; originations enabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | BurnerLoans_PolicyInactive() in action and executable preview | Unchanged debt, collateral, fee reserve, allowance, custody and recipients; no fee collection, payout or events | Covered: [inactive action and preview][test_givenPolicyInactive_whenBorrowIsPreviewedOrExecuted_reverts] |
| BOR-L02 | Borrower or authorized operator separately | Active | Enabled | Active/enabled | Valid positive-fee borrow; originations enabled | `true` | Current RD is Kernel-inactive but locally enabled | borrow succeeds; fee transfer does not invoke RD lifecycle guards | RD receives exact fee; BL debt/maturity and pending reserve correct | Covered: [destination-state and caller matrix][test_givenDistributorUnavailableOrTokenUnlisted_borrowStillPaysExactFee] |
| BOR-L03 | Borrower or authorized operator separately | Active | Enabled | Active/enabled | Valid positive-fee borrow; originations enabled | `true` | Current RD is active/enabled but fee token is NeverListed | Borrow succeeds; asset listing does not gate direct fee transfer | RD receives exact fee | Covered: [destination-state and caller matrix][test_givenDistributorUnavailableOrTokenUnlisted_borrowStillPaysExactFee] |
| BOR-L04 | Borrower or authorized operator separately | Active | Disabled | Active/enabled | Otherwise-valid positive-fee borrow; originations enabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | NotEnabled() in preview and execution | Unchanged; no fee collection or payout | Covered: [local guard route and caller matrix][test_givenLocallyDisabled_borrowAndPreviewRollbackEveryRoute] |
| BOR-L06 | Borrower or authorized operator separately | Inactive | Disabled | Active/enabled | Otherwise-valid positive-fee borrow; originations enabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | NotEnabled() before the new activity check, in preview and execution | Unchanged; no fee collection or payout | Covered: [guard precedence][test_givenDisabledAndPolicyInactive_borrowAndPreviewUseLocalGuard] |

## Fee distribution

| ID | Caller | BL state | Inventory state | Asset/loan state | `sendFeesToDistributor` | Live fee recipient | Fee and transfer state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-P01 | Borrower or authorized operator separately | Active/enabled | Active/enabled | Originations enabled; valid borrower position | `false` | Current Treasury | Positive previewed fee; no prior pending fee; exact collection; destination accepts transfer | borrow succeeds; exact fee is paid to Treasury | Independent fee, debt/maturity, custody and Treasury deltas; exact payout event | Covered: [authorized callers and routing][test_givenValidPositiveFeeBorrow_routesExactFeeForEveryAuthorizedCaller] |
| BOR-P04 | Borrower or authorized operator separately | Active/enabled | Active/enabled | Originations enabled; valid borrower position | `true` | Current nonzero RD | Positive previewed fee; no prior pending fee; exact collection; destination accepts transfer | borrow succeeds; exact fee is paid to RD | Independent fee, debt/maturity, custody and RD deltas; exact payout event | Covered: [authorized callers and routing][test_givenValidPositiveFeeBorrow_routesExactFeeForEveryAuthorizedCaller] |

## Invalid fee inputs

| ID | Caller | BL/Inventory state | Asset/loan state | `sendFeesToDistributor` | Fee recipient | Fee and `maxFee_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-I03 | Borrower or authorized operator separately | Both active/enabled | Originations enabled; otherwise-valid borrower position | `false`; `true` separately | Current Treasury or RD respectively | Positive previewed fee; `maxFee_=fee-1`; fuzz `maxFee_` in `[0, fee-1]` | BurnerLoans_FeeExceedsMax(fee,maxFee) | No fee collection or payout; loan state unchanged; preview still quotes fee | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_borrowRollsBackEveryRouteAndCaller] |

## Numeric extremes

| ID | Caller | BL/Inventory and loan state | `sendFeesToDistributor` | Fee recipient | Fee boundary and prior pending state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-N01 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false`; `true` separately | Current Treasury or RD respectively | Positive previewed fee; `maxFee_=fee`, then `MAX`; fuzz `[fee, MAX]`; no prior pending fee | Same successful loan action and fee for every accepted `maxFee_` | Exact fee paid to selected destination; cap does not change allocation | Covered: [exact and maximum fee caps][test_givenValidPositiveFeeBorrow_routesExactFeeForEveryAuthorizedCaller] |
| BOR-N02 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false`; `true` separately | Current Treasury or RD respectively | Configured fee is zero; preserve zero/positive pre-existing pending fee | Borrow succeeds without a new fee collection or payout | Existing fee reserve remains untouched | Covered: [zero fee with optional reserve][test_givenZeroConfiguredFee_borrowDoesNotTouchExistingFeeReserve] |
| BOR-N03 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false` | Current Treasury | Smallest positive rounded fee is 1; no prior pending fee | Borrow succeeds and routes one token base unit | Exact collection and Treasury delivery | Covered: [one-unit fee][test_givenOneUnitDebt_borrowChargesOneUnitFee] |
| BOR-N04 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `true` | Current nonzero RD | Smallest positive rounded fee is 1; no prior pending fee | Borrow succeeds and routes one token base unit | Exact collection and RD delivery | Covered: [one-unit fee][test_givenOneUnitDebt_borrowChargesOneUnitFee] |

## Fee collection failures

| ID | Caller | BL/Inventory and loan state | `sendFeesToDistributor` | Fee recipient | Payer/token collection state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-I01 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false`; `true` separately | Current Treasury or RD respectively | Positive fee; sufficient balance; allowance=0 | ERC20InsufficientAllowance(BL,0,fee); preview remains available | Rollback loan action, fee reserve, custody and recipients | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_borrowRollsBackEveryRouteAndCaller] |
| BOR-I04 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false`; `true` separately | Current Treasury or RD respectively | Positive fee; sufficient allowance; balance=fee-1 | ERC20InsufficientBalance(payer,fee-1,fee); preview remains available | Rollback loan action, fee reserve, allowance, custody and recipients | Covered: [fee rejection route and caller matrix][test_givenRejectedFeeInput_borrowRollsBackEveryRouteAndCaller] |
| BOR-I02 | Borrower or authorized operator separately | Both active/enabled; valid origination and position | `false`; `true` separately | Current Treasury or RD respectively | Incoming fee token credits an amount different from requested; use one representative inexact receipt because SafeERC20Exact owns return-shape coverage | SafeERC20Exact_InexactTransferFrom(token, BL, expected, received) | Rollback loan action, collected fee, allowance, reserve and custody | Covered: [inexact fee receipt rollback][test_givenInexactIncomingFee_borrowRevertsAndRollsBack] |

## Transfers

| ID | Caller | BL/Inventory and loan state | `sendFeesToDistributor` | Live fee recipient | Prior pending fee | Outgoing token behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-T02 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `false` | Current Treasury | Fuzz zero/positive | Representative ordinary transfer failure after exact fee collection; SafeERC20 owns false/revert return-shape coverage | Borrow succeeds; combined Treasury-routed fee is pending | Loan action retained; fee debt/custody/indexes conserved; PayoutDeferred | Covered: [deferred fee route and caller matrix][test_givenFeeDestinationRejects_borrowDefersCombinedFeeExactly] |
| BOR-T04 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `true` | Current nonzero RD | Fuzz zero/positive | Representative ordinary transfer failure after exact fee collection; SafeERC20 owns false/revert return-shape coverage | Borrow succeeds; combined RD-routed fee is pending | Loan action retained; fee debt/custody/indexes conserved; PayoutDeferred | Covered: [deferred fee route and caller matrix][test_givenFeeDestinationRejects_borrowDefersCombinedFeeExactly] |

## Callbacks

| ID | Caller | BL/Inventory and loan state | `sendFeesToDistributor` / recipient | Callback phase | Callback behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-C01 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `false`/Treasury and `true`/RD separately | Incoming collection | Fee token catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer action succeeds | Exactly one loan mutation; callback sees the old fee reserve | Covered: [callback phase matrix][test_givenFeeTokenCallback_borrowHandlesIncomingAndOutgoingReentrancy] |
| BOR-C04 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `false`/Treasury and `true`/RD separately | Outgoing payout | Fee token catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer action succeeds | Exactly one payment; callback sees the newly accrued fee before debit | Covered: [callback phase matrix][test_givenFeeTokenCallback_borrowHandlesIncomingAndOutgoingReentrancy] |
| BOR-C02 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `false`/Treasury and `true`/RD separately | Incoming collection | Fee token propagates nested guarded-call failure | Whole action reverts with controlled callback error | Loan mutation, collected fee, reserve and custody roll back | Covered: [callback phase matrix][test_givenFeeTokenCallback_borrowHandlesIncomingAndOutgoingReentrancy] |
| BOR-C03 | Borrower or authorized operator separately | Both active/enabled; valid positive-fee origination | `false`/Treasury and `true`/RD separately | Outgoing payout | Fee token propagates nested guarded-call failure | borrow succeeds; outgoing fee deferred | Loan mutation retained; collected fee remains pending; failed transfer has no movement | Covered: [callback phase matrix][test_givenFeeTokenCallback_borrowHandlesIncomingAndOutgoingReentrancy] |
| BOR-C05 | Borrower | Both active/enabled; valid positive-fee origination | `false`/Treasury | MINTR mint | Replacement MINTR catches a nested authorized borrow | Nested ReentrancyGuardReentrantCall(); outer action succeeds | Exactly one mint, debt increase and borrower-index insertion | Covered: [MINTR callback boundary][test_givenReentrantMintr_borrowCannotMintOrIndexTwice] |

## Pending fees and routing changes

| ID | Caller | BL/Inventory and loan state | Prior pending fee | Routing flag transition and live recipient | New fee/transfer state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-P02 | Borrower | Both active/enabled; valid originations and positions | Positive fee deferred under either prior flag | Change or retain `sendFeesToDistributor`; live recipient is current Treasury or RD | Second positive fee collected; outgoing transfer accepts | Both fees are swept to the live fee destination | No old fee double-counting; reserve and token index clear | Covered: [all routing transitions][test_givenDeferredFee_secondBorrowSweepsToLiveDestination] |

## Transfer gas

| ID | Caller | BL/Inventory and loan state | `sendFeesToDistributor` | Live fee recipient | Outgoing token behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BOR-P03 | Borrower | Both active/enabled; valid positive-fee origination | `false`; `true` separately | Current Treasury or RD respectively | Transfer needs more gas than the former fixed cap; normal caller budget is sufficient | Borrow succeeds and fee is delivered immediately | No fee left pending; no transfer gas cap applied | Covered: [route matrix and exact payout][test_givenTransferNeedsMoreThanFormerCap_whenBorrowed_thenFeePaysImmediately] |

[test_givenTransferNeedsMoreThanFormerCap_whenBorrowed_thenFeePaysImmediately]: ./transferPendingPayout.t.sol#L1261
[test_givenOneUnitDebt_borrowChargesOneUnitFee]: ./borrow.t.sol#L2214
[test_givenPolicyInactive_whenBorrowIsPreviewedOrExecuted_reverts]: ./borrow.t.sol#L1627
[test_givenDisabledAndPolicyInactive_borrowAndPreviewUseLocalGuard]: ./borrow.t.sol#L1675
[test_givenValidPositiveFeeBorrow_routesExactFeeForEveryAuthorizedCaller]: ./borrow.t.sol#L132
[test_givenZeroConfiguredFee_borrowDoesNotTouchExistingFeeReserve]: ./borrow.t.sol#L499
[test_givenInexactIncomingFee_borrowRevertsAndRollsBack]: ./borrow.t.sol#L561
[test_givenFeeTokenCallback_borrowHandlesIncomingAndOutgoingReentrancy]: ./borrow.t.sol#L2510
[test_givenReentrantMintr_borrowCannotMintOrIndexTwice]: ./borrow.t.sol#L2622
[test_givenDistributorUnavailableOrTokenUnlisted_borrowStillPaysExactFee]: ./borrow.t.sol#L191
[test_givenLocallyDisabled_borrowAndPreviewRollbackEveryRoute]: ./borrow.t.sol#L256
[test_givenRejectedFeeInput_borrowRollsBackEveryRouteAndCaller]: ./borrow.t.sol#L300
[test_givenFeeDestinationRejects_borrowDefersCombinedFeeExactly]: ./borrow.t.sol#L379
[test_givenDeferredFee_secondBorrowSweepsToLiveDestination]: ./borrow.t.sol#L443
