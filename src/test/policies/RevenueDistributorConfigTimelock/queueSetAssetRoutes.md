# queueSetAssetRoutes scenario plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: RDT wrapper for RD.setAssetRoutes(asset,repurchaseBps,routes). Store the supplied route on RD. Queueing validates the complete request against current RD state, and execution revalidates live conditions after its state-hash guard.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT Kernel-active, RDT enabled, permitted proposer, selected as RD configOperator, RD Kernel-active and locally enabled. Error order follows that list: own RevenueDistributorConfigTimelock_PolicyNotActive(RDT), NotEnabled(), NotAuthorised(), then selected-operator and target checks. Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: per-asset; expected hash: keccak256(abi.encode(assetDistributionHash(asset), current configOperator)).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `asset_`, `repurchaseBps_` and `routes_` against the complete downstream input rules in [setAssetRoutes](../RevenueDistributor/setAssetRoutes.md). This wrapper uses valid payloads plus one representative invalid request to prove queue-time rejection, then separately covers live drift after a valid queue.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and parameter domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSAR-A01 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | All earlier RDT/operator gates and RD lifecycle valid; fuzz `asset_` as zero/EOA/contract, `repurchaseBps_` as 0/10,000/`type(uint16).max`, and `routes_` as empty/valid/invalid | NotAuthorised() | Queue unchanged | Covered: [fuzzed domain][test_whenCallerHasNoConfigRole_queueReverts], [seed identities][test_whenKnownUnauthorizedIdentitiesQueue_reverts] |

## Lifecycle

Fuzz all three queue parameters across the authorization domain above; they do not affect these guard outcomes.

| ID | Caller | Local active | Local enabled | Selected operator | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-L01 | Fuzz permitted role caller | true | false | Yes | true | true | NotEnabled() | Queue unchanged | Covered: [roles, parameter fuzz and rollback][test_givenTimelockDisabled_whenRouteQueued_reverts] |
| QSAR-L02 | Fuzz permitted role caller | false | true | Yes | true | true | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Queue unchanged | Covered: [roles, parameter fuzz and rollback][test_givenTimelockInactive_whenRouteQueued_reverts] |
| QSAR-L03 | Fuzz permitted role caller | true | true | No | true | true | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [roles, parameter fuzz and rollback][test_givenOperatorRotated_whenRouteQueued_reverts] |
| QSAR-L04 | Fuzz permitted role caller | true | true | Yes | true | false | PolicyDependency_NotActive(RD) | Queue unchanged | Covered: [roles, parameter fuzz and rollback][test_givenTargetDisabled_whenRouteQueued_revertsForEitherRole] |
| QSAR-L05 | Fuzz permitted role caller | true | true | Yes | false | true | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_AdminOnlySeed], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RevenueRoleOnlySeed], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RolesOverlapSeed] |
| QSAR-L06 | Fuzz permitted role caller | true | true | Yes | false | false | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_AdminOnlySeed], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RevenueRoleOnlySeed], [test][test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RolesOverlapSeed] |

## Behavior

| ID | Caller | Prior asset state | `asset_` | `repurchaseBps_` | `routes_` | Execution-time state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-P01 | Fuzz permitted role caller | NeverListed | Valid nonzero contract | 0 | Valid representative nonempty route | Guarded state unchanged | Queue then ready execution succeeds | Exact forwarding; RD becomes Active with requested route | Covered: [test][test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes], [test][test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_AdminOnlySeed], [test][test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_RevenueRoleOnlySeed], [test][test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_RolesOverlapSeed], [operator commitment and restoration][test_whenQueuedRoute_commitsCurrentOperator] |

## Invalid inputs

| ID | Caller | Prior asset state | `asset_` | `repurchaseBps_` | Route-recipient state | Route BPS state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-I01 | Fuzz permitted role caller | Any unchanged state | Valid nonzero contract | 0 | Unique, valid | Total 10,001 | Queue gives RevenueDistributor_InvalidBasisPoints(10001) | No action ID consumed or key acquired; no route mutation | Covered: [test][test_whenRouteBasisPointsExceedMaximum_revertsAtQueue], [test][test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_AdminOnlySeed], [test][test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_RevenueRoleOnlySeed], [test][test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_RolesOverlapSeed] |

