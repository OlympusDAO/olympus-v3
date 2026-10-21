# BurnerLoans.transferPendingPayout scenario plan

Scope: permissionless BL retry and pendingPayout/getPendingPayoutTokens/getPendingPayoutRecipients. transferPendingSeizurePayout.t.sol tests this same public function; there is no separate public transferPendingSeizurePayout API.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Debt, custody and transfer quantities are uint256 token base units; `MAX` means `type(uint256).max`.

BL = BurnerLoans. Fuzz caller without exclusions. Kernel-active then locally enabled required, including when no debt. Buckets: fee follows current revenueDistributor when sendFeesToDistributor, otherwise current Treasury; seized collateral follows current Treasury; keeper reward remains fixed to original keeper. Retry transfer order: fee, seized collateral, keeper reward. Even overlapping identities receive separate per-bucket token calls.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Return sum of successfully delivered matching buckets, not total entitlement when some sends fail. For each bucket check PayoutTransferred or PayoutDeferred(token,recipient,kind,amount), exact custody/recipient delta, debt decrement or retention and recipient/token index cleanup. Other recipients and tokens remain unaffected; repeat successful retry returns zero silently.

## Lifecycle

| ID | Caller | BL Kernel | BL local | Matching debt | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-L01 | Any caller, fuzz | Active | Disabled | Fuzz zero/positive | NotEnabled() | Unchanged | Covered: [positive debt and indexes][test_givenPositivePending_whenDisabledAndInactive_viewsRemainReadable], [zero debt][test_givenDisabled_whenAnyCallerRetries_reverts] |
| BLTRY-L02 | Any caller, fuzz | Inactive | Fuzz enabled/disabled | Fuzz zero/positive independently | BurnerLoans_PolicyInactive() before local guard | Unchanged | Covered: [positive debt and disabled precedence][test_givenPositivePending_whenDisabledAndInactive_viewsRemainReadable], [zero debt][testFuzz_givenNoPending_givenInactive_whenAnyCallerFlushes_reverts] |
| BLTRY-L03 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Fuzz zero/positive independently | pendingPayout/getPendingPayoutTokens/getPendingPayoutRecipients remain readable and exact | No state change or token call | Covered: [positive lifecycle states][test_givenPositivePending_whenDisabledAndInactive_viewsRemainReadable], [zero active state][test_givenNoPending_whenEnumerated_returnsEmptyArrays] |

## No entitlement

| ID | Caller | Token input | Recipient input | Matching debt | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-P01 | Any caller, fuzz | Fuzz zero, EOA, unknown contract | Fixed unrelated address | None | Return 0; no token call or payout event | Unchanged | Covered: [token input classes][test_givenNoEntitlement_whenAnyCallerRetries_returnsZero] |
| BLTRY-P13 | Any caller, fuzz | Valid contract | Fuzz zero, EOA, former role without fixed entitlement, unrelated address | None | Return 0; no token call or payout event | Unchanged | Covered: [recipient input classes][test_givenNoEntitlement_whenAnyCallerRetries_returnsZero] |
| BLTRY-P17 | Any caller, fuzz | Previously owed token | Previously owed recipient | Already paid | Return 0; no token call or payout event | Unchanged | Covered: [repeat retry][test_givenSinglePendingBucket_whenTransferFails_thenRetryPaysExactlyOnce] |

## Transfers

