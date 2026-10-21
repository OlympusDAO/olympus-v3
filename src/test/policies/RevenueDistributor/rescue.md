# RevenueDistributor.rescue coverage plan

Scope: RD's surplus rescue and co-located preview assertions. RD = RevenueDistributor. Each row links to tests with reciprocal Scenarios comments.

Local disablement retains admin/current operator recovery. A disabled timelock blocks its queues and execution; admin can call RD directly. Kernel inactivity rejects preview and execution.

## Domains and assertions

- Admin = ADMIN_ROLE holder; Operator = current nonzero configOperator. Test these separately. Unauthorized callers include zero, emergency-only, revenue_distributor_admin-only and former operator unless independently authorized.
- Default: RD enabled and Kernel-active; NeverListed token, unrelated valid destination. Preview and execution allow local disablement but require Kernel activity. Preview is permissionless and is checked beside each action case.
- Only NeverListed assets qualify. Active and Retired assets remain managed, including when their pending debt is zero. Supported public flows create debt only after listing, so a successful NeverListed rescue has no pending debt and sends the full live token balance B.
- Amounts are token base units; MAX=uint256 maximum. There is no amount parameter. Ordinary B=19. Permitted destinations include Treasury, current operator and an unrelated address; forbidden destinations are zero, Kernel, RD and the asset itself.
- Positive payment: preview=B; custody falls by B, destination rises by B. Assert exactly one token Transfer then one RD AssetRescued(asset,destination,B). Routes, listing, raw pending Treasury/yield/configured-recipient debts, aggregates, retry indexes, operator and other assets remain unchanged.
- No-op: B=0; preview=0; no token call or rescue/transfer event, including if transfers would reject. Unchanged: balances and all those states unchanged; no committed events. Errors omit RevenueDistributor_. InvalidRescueDestination includes zero.

## Authorization and lifecycle

Every success row uses B=19 and destination starting balance=7, ending with RD custody=0 and destination=26. Active previews return 19; inactive previews revert PolicyInactive(), independently of caller authorization.

| ID | Caller | RD local state | RD Kernel membership | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| L-01 | Admin | Enabled | Active | Pay 19; shared success assertions | Covered: [admin rescues][test_givenDistributorEnabled_whenAdminRescues], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [surplus rescued][test_givenDistributorRestored_whenSurplusRescued] |
| L-02 | Operator | Enabled | Active | Pay 19; shared success assertions | Covered: [operator rescues][test_givenDistributorEnabled_whenOperatorRescues], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews] |
| L-06 | Admin | Disabled | Active | Pay 19; shared success assertions | Covered: [admin rescues][test_givenDistributorDisabled_whenAdminRescues], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews] |
| L-07 | Operator | Disabled | Active | Pay 19; shared success assertions | Covered: [operator rescues][test_givenDistributorDisabled_whenOperatorRescues], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews] |
| L-03 | Admin | Enabled/disabled | Inactive | PolicyInactive(); Unchanged | Covered: [admin rescues][test_givenDistributorInactive_whenAdminRescues_reverts], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts] |
| L-04 | Operator | Enabled/disabled | Inactive | PolicyInactive(); Unchanged | Covered: [operator rescues][test_givenDistributorInactive_whenOperatorRescues_reverts], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts] |
| L-05 | Fuzz caller outside Admin/Operator | Enabled/disabled | Active/inactive | UnauthorizedConfigOperator(caller); Unchanged | Covered: [fuzzed callers][test_givenDistributorLifecycle_whenCallerUnauthorized_reverts], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [caller identities][test_givenUnauthorizedIdentities_whenSeeded_reverts] |
| A-01 | Admin | Enabled/disabled; timelock disabled or Kernel-inactive | Active | Pay 19 directly; one transfer and AssetRescued; no timelock action created | Covered: [admin rescues directly][test_givenTimelockUnavailable_whenAdminRescuesDirectly] |

Check competing faults separately: unauthorized caller wins over asset=0 and inactivity; authorized caller with inactive RD gets PolicyInactive even for invalid input. Inactive preview also gets PolicyInactive before input validation. No re-enabled/reactivated history rows.

## Surplus and isolation

