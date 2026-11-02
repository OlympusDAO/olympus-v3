# RevenueDistributor.rescue coverage plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: RD's surplus rescue and co-located preview assertions. RD = RevenueDistributor. Each row links to tests with reciprocal Scenarios comments.

Local disablement retains admin/current operator recovery. A disabled timelock blocks its queues and execution; admin can call RD directly. Kernel inactivity rejects preview and execution.

## Domains and assertions

Normalized scenario scope: `RD-RESCUE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

- Admin = ADMIN_ROLE holder; Operator = current nonzero configOperator. Test these separately. Unauthorized callers include zero, emergency-only, revenue_distributor_admin-only and former operator unless independently authorized.
- Default: RD enabled and Kernel-active; NeverListed token, unrelated valid destination. Preview and execution allow local disablement but require Kernel activity. Preview is permissionless and is checked beside each action case.
- Only NeverListed assets qualify. Active and Retired assets remain managed, including when their pending debt is zero. Supported public flows create debt only after listing, so a successful NeverListed rescue has no pending debt and sends the full live token balance B.
- Amounts are token base units; MAX=uint256 maximum. There is no amount parameter. Ordinary B=19. Permitted destinations include Treasury, current operator and an unrelated address; forbidden destinations are zero, Kernel, RD and the asset itself.
- Positive payment: preview=B; custody falls by B, destination rises by B. Assert exactly one token Transfer then one RD AssetRescued(asset,destination,B). Routes, listing, raw pending Treasury/yield/configured-recipient debts, aggregates, retry indexes, operator and other assets remain unchanged.
- No-op: B=0; preview=0; no token call or rescue/transfer event, including if transfers would reject. Unchanged: balances and all those states unchanged; no committed events. Errors omit RevenueDistributor_. InvalidRescueDestination includes zero.

## Scenario setup

Every success row uses B=19 and destination starting balance=7, ending with RD custody=0 and destination=26. Active previews return 19; inactive previews revert PolicyInactive(), independently of caller authorization.

## Authorization

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| RD-RESCUE-L01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | true | true | Pay 19; shared success assertions | Covered: [test][test_givenDistributorEnabled_whenAdminRescues], [test][test_givenActiveDistributor_whenAnyCallerPreviews], [test][test_givenDistributorRestored_whenSurplusRescued], [test][test_givenDistributorEnabled_whenOperatorRescues], [test][test_givenDistributorEnabled_whenAdminRescues_AdminOnlySeed], [test][test_givenDistributorEnabled_whenAdminRescues_OperatorOnlySeed], [test][test_givenDistributorEnabled_whenAdminRescues_RolesOverlapSeed], [test][test_givenDistributorRestored_whenSurplusRescued_AdminOnlySeed], [test][test_givenDistributorRestored_whenSurplusRescued_OperatorOnlySeed], [test][test_givenDistributorRestored_whenSurplusRescued_RolesOverlapSeed], [test][test_givenDistributorEnabled_whenOperatorRescues_AdminOnlySeed], [test][test_givenDistributorEnabled_whenOperatorRescues_OperatorOnlySeed], [test][test_givenDistributorEnabled_whenOperatorRescues_RolesOverlapSeed] |
| RD-RESCUE-L03 | Fuzz callers excluding every ADMIN_ROLE holder and selected current configOperator | true | true | UnauthorizedConfigOperator(caller); Unchanged | Covered: [fuzzed callers][test_givenActiveDistributor_whenCallerUnauthorized_reverts], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [caller identities][test_givenUnauthorizedIdentities_whenSeeded_reverts] |
| RD-RESCUE-L04 | Fuzz callers excluding every ADMIN_ROLE holder and selected current configOperator | false | true | RevenueDistributor_PolicyNotActive(RD) before caller and input checks; Unchanged | Covered: [fuzzed callers][test_givenInactiveDistributor_whenCallerUnauthorized_reverts], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [caller identities][test_givenInactiveUnauthorizedIdentities_whenSeeded_reverts] |
| RD-RESCUE-L05 | Fuzz callers excluding every ADMIN_ROLE holder and selected current configOperator | true | false | UnauthorizedConfigOperator(caller); Unchanged | Covered: [fuzzed callers][test_givenActiveDistributor_whenCallerUnauthorized_reverts], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [caller identities][test_givenUnauthorizedIdentities_whenSeeded_reverts] |
| RD-RESCUE-L06 | Fuzz callers excluding every ADMIN_ROLE holder and selected current configOperator | false | false | RevenueDistributor_PolicyNotActive(RD) before caller and input checks; Unchanged | Covered: [fuzzed callers][test_givenInactiveDistributor_whenCallerUnauthorized_reverts], [fuzz][test_givenActiveDistributor_whenAnyCallerPreviews], [fuzz][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [caller identities][test_givenInactiveUnauthorizedIdentities_whenSeeded_reverts] |
| RD-RESCUE-A01 | ADMIN_ROLE holder | true | true | Pay 19 directly; one transfer and AssetRescued; no timelock action created | Covered: [admin rescues directly][test_givenTimelockUnavailable_whenAdminRescuesDirectly] |
| RD-RESCUE-A02 | ADMIN_ROLE holder | true | false | Pay 19 directly; one transfer and AssetRescued; no timelock action created | Covered: [admin rescues directly][test_givenTimelockUnavailable_whenAdminRescuesDirectly] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| RD-RESCUE-L07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | true | false | Pay 19; shared success assertions | Covered: [test][test_givenDistributorDisabled_whenAdminRescues], [test][test_givenActiveDistributor_whenAnyCallerPreviews], [test][test_givenDistributorDisabled_whenOperatorRescues], [test][test_givenDistributorDisabled_whenAdminRescues_AdminOnlySeed], [test][test_givenDistributorDisabled_whenAdminRescues_OperatorOnlySeed], [test][test_givenDistributorDisabled_whenAdminRescues_RolesOverlapSeed], [test][test_givenDistributorDisabled_whenOperatorRescues_AdminOnlySeed], [test][test_givenDistributorDisabled_whenOperatorRescues_OperatorOnlySeed], [test][test_givenDistributorDisabled_whenOperatorRescues_RolesOverlapSeed] |
| RD-RESCUE-L09 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | false | true | PolicyInactive(); Unchanged | Covered: [test][test_givenDistributorInactive_whenAdminRescues_reverts], [test][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [test][test_givenDistributorInactive_whenOperatorRescues_reverts], [test][test_givenDistributorInactive_whenAdminRescues_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenAdminRescues_reverts_OperatorOnlySeed], [test][test_givenDistributorInactive_whenAdminRescues_reverts_RolesOverlapSeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_OperatorOnlySeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_RolesOverlapSeed] |
| RD-RESCUE-L10 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | false | false | PolicyInactive(); Unchanged | Covered: [test][test_givenDistributorInactive_whenAdminRescues_reverts], [test][test_givenInactiveDistributor_whenAnyCallerPreviews_reverts], [test][test_givenDistributorInactive_whenOperatorRescues_reverts], [test][test_givenDistributorInactive_whenAdminRescues_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenAdminRescues_reverts_OperatorOnlySeed], [test][test_givenDistributorInactive_whenAdminRescues_reverts_RolesOverlapSeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_OperatorOnlySeed], [test][test_givenDistributorInactive_whenOperatorRescues_reverts_RolesOverlapSeed] |

Check competing faults separately: own inactivity wins over caller authorization and asset=0; while active, unauthorized callers fail before asset validation. Inactive preview also gets PolicyInactive before input validation. No re-enabled/reactivated history rows.

## Surplus and isolation

| ID | Caller | State / inputs / boundaries | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| RD-RESCUE-P01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | NeverListed; fuzz B=1..MAX; seed 1, MAX−1, MAX; fuzz valid destination and guarantee Treasury/operator/unrelated identities | B | Full payment; include zero/nonzero destination starting balance within total-supply budget | Covered: [test][test_givenNeverListedAsset_whenFullCustodyRescued], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded], [test][test_givenNeverListedAsset_whenFullCustodyRescued_AdminOnlySeed], [test][test_givenNeverListedAsset_whenFullCustodyRescued_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenFullCustodyRescued_RolesOverlapSeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_AdminOnlySeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_RolesOverlapSeed] |
| RD-RESCUE-P03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | NeverListed; B=0; transfer rejects if called | 0 | No-op; Unchanged | Covered: [test][test_givenZeroCustody_whenEachPermittedCallerRescues], [test][test_givenZeroCustody_whenEachPermittedCallerRescues_AdminOnlySeed], [test][test_givenZeroCustody_whenEachPermittedCallerRescues_OperatorOnlySeed], [test][test_givenZeroCustody_whenEachPermittedCallerRescues_RolesOverlapSeed] |
| RD-RESCUE-P05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | NeverListed token alongside another managed asset with Treasury, yield-recipient and three configured-recipient debts | Selected B | Only selected custody moves; other raw debts/aggregate/indexes/balances/routes preserved | Covered: [test][test_givenNeverListedAsset_whenFullCustodyRescued], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded], [test][test_givenNeverListedAsset_whenFullCustodyRescued_AdminOnlySeed], [test][test_givenNeverListedAsset_whenFullCustodyRescued_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenFullCustodyRescued_RolesOverlapSeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_AdminOnlySeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_RolesOverlapSeed] |
| RD-RESCUE-A03 | ADMIN_ROLE holder | Config operator rotated or revoked; B=19 | 19 | Pay 19; admin authority retained | Covered: [test][test_givenOperatorRotated_whenCurrentAuthorityRescues], [test][test_givenOperatorRevoked_whenAdminRescues] |
| RD-RESCUE-P07 | Selected new nonzero configOperator without ADMIN_ROLE | Rotation complete; B=19 | 19 | Pay 19; exact transfer and AssetRescued event | Covered: [test][test_givenOperatorRotated_whenCurrentAuthorityRescues] |
| RD-RESCUE-P08 | Former configOperator without ADMIN_ROLE | Rotation or revocation complete; B=19 | 19 (permissionless preview) | RevenueDistributor_UnauthorizedConfigOperator(caller); unchanged; no transfer/logs | Covered: [test][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [test][test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts] |

## Invalid inputs

Run each permitted caller separately with RD Kernel-active and enabled or disabled. Co-locate exact preview and execution errors, plus Unchanged assertions.

| ID | Caller | State / invalid input | Preview / execution | Test |
| --- | --- | --- | --- | --- |
| RD-RESCUE-I01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | asset=0; valid destination | InvalidAsset(asset) | Covered: [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_RolesOverlapSeed] |
| RD-RESCUE-I02 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Nonzero EOA asset; valid destination | InvalidAsset(asset) | Covered: [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenAssetHasNoCode_reverts_RolesOverlapSeed] |
| RD-RESCUE-I05 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=0; valid asset; seed B=0, 1, MAX | InvalidRescueDestination(destination) | Covered: [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed] |
| RD-RESCUE-I06 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=Kernel; valid asset; seed B=0, 1, MAX | InvalidRescueDestination(destination) | Covered: [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed] |
| RD-RESCUE-I07 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=RD; valid asset; seed B=0, 1, MAX | InvalidRescueDestination(destination) | Covered: [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed] |
| RD-RESCUE-I08 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | destination=asset; valid asset; seed B=0, 1, MAX | InvalidRescueDestination(destination) | Covered: [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed] |
| RD-RESCUE-I13 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Active asset; seed B=0 with no debt, B=R−1 and B=R with nonzero pending Treasury/yield/configured debts, and B=R+5 | AssetManaged(asset); Unchanged | Covered: [test][test_givenActiveAsset_whenSurplusRescueRequested_reverts], [test][test_givenActiveAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed], [test][test_givenActiveAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed], [test][test_givenActiveAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed] |
| RD-RESCUE-I15 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Retired asset; same explicit custody/debt constructions as RD-RESCUE-I13 | AssetManaged(asset); Unchanged | Covered: [test][test_givenRetiredAsset_whenSurplusRescueRequested_reverts], [test][test_givenRetiredAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed], [test][test_givenRetiredAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed], [test][test_givenRetiredAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed] |
| RD-RESCUE-I17 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | Valid-code NeverListed token with controlled balanceOf failure | Exact dependency error; Unchanged | Covered: [test][test_givenNeverListedAsset_whenBalanceQueryReverts_reverts], [test][test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_RolesOverlapSeed] |

Address validation precedes listing validation, which precedes balanceOf. Preserve that order with asset=0 plus forbidden destination, and managed asset plus forbidden destination. Do not fabricate pending-debt combinations for NeverListed tokens.

## Transfers

Use NeverListed B=19 and existing destination balance=7; seed an unrelated managed asset's debts. Preview=19 for both failures.

| ID | Caller | Transfer behavior | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-RESCUE-T01 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | transfer reverts with controlled custom error | Bubble exact token error; Unchanged | Covered: [test][test_givenNeverListedAsset_whenTransferReverts_reverts], [test][test_givenNeverListedAsset_whenTransferReverts_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenTransferReverts_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenTransferReverts_reverts_RolesOverlapSeed] |
| RD-RESCUE-T03 | Fuzz ADMIN-only, selected configOperator-only and overlapping authority; seed each | transfer returns false | SafeERC20FailedOperation(asset); Unchanged | Covered: [test][test_givenNeverListedAsset_whenTransferReturnsFalse_reverts], [test][test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_AdminOnlySeed], [test][test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_OperatorOnlySeed], [test][test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_RolesOverlapSeed] |

## Callbacks

Nested requests must be independently authorized and otherwise valid, so they reach the intended guard.

| ID | Caller | Callback | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| RD-RESCUE-C01 | Fuzz ADMIN-only, selected configOperator-only and overlap callers; seed each | Reenter surplus rescue; independently seed same/different allowed token; callback catches failure | Nested ReentrancyGuardReentrantCall(); one outer payment; no nested mutation; post-transfer preview reflects actual remaining balance | Covered: [test][test_givenSurplusRescueCallback_whenFailureIsCaught], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsCaught_RolesOverlapSeed] |
| RD-RESCUE-C05 | Fuzz ADMIN-only, selected configOperator-only and overlap callers; seed each | Reenter surplus rescue; independently seed same/different allowed token; callback propagates failure | Outer token CallbackFailed(); entire transaction rolls back, including balances, indexes, liabilities, configuration and committed logs | Covered: [test][test_givenSurplusRescueCallback_whenFailureIsPropagated], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenSurplusRescueCallback_whenFailureIsPropagated_RolesOverlapSeed] |
| RD-RESCUE-C03 | Fuzz ADMIN-only, selected configOperator-only and overlap callers; seed each | Otherwise eligible guarded pending rescue/retry/distribute/configuration; independently seed each named route; callback catches failure | Nested ReentrancyGuardReentrantCall(); one outer payment; no nested mutation; post-transfer preview reflects actual remaining balance | Covered: [test][test_givenPendingRescueCallback_whenFailureIsCaught], [test][test_givenPendingRetryCallback_whenFailureIsCaught], [test][test_givenDistributeCallback_whenFailureIsCaught], [test][test_givenConfigurationCallback_whenFailureIsCaught], [test][test_givenPendingRescueCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenDistributeCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenDistributeCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenDistributeCallback_whenFailureIsCaught_RolesOverlapSeed], [test][test_givenConfigurationCallback_whenFailureIsCaught_AdminOnlySeed], [test][test_givenConfigurationCallback_whenFailureIsCaught_OperatorOnlySeed], [test][test_givenConfigurationCallback_whenFailureIsCaught_RolesOverlapSeed] |
| RD-RESCUE-C06 | Fuzz ADMIN-only, selected configOperator-only and overlap callers; seed each | Otherwise eligible guarded pending rescue/retry/distribute/configuration; independently seed each named route; callback propagates failure | Outer token CallbackFailed(); entire transaction rolls back, including balances, indexes, liabilities, configuration and committed logs | Covered: [test][test_givenPendingRescueCallback_whenFailureIsPropagated], [test][test_givenPendingRetryCallback_whenFailureIsPropagated], [test][test_givenDistributeCallback_whenFailureIsPropagated], [test][test_givenConfigurationCallback_whenFailureIsPropagated], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenPendingRescueCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenPendingRetryCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenDistributeCallback_whenFailureIsPropagated_RolesOverlapSeed], [test][test_givenConfigurationCallback_whenFailureIsPropagated_AdminOnlySeed], [test][test_givenConfigurationCallback_whenFailureIsPropagated_OperatorOnlySeed], [test][test_givenConfigurationCallback_whenFailureIsPropagated_RolesOverlapSeed] |

[test_givenDistributorEnabled_whenAdminRescues]: ./rescue.t.sol#L38
[test_givenActiveDistributor_whenAnyCallerPreviews]: ./rescue.t.sol#L245
[test_givenDistributorRestored_whenSurplusRescued]: ./rescue.t.sol#L1071
[test_givenDistributorEnabled_whenOperatorRescues]: ./rescue.t.sol#L115
[test_givenDistributorDisabled_whenAdminRescues]: ./rescue.t.sol#L58
[test_givenDistributorDisabled_whenOperatorRescues]: ./rescue.t.sol#L135
[test_givenDistributorInactive_whenAdminRescues_reverts]: ./rescue.t.sol#L82
[test_givenInactiveDistributor_whenAnyCallerPreviews_reverts]: ./rescue.t.sol#L263
[test_givenDistributorInactive_whenOperatorRescues_reverts]: ./rescue.t.sol#L159
[test_givenActiveDistributor_whenCallerUnauthorized_reverts]: ./rescue.t.sol#L198
[test_givenUnauthorizedIdentities_whenSeeded_reverts]: ./rescue.t.sol#L284
[test_givenTimelockUnavailable_whenAdminRescuesDirectly]: ./rescue.t.sol#L297
[test_givenNeverListedAsset_whenFullCustodyRescued]: ./rescue.t.sol#L326
[test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded]: ./rescue.t.sol#L346
[test_givenZeroCustody_whenEachPermittedCallerRescues]: ./rescue.t.sol#L383
[test_givenOperatorRotated_whenFormerOperatorRescues_reverts]: ./rescue.t.sol#L396
[test_givenOperatorRotated_whenCurrentAuthorityRescues]: ./rescue.t.sol#L414
[test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts]: ./rescue.t.sol#L428
[test_givenOperatorRevoked_whenAdminRescues]: ./rescue.t.sol#L450
[test_givenNeverListedAsset_whenAssetHasNoCode_reverts]: ./rescue.t.sol#L461
[test_givenNeverListedAsset_whenDestinationIsForbidden_reverts]: ./rescue.t.sol#L504
[test_givenActiveAsset_whenSurplusRescueRequested_reverts]: ./rescue.t.sol#L574
[test_givenRetiredAsset_whenSurplusRescueRequested_reverts]: ./rescue.t.sol#L632
[test_givenNeverListedAsset_whenBalanceQueryReverts_reverts]: ./rescue.t.sol#L548
[test_givenNeverListedAsset_whenTransferReverts_reverts]: ./rescue.t.sol#L705
[test_givenNeverListedAsset_whenTransferReturnsFalse_reverts]: ./rescue.t.sol#L723
[test_givenSurplusRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L758
[test_givenSurplusRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L787
[test_givenPendingRescueCallback_whenFailureIsCaught]: ./rescue.t.sol#L818
[test_givenPendingRescueCallback_whenFailureIsPropagated]: ./rescue.t.sol#L846
[test_givenPendingRetryCallback_whenFailureIsCaught]: ./rescue.t.sol#L876
[test_givenPendingRetryCallback_whenFailureIsPropagated]: ./rescue.t.sol#L904
[test_givenDistributeCallback_whenFailureIsCaught]: ./rescue.t.sol#L934
[test_givenDistributeCallback_whenFailureIsPropagated]: ./rescue.t.sol#L962
[test_givenConfigurationCallback_whenFailureIsCaught]: ./rescue.t.sol#L992
[test_givenConfigurationCallback_whenFailureIsPropagated]: ./rescue.t.sol#L1020

## Additional existing test evidence

- [test_givenOperatorRotated_whenFormerOperatorRescues_reverts][test_givenOperatorRotated_whenFormerOperatorRescues_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenOperatorRotated_whenCurrentAuthorityRescues][test_givenOperatorRotated_whenCurrentAuthorityRescues] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts][test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenOperatorRevoked_whenAdminRescues][test_givenOperatorRevoked_whenAdminRescues] — existing regression evidence; review generators and assertions before mapping the expanded cases.

Retired duplicate caller IDs: RD-RESCUE-C02, RD-RESCUE-C04. Equivalent caller classes now share each caught/propagated outcome; retain exclusive and overlapping authority seeds.

Retired duplicate caller IDs: RD-RESCUE-L02, RD-RESCUE-L08, RD-RESCUE-L11, RD-RESCUE-L12, RD-RESCUE-P02, RD-RESCUE-P04, RD-RESCUE-P06, RD-RESCUE-I03, RD-RESCUE-I04, RD-RESCUE-I09, RD-RESCUE-I10, RD-RESCUE-I11, RD-RESCUE-I12, RD-RESCUE-I14, RD-RESCUE-I16, RD-RESCUE-I18, RD-RESCUE-T02, RD-RESCUE-T04. Retained caller families include explicit exclusive-role and overlapping-role seeds.

[test_givenDistributorEnabled_whenAdminRescues_AdminOnlySeed]: ./rescue.t.sol#L1239

[test_givenDistributorEnabled_whenAdminRescues_OperatorOnlySeed]: ./rescue.t.sol#L1244

[test_givenDistributorEnabled_whenAdminRescues_RolesOverlapSeed]: ./rescue.t.sol#L1249

[test_givenDistributorRestored_whenSurplusRescued_AdminOnlySeed]: ./rescue.t.sol#L1299

[test_givenDistributorRestored_whenSurplusRescued_OperatorOnlySeed]: ./rescue.t.sol#L1304

[test_givenDistributorRestored_whenSurplusRescued_RolesOverlapSeed]: ./rescue.t.sol#L1309

[test_givenDistributorEnabled_whenOperatorRescues_AdminOnlySeed]: ./rescue.t.sol#L1254

[test_givenDistributorEnabled_whenOperatorRescues_OperatorOnlySeed]: ./rescue.t.sol#L1259

[test_givenDistributorEnabled_whenOperatorRescues_RolesOverlapSeed]: ./rescue.t.sol#L1264

[test_givenDistributorDisabled_whenAdminRescues_AdminOnlySeed]: ./rescue.t.sol#L1209

[test_givenDistributorDisabled_whenAdminRescues_OperatorOnlySeed]: ./rescue.t.sol#L1214

[test_givenDistributorDisabled_whenAdminRescues_RolesOverlapSeed]: ./rescue.t.sol#L1219

[test_givenDistributorDisabled_whenOperatorRescues_AdminOnlySeed]: ./rescue.t.sol#L1224

[test_givenDistributorDisabled_whenOperatorRescues_OperatorOnlySeed]: ./rescue.t.sol#L1229

[test_givenDistributorDisabled_whenOperatorRescues_RolesOverlapSeed]: ./rescue.t.sol#L1234

[test_givenDistributorInactive_whenAdminRescues_reverts_AdminOnlySeed]: ./rescue.t.sol#L1269

[test_givenDistributorInactive_whenAdminRescues_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1274

[test_givenDistributorInactive_whenAdminRescues_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1279

[test_givenDistributorInactive_whenOperatorRescues_reverts_AdminOnlySeed]: ./rescue.t.sol#L1284

[test_givenDistributorInactive_whenOperatorRescues_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1289

[test_givenDistributorInactive_whenOperatorRescues_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1294

[test_givenNeverListedAsset_whenFullCustodyRescued_AdminOnlySeed]: ./rescue.t.sol#L1386

[test_givenNeverListedAsset_whenFullCustodyRescued_OperatorOnlySeed]: ./rescue.t.sol#L1391

[test_givenNeverListedAsset_whenFullCustodyRescued_RolesOverlapSeed]: ./rescue.t.sol#L1396

[test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_AdminOnlySeed]: ./rescue.t.sol#L1344

[test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_OperatorOnlySeed]: ./rescue.t.sol#L1349

[test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_RolesOverlapSeed]: ./rescue.t.sol#L1356

[test_givenZeroCustody_whenEachPermittedCallerRescues_AdminOnlySeed]: ./rescue.t.sol#L1536

[test_givenZeroCustody_whenEachPermittedCallerRescues_OperatorOnlySeed]: ./rescue.t.sol#L1541

[test_givenZeroCustody_whenEachPermittedCallerRescues_RolesOverlapSeed]: ./rescue.t.sol#L1546

[test_givenNeverListedAsset_whenAssetHasNoCode_reverts_AdminOnlySeed]: ./rescue.t.sol#L1314

[test_givenNeverListedAsset_whenAssetHasNoCode_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1319

[test_givenNeverListedAsset_whenAssetHasNoCode_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1324

[test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed]: ./rescue.t.sol#L1363

[test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1372

[test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1379

[test_givenActiveAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed]: ./rescue.t.sol#L1134

[test_givenActiveAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1139

[test_givenActiveAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1144

[test_givenRetiredAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed]: ./rescue.t.sol#L1491

[test_givenRetiredAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1496

[test_givenRetiredAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1501

[test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_AdminOnlySeed]: ./rescue.t.sol#L1329

[test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1334

[test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1339

[test_givenNeverListedAsset_whenTransferReverts_reverts_AdminOnlySeed]: ./rescue.t.sol#L1416

[test_givenNeverListedAsset_whenTransferReverts_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1421

[test_givenNeverListedAsset_whenTransferReverts_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1426

[test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_AdminOnlySeed]: ./rescue.t.sol#L1401

[test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_OperatorOnlySeed]: ./rescue.t.sol#L1406

[test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_RolesOverlapSeed]: ./rescue.t.sol#L1411

[test_givenSurplusRescueCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescue.t.sol#L1506

[test_givenSurplusRescueCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescue.t.sol#L1511

[test_givenSurplusRescueCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescue.t.sol#L1516

[test_givenSurplusRescueCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescue.t.sol#L1521

[test_givenSurplusRescueCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescue.t.sol#L1526

[test_givenSurplusRescueCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescue.t.sol#L1531

[test_givenPendingRescueCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescue.t.sol#L1431

[test_givenPendingRescueCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescue.t.sol#L1436

[test_givenPendingRescueCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescue.t.sol#L1441

[test_givenPendingRetryCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescue.t.sol#L1461

[test_givenPendingRetryCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescue.t.sol#L1466

[test_givenPendingRetryCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescue.t.sol#L1471

[test_givenDistributeCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescue.t.sol#L1179

[test_givenDistributeCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescue.t.sol#L1184

[test_givenDistributeCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescue.t.sol#L1189

[test_givenConfigurationCallback_whenFailureIsCaught_AdminOnlySeed]: ./rescue.t.sol#L1149

[test_givenConfigurationCallback_whenFailureIsCaught_OperatorOnlySeed]: ./rescue.t.sol#L1154

[test_givenConfigurationCallback_whenFailureIsCaught_RolesOverlapSeed]: ./rescue.t.sol#L1159

[test_givenPendingRescueCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescue.t.sol#L1446

[test_givenPendingRescueCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescue.t.sol#L1451

[test_givenPendingRescueCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescue.t.sol#L1456

[test_givenPendingRetryCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescue.t.sol#L1476

[test_givenPendingRetryCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescue.t.sol#L1481

[test_givenPendingRetryCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescue.t.sol#L1486

[test_givenDistributeCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescue.t.sol#L1194

[test_givenDistributeCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescue.t.sol#L1199

[test_givenDistributeCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescue.t.sol#L1204

[test_givenConfigurationCallback_whenFailureIsPropagated_AdminOnlySeed]: ./rescue.t.sol#L1164

[test_givenConfigurationCallback_whenFailureIsPropagated_OperatorOnlySeed]: ./rescue.t.sol#L1169

[test_givenConfigurationCallback_whenFailureIsPropagated_RolesOverlapSeed]: ./rescue.t.sol#L1174

[test_givenInactiveDistributor_whenCallerUnauthorized_reverts]: ./rescue.t.sol#L221

[test_givenInactiveUnauthorizedIdentities_whenSeeded_reverts]: ./rescue.t.sol#L1551