| ID | Caller | Positive bucket mask | Custody | Ordered transfer behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-T01 | Any caller, fuzz | Exactly one of fee, seizure, keeper | Solvent | Representative ordinary transfer failure; SafeERC20 owns false/revert return-shape coverage | Return zero for the selected bucket; PayoutDeferred emitted with its exact kind/amount | Selected debt and indexes retained; later retry pays it once; other buckets unchanged | Covered: [all single buckets][test_givenSinglePendingBucket_whenTransferFails_thenRetryPaysExactlyOnce] |
| BLTRY-T06 | Any caller, fuzz | At least two buckets for one recipient | Solvent | One succeeds and one has a representative ordinary transfer failure | Return successful subtotal; PayoutDeferred only for failed send | Partial progress retained; later retry pays only remaining bucket | Covered: [sequenced transfer failure][test_givenTwoOrderedBuckets_retryRetainsOnlyFailedRemainder] |
| BLTRY-T02 | Any caller, fuzz | At least two ordered buckets | First affordable; next underfunded | First succeeds; next gives standard insufficient-balance failure | Return delivered subtotal; failed transfer is deferred | No explicit reserve-solvency revert; retained debt remains indexed | Covered: [underfunded second bucket][test_givenTwoOrderedBuckets_retryRetainsOnlyFailedRemainder] |

## Callbacks

| ID | Caller | Bucket mask | Nested guarded call | Callback handling | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-C01 | Any caller, fuzz | Fuzz fee/seizure/keeper | Retry or another guarded BL write | Caught | Nested ReentrancyGuardReentrantCall(); outer pays once | No duplicated payout | Covered: [all bucket and nested-entry matrices][test_givenPayoutTokenCallback_retryHandlesEveryBucket] |
| BLTRY-C02 | Any caller, fuzz | Fuzz fee/seizure/keeper, including another healthy bucket | Retry or another guarded BL write | Propagated | Transfer deferred, return zero for affected bucket | Affected debt/custody retained; other sends may progress | Covered: [all bucket, nested-entry and mixed-progress matrices][test_givenPayoutTokenCallback_retryHandlesEveryBucket] |

## Fee bucket

| ID | Caller | Fee debt | `sendFeesToDistributor` | RD pointer | Resolved fee recipient | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-P02 | Any caller, fuzz | Amount 1..MAX; seed 1,MAX | Fuzz false/true | Fuzz zero/nonzero compatibly | Current Treasury or selected RD according to flag and pointer | Return full fee on successful delivery | Fee debt clears; reserve/token index updated | Covered: [caller, route and full uint256 quantity matrix][test_givenPendingFee_retryPaysEveryQuantityToCurrentRoute] |

## Seizure and keeper buckets

| ID | Caller | Positive bucket | Role state | Resolved recipient | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-P03 | Any caller, fuzz | Seized collateral only | Treasury unchanged/upgraded | Current Treasury | Return full seizure amount | Current Treasury is paid; keeper debts remain unchanged | Covered: [caller, Treasury and full uint256 quantity matrix with isolation][test_givenPendingSeizure_retryPaysEveryQuantityAndPreservesOtherToken] |
| BLTRY-P18 | Any caller, fuzz | Keeper reward only | Keeper identity fixed at accrual | Original keeper | Return full keeper amount | Fixed keeper is paid; other keeper and role debts remain unchanged | Covered: [single keeper bucket][test_givenSinglePendingBucket_whenTransferFails_thenRetryPaysExactlyOnce] |

## Overlapping debt buckets

| ID | Caller | Shared recipient | Positive bucket mask | Amount domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-P04 | Any caller, fuzz | One address resolves for every selected bucket | Fuzz fee+seizure, fee+keeper, seizure+keeper, all three | Independent positive quantities whose sum does not overflow | One ordered transfer per positive bucket; return exact sum | Clear only selected debt; getters list recipient once; unrelated buckets/recipients unchanged | Covered: [all masks, quantity fuzz, transfer count and event order][test_givenOverlappingBuckets_retryPaysEachSelectedBucketInOrder] |

## Routing changes