| ID | Caller | State / inputs / boundaries | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| P-01 | Admin; Operator separately | NeverListed; fuzz B=1..MAX; seed 1, MAX−1, MAX; fuzz valid destination and guarantee Treasury/operator/unrelated identities | B | Full payment; include zero/nonzero destination starting balance within total-supply budget | Covered: [fuzz][test_givenNeverListedAsset_whenFullCustodyRescued], [fixed fixtures][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded] |
| P-02 | Admin; Operator separately | NeverListed; B=0; transfer rejects if called | 0 | No-op; Unchanged | Covered: [permitted caller rescues][test_givenZeroCustody_whenEachPermittedCallerRescues] |
| ISO-01 | Admin; Operator separately | NeverListed token alongside another managed asset with Treasury, yield-recipient and three configured-recipient debts | Selected B | Only selected custody moves; other raw debts/aggregate/indexes/balances/routes preserved | Covered: [fuzz][test_givenNeverListedAsset_whenFullCustodyRescued], [fixed fixtures][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded] |
| AUTH-01 | Admin; current/former Operator | Operator changed/revoked to zero; B=19 | 19 | Admin/current operator pays 19; former operator/zero caller rejected unless independently admin | Covered: [former operator rejected][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [current authority][test_givenOperatorRotated_whenCurrentAuthorityRescues], [former operator rejected][test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts], [admin after revocation][test_givenOperatorRevoked_whenAdminRescues] |

## Invalid inputs

Run each permitted caller separately with RD Kernel-active and enabled or disabled. Co-locate exact preview and execution errors, plus Unchanged assertions.

| ID | Caller | State / invalid input | Preview / execution | Test |
| --- | --- | --- | --- | --- |
| I-01 | Admin; Operator separately | asset=0 or nonzero address without code; valid destination | InvalidAsset(asset) | Covered: [asset has no code][test_givenNeverListedAsset_whenAssetHasNoCode_reverts] |
| I-02 | Admin; Operator separately | destination=0, Kernel, RD or asset; valid asset; seed B=0, 1, MAX | InvalidRescueDestination(destination) | Covered: [destination is forbidden][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts] |
| I-03 | Admin; Operator separately | Active asset; seed B=0 with no debt, B=R−1 and B=R with nonzero pending Treasury/yield/configured debts, and B=R+5 | AssetManaged(asset); Unchanged | Covered: [surplus rescue requested][test_givenActiveAsset_whenSurplusRescueRequested_reverts] |
| I-04 | Admin; Operator separately | Retired asset; same explicit custody/debt constructions as I-03 | AssetManaged(asset); Unchanged | Covered: [surplus rescue requested][test_givenRetiredAsset_whenSurplusRescueRequested_reverts] |
| I-05 | Admin; Operator separately | Valid-code NeverListed token with controlled balanceOf failure | Exact dependency error; Unchanged | Covered: [balance query reverts][test_givenNeverListedAsset_whenBalanceQueryReverts_reverts] |

Address validation precedes listing validation, which precedes balanceOf. Preserve that order with asset=0 plus forbidden destination, and managed asset plus forbidden destination. Do not fabricate pending-debt combinations for NeverListed tokens.

## Transfers

Use NeverListed B=19 and existing destination balance=7; seed an unrelated managed asset's debts. Preview=19 for both failures.

| ID | Caller | Transfer behavior | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| TX-01 | Admin; Operator separately | transfer reverts with controlled custom error | Bubble exact token error; Unchanged | Covered: [transfer reverts][test_givenNeverListedAsset_whenTransferReverts_reverts] |
| TX-02 | Admin; Operator separately | transfer returns false | SafeERC20FailedOperation(asset); Unchanged | Covered: [transfer returns false][test_givenNeverListedAsset_whenTransferReturnsFalse_reverts] |

## Callbacks

Nested requests must be independently authorized and otherwise valid, so they reach the intended guard.

| ID | Caller | Callback | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| CB-01 | Admin; Operator separately | Reenter surplus rescue for same or another NeverListed token; catch/propagate guard failure | Nested ReentrancyGuardReentrantCall(); caught: exactly one outer payment and post-transfer preview=0; propagated: token CallbackFailed() and Unchanged (nested guard failure confirmed in the caught counterpart) | Covered: [surplus rescue: caught][test_givenSurplusRescueCallback_whenFailureIsCaught], [surplus rescue: propagated][test_givenSurplusRescueCallback_whenFailureIsPropagated] |
| CB-02 | Admin; Operator separately | Attempt otherwise eligible pending payout/retry/distribute on a managed token or guarded configuration; catch/propagate | Same guard and outer outcomes; no nested debt/index/configuration mutation | Covered: [pending rescue: caught][test_givenPendingRescueCallback_whenFailureIsCaught], [pending rescue: propagated][test_givenPendingRescueCallback_whenFailureIsPropagated], [pending retry: caught][test_givenPendingRetryCallback_whenFailureIsCaught], [pending retry: propagated][test_givenPendingRetryCallback_whenFailureIsPropagated], [distribute: caught][test_givenDistributeCallback_whenFailureIsCaught], [distribute: propagated][test_givenDistributeCallback_whenFailureIsPropagated], [configuration: caught][test_givenConfigurationCallback_whenFailureIsCaught], [configuration: propagated][test_givenConfigurationCallback_whenFailureIsPropagated] |

[test_givenDistributorEnabled_whenAdminRescues]: ./rescue.t.sol#L36
[test_givenActiveDistributor_whenAnyCallerPreviews]: ./rescue.t.sol#L182
[test_givenDistributorRestored_whenSurplusRescued]: ./rescue.t.sol#L1217
[test_givenDistributorEnabled_whenOperatorRescues]: ./rescue.t.sol#L94
[test_givenDistributorDisabled_whenAdminRescues]: ./rescue.t.sol#L50
[test_givenDistributorDisabled_whenOperatorRescues]: ./rescue.t.sol#L108
[test_givenDistributorInactive_whenAdminRescues_reverts]: ./rescue.t.sol#L68
[test_givenInactiveDistributor_whenAnyCallerPreviews_reverts]: ./rescue.t.sol#L201
[test_givenDistributorInactive_whenOperatorRescues_reverts]: ./rescue.t.sol#L126
[test_givenDistributorLifecycle_whenCallerUnauthorized_reverts]: ./rescue.t.sol#L158
[test_givenUnauthorizedIdentities_whenSeeded_reverts]: ./rescue.t.sol#L221
[test_givenTimelockUnavailable_whenAdminRescuesDirectly]: ./rescue.t.sol#L234
[test_givenNeverListedAsset_whenFullCustodyRescued]: ./rescue.t.sol#L257
[test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded]: ./rescue.t.sol#L272
[test_givenZeroCustody_whenEachPermittedCallerRescues]: ./rescue.t.sol#L303
[test_givenOperatorRotated_whenFormerOperatorRescues_reverts]: ./rescue.t.sol#L310
[test_givenOperatorRotated_whenCurrentAuthorityRescues]: ./rescue.t.sol#L328
[test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts]: ./rescue.t.sol#L342
[test_givenOperatorRevoked_whenAdminRescues]: ./rescue.t.sol#L364
[test_givenNeverListedAsset_whenAssetHasNoCode_reverts]: ./rescue.t.sol#L375
[test_givenNeverListedAsset_whenDestinationIsForbidden_reverts]: ./rescue.t.sol#L413
[test_givenActiveAsset_whenSurplusRescueRequested_reverts]: ./rescue.t.sol#L473
[test_givenRetiredAsset_whenSurplusRescueRequested_reverts]: ./rescue.t.sol#L527
[test_givenNeverListedAsset_whenBalanceQueryReverts_reverts]: ./rescue.t.sol#L452
[test_givenNeverListedAsset_whenTransferReverts_reverts]: ./rescue.t.sol#L596
[test_givenNeverListedAsset_whenTransferReturnsFalse_reverts]: ./rescue.t.sol#L601
[test_givenSurplusRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L636
[test_givenSurplusRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L691
[test_givenPendingRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L748
[test_givenPendingRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L803
[test_givenPendingRetryCallback_whenFailureIsCaught]: ./rescue.t.sol#L860
[test_givenPendingRetryCallback_whenFailureIsPropagated]: ./rescue.t.sol#L915
[test_givenDistributeCallback_whenFailureIsCaught]: ./rescue.t.sol#L972
[test_givenDistributeCallback_whenFailureIsPropagated]: ./rescue.t.sol#L1027
[test_givenConfigurationCallback_whenFailureIsCaught]: ./rescue.t.sol#L1084
[test_givenConfigurationCallback_whenFailureIsPropagated]: ./rescue.t.sol#L1139
