# BurnerLoans.rescue coverage plan

Scope: BL's surplus rescue and co-located `previewRescue` assertions. BL = BurnerLoans; BLC = BurnerLoansConfig. Each row links to tests with reciprocal Scenarios comments.

BL accepts the bound Configurator or current admin. If BLC/BLCT is disabled or inactive, admin can rescue directly from locally enabled or disabled BL. BL must remain Kernel-active.

## Domains and assertions

- Configurator = BL's currently selected BLC; Admin = ADMIN_ROLE holder. Default: BL enabled and Kernel-active, valid token and unrelated destination. BL may be locally disabled; preview and execution require Kernel activity. Preview is permissionless and ignores local enablement.
- B = BL token custody; R = aggregate pending payouts; S = max(B−R, 0); MAX = uint256 maximum. All quantities are token base units, without decimal conversion. Rescue has no amount parameter.
- Pending buckets are keeper rewards (10), fees (20) and seized collateral (30). In the ordinary bucket rows, absent buckets are zero and B = R+5. Rescue never pays or debits these obligations.
- Owners: reward belongs to a keeper; fees and seizure belong to their Treasury/RevenueDistributor destinations. Use shared fee/seizure ownership and a separate routing case with distinct owners. Destination may be an owed owner or unrelated, unless forbidden below. Rescue reads the aggregate reserve, so it needs no exhaustive owner-allocation matrix.
- Token configuration does not change the formula. An unconfigured token without pending debt has its entire balance available. A configured token with pending debt exposes only surplus; a configured token without debt also exposes its full balance.
- Positive payment: preview equals independently calculated S; custody decreases by S and destination increases by S, including a pre-existing destination balance. Assert exactly one token Transfer and one BL AssetRescued(token, destination, S), in that order. Each raw bucket, aggregate, retry index, token configuration and unrelated token balance remain unchanged.
- No-op: preview is zero, no transfer is attempted, no Transfer/AssetRescued event is emitted, and all state is unchanged. Use a token that rejects transfers to prove the skipped call. This applies at and below reserve.
- Unchanged: token custody/destination balances, all payout buckets/aggregates/indexes, configuration and callback state are unchanged; no committed events. Error names omit the BurnerLoans_ prefix. Invalid destination uses InvalidRescueDestination, including zero.

## Authorization and lifecycle

Use valid inputs and B=65, R=60, S=5 for success rows, so every allowed state proves payment.

| ID | Caller | BL local state | BL Kernel membership | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| L-01 | Configurator | Enabled | Active | 5 | Pay 5; preserve R=60 | Covered: [configurator rescues][test_givenFacilityEnabled_whenConfiguratorRescues], [permitted caller rescues][test_givenFacilityRestored_whenEachPermittedCallerRescues], [fuzz][test_givenActiveFacility_whenAnyCallerPreviews] |
| L-02 | Configurator | Disabled | Active | 5 | Pay 5; preserve R=60 | Covered: [configurator rescues][test_givenFacilityDisabled_whenConfiguratorRescues], [fuzz][test_givenActiveFacility_whenAnyCallerPreviews] |
| L-03 | Configurator | Enabled/disabled | Inactive | PolicyInactive() | PolicyInactive(); Unchanged | Covered: [configurator rescues][test_givenFacilityInactive_whenConfiguratorRescues_reverts] |
| L-04 | Fuzz caller outside Configurator/Admin | Enabled/disabled | Active/inactive | Active: input checks; inactive: PolicyInactive() | NotAuthorised(); Unchanged, including when token=0 | Covered: [fuzzed callers][test_givenFacilityLifecycle_whenCallerIsUnauthorized_reverts], [fuzz][test_givenActiveFacility_whenAnyCallerPreviews], [caller identities][test_givenUnauthorizedIdentities_whenSeeded_reverts] |
| L-05 | Admin | Enabled/disabled | Inactive | PolicyInactive() | PolicyInactive before invalid input; no payment | Covered: [admin rescues][test_givenFacilityInactive_whenAdminRescues_reverts] |
| L-06 | Admin | Enabled/disabled | Active | 5 | Pay 5; preserve R=60 | Covered: [admin rescues][test_givenFacilityEnabled_whenAdminRescues], [admin rescues][test_givenFacilityDisabled_whenAdminRescues], [permitted caller rescues][test_givenFacilityRestored_whenEachPermittedCallerRescues], [fuzz][test_givenActiveFacility_whenAnyCallerPreviews] |
| A-01 | Admin | Enabled/disabled; BLC/BLCT disabled and active/inactive | Active | 7 | Direct recovery pays surplus 7; retains each pending bucket and reserve 60 | Covered: [admin rescues directly][test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly] |

Inactive policy wins over token=0 or invalid destination in both preview and authorized execution. No separate re-enabled/reactivated history is needed.

## Surplus and pending buckets

P-02 and P-06 through P-11 use the ordinary quantities defined above. Keep populated buckets and their owners explicit in grouped tests; P-13 supplies independent quantity boundaries.