## State changes

| ID | Caller | Route/listing after queue | Yield pointer/availability after queue | Custody/debt after queue | Treasury after queue | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-S01 | Fuzz permitted role caller | Same asset route changed | Unchanged | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [test][test_whenRouteChanges_executionRevertsAndRetainsKey], [test][test_whenRouteChanges_executionRevertsAndRetainsKey_AdminOnlySeed], [test][test_whenRouteChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed], [test][test_whenRouteChanges_executionRevertsAndRetainsKey_RolesOverlapSeed] |
| QSAR-S04 | Fuzz permitted role caller | Same asset listing changed | Unchanged | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [test][test_whenListingChanges_executionRevertsAndRetainsKey], [test][test_whenListingChanges_executionRevertsAndRetainsKey_AdminOnlySeed], [test][test_whenListingChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed], [test][test_whenListingChanges_executionRevertsAndRetainsKey_RolesOverlapSeed] |
| QSAR-S05 | Fuzz permitted role caller | Unchanged | Changed | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [test][test_whenYieldPointerChanges_executionRevertsAndRetainsKey], [test][test_whenYieldPointerChanges_executionRevertsAndRetainsKey_AdminOnlySeed], [test][test_whenYieldPointerChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed], [test][test_whenYieldPointerChanges_executionRevertsAndRetainsKey_RolesOverlapSeed] |
| QSAR-S02 | Fuzz permitted role caller | Unchanged | Unchanged | Custody donation only | Unchanged | Expected hash remains valid | Ready execution applies requested route | Covered: [test][test_whenCustodyChangesAfterQueue_executionStillSucceeds], [test][test_whenCustodyChangesAfterQueue_executionStillSucceeds_AdminOnlySeed], [test][test_whenCustodyChangesAfterQueue_executionStillSucceeds_RevenueRoleOnlySeed], [test][test_whenCustodyChangesAfterQueue_executionStillSucceeds_RolesOverlapSeed] |
| QSAR-S06 | Fuzz permitted role caller | Unchanged | Unchanged | Pending debt paid only | Unchanged | Expected hash remains valid | Ready execution applies requested route | Covered: [test][test_whenPendingDebtPaidAfterQueue_executionStillSucceeds], [test][test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_AdminOnlySeed], [test][test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_RevenueRoleOnlySeed], [test][test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_RolesOverlapSeed] |
| QSAR-S07 | Fuzz permitted role caller | Unchanged | Unchanged | Unchanged | Upgraded to non-colliding address | Expected hash remains valid | Ready execution applies requested route using live Treasury validation | Covered: [test][test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds], [test][test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_AdminOnlySeed], [test][test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_RevenueRoleOnlySeed], [test][test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_RolesOverlapSeed] |
| QSAR-S03 | Fuzz permitted role caller | Unchanged | Unchanged | Unchanged | Upgraded to queued configured recipient | Hash unchanged; execution gives RevenueDistributor_InvalidRecipient(newTreasury) | Retain queued action/key; no route, liability or custody mutation | Covered: [test][test_whenQueuedRecipientBecomesTreasury_executionReverts], [test][test_whenQueuedRecipientBecomesTreasury_executionReverts_AdminOnlySeed], [test][test_whenQueuedRecipientBecomesTreasury_executionReverts_RevenueRoleOnlySeed], [test][test_whenQueuedRecipientBecomesTreasury_executionReverts_RolesOverlapSeed] |
| QSAR-S08 | Fuzz permitted role caller | Unchanged; queued repurchase 2,000 BPS | Same pointer; Kernel-active; locally disabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives PolicyDependency_NotActive(yieldRecipient) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [test][test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries], [test][test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_AdminOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_RevenueRoleOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_RolesOverlapSeed] |
| QSAR-S09 | Fuzz permitted role caller | Unchanged; queued repurchase 2,000 BPS | Same pointer; Kernel-inactive; locally enabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives PolicyDependency_NotActive(yieldRecipient) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [test][test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries], [test][test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_AdminOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_RevenueRoleOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_RolesOverlapSeed] |
| QSAR-S10 | Fuzz permitted role caller | Unchanged; queued repurchase 2,000 BPS | Same pointer; active/enabled; asset registration disabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives RevenueDistributor_YieldRecipientUnavailable(yieldRecipient,asset) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [test][test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries], [test][test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_AdminOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_RevenueRoleOnlySeed], [test][test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_RolesOverlapSeed] |