| ID | Caller | Positive bucket mask | Fee flag transition | Role/pointer transition | Recipient relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLTRY-P05 | Any caller, fuzz | Fee only | Remains true | RD old -> new | Old/new RD distinct; neither is keeper | Old RD retry returns 0; new RD receives fee | Debt follows new role; exact fee event, balance delta and getter/index cleanup | Covered: [replacement route and full accounting][test_givenFeeRouteChanges_retryUsesOnlyCurrentRecipient] |
| BLTRY-P07 | Any caller, fuzz | Fee only | True -> false | RD unchanged; Treasury current | RD/Treasury distinct; neither is keeper | Former RD returns 0; current Treasury receives fee | Fee debt follows Treasury; exact balance/event and getter/index updates | Covered: [flag transition and full accounting][test_givenFeeRouteChanges_retryUsesOnlyCurrentRecipient] |
| BLTRY-P08 | Any caller, fuzz | Fee, with optional seizure/keeper debt | False -> true | Compatible RD selected | Treasury/RD distinct | Former Treasury returns 0 for fee-only entitlement; selected RD receives fee | Treasury seizure debt, if present, stays with Treasury; fixed keeper debt preserved | Covered: [all optional bucket combinations and route isolation][test_givenTreasuryFeeRouteMovesToDistributor_otherBucketsStayBound] |
| BLTRY-P09 | Any caller, fuzz | Fee and/or seizure | Unchanged | Treasury old -> new while BL inactive, then refreshed | Old/new Treasury distinct; neither is keeper | Current Treasury receives role debt; former Treasury returns 0 | Both role buckets follow refreshed Treasury; preserve unrelated fees and keeper debt | Covered: [combined role debt, former no-op and unrelated debt preservation][test_givenTreasuryUpgrades_combinedRoleDebtFollowsCurrentTreasury] |
| BLTRY-P10 | Any caller, fuzz | Keeper plus fee or seizure role debt | Any compatible value | Former RD or Treasury role rotates | Original keeper equals former role address | Former role address still receives its fixed keeper reward, without redirected role debt | Keeper entitlement remains address-bound; current role receives only its matching debt | Covered: [former RD remains fixed keeper][test_givenFormerDistributorIsKeeper_rotationPreservesOnlyFixedReward] |

[test_givenDisabled_whenAnyCallerRetries_reverts]: ./transferPendingPayout.t.sol#L760
[testFuzz_givenNoPending_givenInactive_whenAnyCallerFlushes_reverts]: ./transferPendingPayout.t.sol#L774
[test_givenNoPending_whenEnumerated_returnsEmptyArrays]: ./transferPendingPayout.t.sol#L360
[test_givenNoEntitlement_whenAnyCallerRetries_returnsZero]: ./transferPendingPayout.t.sol#L211
[test_givenPositivePending_whenDisabledAndInactive_viewsRemainReadable]: ./transferPendingPayout.t.sol#L257
[test_givenSinglePendingBucket_whenTransferFails_thenRetryPaysExactlyOnce]: ./transferPendingPayout.t.sol#L287
[test_givenTwoOrderedBuckets_retryRetainsOnlyFailedRemainder]: ./transferPendingSeizurePayout.t.sol#L91
[test_givenFormerDistributorIsKeeper_rotationPreservesOnlyFixedReward]: ./transferPendingPayout.t.sol#L1210
[test_givenPayoutTokenCallback_retryHandlesEveryBucket]: ./transferPendingPayout.t.sol#L585
[test_givenPendingFee_retryPaysEveryQuantityToCurrentRoute]: ./transferPendingPayout.t.sol#L114
[test_givenPendingSeizure_retryPaysEveryQuantityAndPreservesOtherToken]: ./transferPendingSeizurePayout.t.sol#L19
[test_givenOverlappingBuckets_retryPaysEachSelectedBucketInOrder]: ./transferPendingPayout.t.sol#L159
[test_givenFeeRouteChanges_retryUsesOnlyCurrentRecipient]: ./transferPendingPayout.t.sol#L966
[test_givenTreasuryFeeRouteMovesToDistributor_otherBucketsStayBound]: ./transferPendingPayout.t.sol#L1027
[test_givenTreasuryUpgrades_combinedRoleDebtFollowsCurrentTreasury]: ./transferPendingPayout.t.sol#L1108