| ID | Caller | State / inputs | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| P-01 | Configurator | Unconfigured token; R=0; fuzz B=1..MAX; seed 1, MAX−1, MAX | B | Rescue full B; positive-payment assertions | Covered: [fuzz][test_givenUnconfiguredToken_whenFullBalanceRescued], [boundaries][test_givenUnconfiguredToken_whenBalanceBoundariesAreSeeded] |
| P-02 | Configurator | Only keeper rewards=10; B=15 | 5 | Pay 5; keeper debt remains 10; fee/seizure remain zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-06 | Configurator | Only fees=20; B=25 | 5 | Pay 5; fees remain 20; other buckets remain zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-07 | Configurator | Only seized collateral=30; B=35 | 5 | Pay 5; seizure remains 30; other buckets remain zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-08 | Configurator | Keeper rewards=10 and fees=20; B=35 | 5 | Pay 5; both debts unchanged; seizure zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-09 | Configurator | Keeper rewards=10 and seizure=30; B=45 | 5 | Pay 5; both debts unchanged; fees zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-10 | Configurator | Fees=20 and seizure=30; B=55 | 5 | Pay 5; both debts unchanged; keeper rewards zero | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-11 | Configurator | Keeper rewards=10, fees=20, seizure=30; B=65 | 5 | Pay 5; all three debts and their aggregate/indexes unchanged | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |
| P-03 | Configurator | Exact reserve B=R; seed R=0, 1, 60, MAX | 0 | No-op, including funded reserve | Covered: [fuzz][test_givenReserve_whenCustodyAtOrBelowReserve], [boundaries][test_givenReserve_whenCustodyBoundariesAreSeeded] |
| P-04 | Configurator | Underfunded; R>0; fuzz B=0..R−1; seed B=0, R−1 with R=1, 60, MAX | 0 | No-op; preserve underfunded custody and every debt | Covered: [fuzz][test_givenReserve_whenCustodyAtOrBelowReserve], [boundaries][test_givenReserve_whenCustodyBoundariesAreSeeded] |
| P-05 | Configurator | Configured token; R=60 in all three buckets; B=65 | 5 | Rescue only 5; retain configuration and reserve 60 | Covered: [surplus rescued][test_givenConfiguredToken_whenSurplusRescued] |
| P-12 | Configurator | Configured token; R=0; B=19 | 19 | Rescue full 19; retain configuration | Covered: [surplus rescued][test_givenConfiguredToken_whenSurplusRescued] |
| P-13 | Configurator | Each nonempty bucket subset; fuzz bucket quantities with sum R<MAX and S=1..MAX−R; seed S=1, MAX−R; seed each subset’s minimum positive R, MAX−1 and B=MAX | S | Positive-payment assertions; no subtraction overflow or reserved-token transfer | Covered: [fuzz][test_givenVariableReserve_whenSurplusRescued], [boundaries][test_givenVariableReserve_whenMaximumBoundariesAreSeeded] |
| ISO-01 | Configurator | Selected token plus another token with debts to three keepers; destination is owed owner or unrelated | Selected S | Only selected surplus moves; all debts/indexes and other custody preserved | Covered: [owed or unrelated destination rescued][test_givenUnrelatedDebts_whenOwedOrUnrelatedDestinationRescued] |

P-01 fuzzes permitted destinations; ISO-01 explicitly seeds owed-owner and unrelated destinations. Existing destination custody and S must fit the token's total-supply budget; test MAX with zero other supply rather than silently bounding it away.

## Invalid inputs

Run with BL active, enabled or disabled, and B below/equal/above R. Preview and execution must return the same input/dependency error and preserve state.

| ID | Caller | Invalid input; other inputs valid | Preview / execution | Test |
| --- | --- | --- | --- | --- |
| I-01 | Configurator | token=0 or nonzero address without code | InvalidAsset(token); Unchanged | Covered: [token has no code][test_givenBucketAndCustodyStates_whenTokenHasNoCode_reverts] |
| I-02 | Configurator | destination=0 | InvalidRescueDestination(0); Unchanged | Covered: [destination is forbidden][test_givenBucketAndCustodyStates_whenDestinationIsForbidden_reverts] |
| I-03 | Configurator | destination=BL, token, current Configurator or Kernel | InvalidRescueDestination(destination); Unchanged | Covered: [destination is forbidden][test_givenBucketAndCustodyStates_whenDestinationIsForbidden_reverts] |
| I-04 | Configurator | Valid-code token with controlled balanceOf revert | Exact dependency failure; Unchanged | Covered: [balance query reverts][test_givenBucketAndCustodyStates_whenBalanceQueryReverts_reverts] |

Zero/no-code tokens use InvalidAsset(token), consistent with RD. Asset validation must precede destination validation. Check preview caller independence beside these cases and the successful action, without a separate preview suite.

## Transfers

Use S=5 with all three debts populated and a pre-existing destination balance. Preview still returns 5 because it does not attempt transfer.