## Queue conflicts

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSAR-Q01 | Fuzz permitted role caller | Conflict with existing per-asset action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [test][test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts], [test][test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_AdminOnlySeed], [test][test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_RevenueRoleOnlySeed], [test][test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_RolesOverlapSeed] |

[test_whenCallerHasNoConfigRole_queueReverts]: ./queueSetAssetRoutes.t.sol#L144
[test_whenKnownUnauthorizedIdentitiesQueue_reverts]: ./queueSetAssetRoutes.t.sol#L165
[test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes]: ./queueSetAssetRoutes.t.sol#L320
[test_givenTimelockDisabled_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L175
[test_givenTimelockInactive_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L198
[test_givenOperatorRotated_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L228
[test_givenTargetDisabled_whenRouteQueued_revertsForEitherRole]: ./queueSetAssetRoutes.t.sol#L257
[test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState]: ./queueSetAssetRoutes.t.sol#L285
[test_whenRouteBasisPointsExceedMaximum_revertsAtQueue]: ./queueSetAssetRoutes.t.sol#L94
[test_whenRouteChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L431
[test_whenListingChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L466
[test_whenYieldPointerChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L499
[test_whenCustodyChangesAfterQueue_executionStillSucceeds]: ./queueSetAssetRoutes.t.sol#L532
[test_whenPendingDebtPaidAfterQueue_executionStillSucceeds]: ./queueSetAssetRoutes.t.sol#L557
[test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds]: ./queueSetAssetRoutes.t.sol#L592
[test_whenQueuedRecipientBecomesTreasury_executionReverts]: ./queueSetAssetRoutes.t.sol#L616
[test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts]: ./queueSetAssetRoutes.t.sol#L645
[test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L752
[test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L781
[test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L810
[test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L957
[test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L975
[test_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L993
[test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1250
[test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1262
[test_whenValidNonemptyRouteQueued_storesExactActionAndExecutes_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1276
[test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1169
[test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1174
[test_whenRouteBasisPointsExceedMaximum_revertsAtQueue_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1179
[test_whenRouteChanges_executionRevertsAndRetainsKey_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1184
[test_whenRouteChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1194
[test_whenRouteChanges_executionRevertsAndRetainsKey_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1204
[test_whenListingChanges_executionRevertsAndRetainsKey_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1077
[test_whenListingChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1087
[test_whenListingChanges_executionRevertsAndRetainsKey_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1097
[test_whenYieldPointerChanges_executionRevertsAndRetainsKey_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1290
[test_whenYieldPointerChanges_executionRevertsAndRetainsKey_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1300
[test_whenYieldPointerChanges_executionRevertsAndRetainsKey_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1312
[test_whenCustodyChangesAfterQueue_executionStillSucceeds_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1044
[test_whenCustodyChangesAfterQueue_executionStillSucceeds_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1055
[test_whenCustodyChangesAfterQueue_executionStillSucceeds_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1066
[test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1107
[test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1117
[test_whenPendingDebtPaidAfterQueue_executionStillSucceeds_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1129
[test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1214
[test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1226
[test_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1238
[test_whenQueuedRecipientBecomesTreasury_executionReverts_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1139
[test_whenQueuedRecipientBecomesTreasury_executionReverts_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1149
[test_whenQueuedRecipientBecomesTreasury_executionReverts_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1159
[test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L879
[test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L892
[test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L905
[test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L918
[test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L931
[test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L944
[test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L840
[test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L853
[test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L866
[test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_AdminOnlySeed]: ./queueSetAssetRoutes.t.sol#L1011
[test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_RevenueRoleOnlySeed]: ./queueSetAssetRoutes.t.sol#L1022
[test_whenAssetKeyAlreadyOwned_secondRouteQueueReverts_RolesOverlapSeed]: ./queueSetAssetRoutes.t.sol#L1033

[test_whenQueuedRoute_commitsCurrentOperator]: ./queueSetAssetRoutes.t.sol#L1322