| ID | Caller | Token transfer behavior | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| TX-01 | Configurator | transfer reverts with a controlled custom error | Bubble exact token error; Unchanged | Covered: [transfer reverts][test_givenPendingReserve_whenTransferReverts_reverts] |
| TX-02 | Configurator | transfer returns false | SafeERC20FailedOperation(token); Unchanged | Covered: [transfer returns false][test_givenPendingReserve_whenTransferReturnsFalse_reverts] |
| TX-03 | Configurator | Standard transfer returns true | Pay S=5 once; custody 65→60; destination +5; preserve R=60 and shared success assertions | Covered: [fuzz][test_givenBucketSubset_whenSurplusRescued], [fixed fixtures][test_givenBucketSubsets_whenEachIsSeeded] |

## Callbacks

Authorize the nested route and seed its otherwise valid inputs so the callback reaches the guard. Keep outer and nested token choices explicit.

| ID | Caller | Callback | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| CB-01 | Configurator | Reenter surplus rescue for same token; catch or propagate failure | Nested ReentrancyGuardReentrantCall(); caught: one outer payment, preview afterward=0; propagated: token CallbackFailed() and Unchanged (nested guard failure confirmed in the caught counterpart) | Covered: [surplus rescue: caught][test_givenSurplusRescueCallback_whenFailureIsCaught], [surplus rescue: propagated][test_givenSurplusRescueCallback_whenFailureIsPropagated] |
| CB-02 | Configurator | Attempt an otherwise eligible pending rescue/retry for same or different token; catch or propagate failure | Same guard and outer outcomes; no nested debt/index/configuration mutation | Covered: [pending rescue: caught][test_givenPendingRescueCallback_whenFailureIsCaught], [pending rescue: propagated][test_givenPendingRescueCallback_whenFailureIsPropagated], [pending retry: caught][test_givenPendingRetryCallback_whenFailureIsCaught], [pending retry: propagated][test_givenPendingRetryCallback_whenFailureIsPropagated] |

[test_givenFacilityEnabled_whenConfiguratorRescues]: ./rescue.t.sol#L266
[test_givenFacilityRestored_whenEachPermittedCallerRescues]: ./rescue.t.sol#L404
[test_givenActiveFacility_whenAnyCallerPreviews]: ./rescue.t.sol#L439
[test_givenFacilityDisabled_whenConfiguratorRescues]: ./rescue.t.sol#L279
[test_givenFacilityInactive_whenConfiguratorRescues_reverts]: ./rescue.t.sol#L296
[test_givenFacilityLifecycle_whenCallerIsUnauthorized_reverts]: ./rescue.t.sol#L420
[test_givenUnauthorizedIdentities_whenSeeded_reverts]: ./rescue.t.sol#L460
[test_givenFacilityInactive_whenAdminRescues_reverts]: ./rescue.t.sol#L365
[test_givenFacilityEnabled_whenAdminRescues]: ./rescue.t.sol#L335
[test_givenFacilityDisabled_whenAdminRescues]: ./rescue.t.sol#L348
[test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly]: ./rescue.t.sol#L492
[test_givenUnconfiguredToken_whenFullBalanceRescued]: ./rescue.t.sol#L76
[test_givenUnconfiguredToken_whenBalanceBoundariesAreSeeded]: ./rescue.t.sol#L92
[test_givenBucketSubset_whenSurplusRescued]: ./rescue.t.sol#L35
[test_givenBucketSubsets_whenEachIsSeeded]: ./rescue.t.sol#L48
[test_givenReserve_whenCustodyAtOrBelowReserve]: ./rescue.t.sol#L187
[test_givenReserve_whenCustodyBoundariesAreSeeded]: ./rescue.t.sol#L196
[test_givenConfiguredToken_whenSurplusRescued]: ./rescue.t.sol#L220
[test_givenVariableReserve_whenSurplusRescued]: ./rescue.t.sol#L113
[test_givenVariableReserve_whenMaximumBoundariesAreSeeded]: ./rescue.t.sol#L135
[test_givenUnrelatedDebts_whenOwedOrUnrelatedDestinationRescued]: ./rescue.t.sol#L237
[test_givenBucketAndCustodyStates_whenTokenHasNoCode_reverts]: ./rescue.t.sol#L521
[test_givenBucketAndCustodyStates_whenDestinationIsForbidden_reverts]: ./rescue.t.sol#L556
[test_givenBucketAndCustodyStates_whenBalanceQueryReverts_reverts]: ./rescue.t.sol#L596
[test_givenPendingReserve_whenTransferReverts_reverts]: ./rescue.t.sol#L630
[test_givenPendingReserve_whenTransferReturnsFalse_reverts]: ./rescue.t.sol#L635
[test_givenSurplusRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L685
[test_givenSurplusRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L741
[test_givenPendingRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L797
[test_givenPendingRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L853
[test_givenPendingRetryCallback_whenFailureIsCaught]: ./rescue.t.sol#L909
[test_givenPendingRetryCallback_whenFailureIsPropagated]: ./rescue.t.sol#L965
