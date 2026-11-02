# queueDisableAssetRoutes scenario plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: RDT wrapper for RD.disableAssetRoutes(asset). Retire a requested Active asset. Queueing validates that the asset is Active, and execution rejects guarded state drift before forwarding the request.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT Kernel-active, RDT enabled, permitted proposer, selected as RD configOperator, RD Kernel-active and locally enabled. Error order follows that list: own RevenueDistributorConfigTimelock_PolicyNotActive(RDT), NotEnabled(), NotAuthorised(), then selected-operator and target checks. Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: per-asset; expected hash: assetDistributionHash(asset).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `asset_` activity against the same rule documented in [disableAssetRoutes](../RevenueDistributor/disableAssetRoutes.md). Execution still protects against a once-valid asset changing after queueing.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and `asset_` domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QDAR-A01 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | All earlier RDT/operator gates and RD lifecycle valid; fuzz `asset_` as zero, EOA, NeverListed, Active and Retired | NotAuthorised() | Queue unchanged | Covered: [evidence][test_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle

Fuzz `asset_` across the authorization domain above; it does not affect these guard outcomes.

| ID | Caller | Local active | Local enabled | Selected operator | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-L01 | Fuzz permitted role caller | true | false | Yes | true | true | NotEnabled() | Queue unchanged | Covered: [evidence][test_givenTimelockDisabled_whenQueued_reverts] |
| QDAR-L02 | Fuzz permitted role caller | false | true | Yes | true | true | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Queue unchanged | Covered: [evidence][test_givenTimelockInactive_whenQueued_reverts] |
| QDAR-L03 | Fuzz permitted role caller | true | true | No | true | true | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [evidence][test_givenOperatorRotated_whenQueued_reverts] |
| QDAR-L04 | Fuzz permitted role caller | true | true | Yes | true | false | PolicyDependency_NotActive(RD) | Queue unchanged | Covered: [evidence][test_givenDistributorDisabled_whenQueued_reverts] |
| QDAR-L05 | Fuzz permitted role caller | true | true | Yes | false | true | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenDistributorInactive_whenQueued_reverts], [test][test_givenDistributorInactive_whenQueued_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenQueued_reverts_RevenueRoleOnlySeed], [test][test_givenDistributorInactive_whenQueued_reverts_RolesOverlapSeed] |
| QDAR-L06 | Fuzz permitted role caller | true | true | Yes | false | false | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenDistributorInactive_whenQueued_reverts], [test][test_givenDistributorInactive_whenQueued_reverts_AdminOnlySeed], [test][test_givenDistributorInactive_whenQueued_reverts_RevenueRoleOnlySeed], [test][test_givenDistributorInactive_whenQueued_reverts_RolesOverlapSeed] |

## Behavior

| ID | Caller | Asset state at queue | Route state | Pending bucket mask | Asset state at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-P01 | Fuzz permitted role caller | Active | Representative nonempty route | Representative nonempty debt | Unchanged | Queue then ready execution succeeds | Exact forwarding; retire route; pending debt preserved | Covered: [test][test_whenActiveAssetDisableQueues_executesAfterDelay], [test][test_whenActiveAssetDisableQueues_executesAfterDelay_AdminOnlySeed], [test][test_whenActiveAssetDisableQueues_executesAfterDelay_RevenueRoleOnlySeed], [test][test_whenActiveAssetDisableQueues_executesAfterDelay_RolesOverlapSeed], [test][test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt], [test][test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_AdminOnlySeed], [test][test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_RevenueRoleOnlySeed], [test][test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_RolesOverlapSeed] |

## Invalid inputs

| ID | Caller | `asset_` kind | Asset state at queue | Asset state at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-I01 | Fuzz permitted role caller | Fuzz zero, EOA, contract | NeverListed | No execution | Queue gives RevenueDistributor_AssetNotActive(asset) | No action ID consumed or key acquired; no route/state mutation | Covered: [test][test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue], [test][test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed], [test][test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed], [test][test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed], [test][test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue], [test][test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed], [test][test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed], [test][test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed] |
| QDAR-I02 | Fuzz permitted role caller | Nonzero contract | Retired | No execution | Queue gives RevenueDistributor_AssetNotActive(asset) | No action ID consumed or key acquired; pending debt and retired state unchanged | Covered: [test][test_givenRetiredAsset_whenDisableQueued_revertsAtQueue], [test][test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed], [test][test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed], [test][test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed] |

## State changes

| ID | Caller | Queued asset state | Post-queue route state | Post-queue listing state | Post-queue yield pointer | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-S01 | Fuzz permitted role caller | Active | Changed | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key and action | Covered: [test][test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey], [test][test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_AdminOnlySeed], [test][test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_RevenueRoleOnlySeed], [test][test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_RolesOverlapSeed] |
| QDAR-S02 | Fuzz permitted role caller | Active | Cleared by direct Active→Retired transition | Active→Retired | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged before downstream execution | Failed execution retains key and action; the independently committed retirement remains | Covered: [test][test_whenAssetRetiredAfterQueue_executionReverts], [test][test_whenAssetRetiredAfterQueue_executionReverts_AdminOnlySeed], [test][test_whenAssetRetiredAfterQueue_executionReverts_RevenueRoleOnlySeed], [test][test_whenAssetRetiredAfterQueue_executionReverts_RolesOverlapSeed] |
| QDAR-S03 | Fuzz permitted role caller | Active | Unchanged | Unchanged | Changed | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key and action | Covered: [test][test_whenYieldPointerChangesAfterQueue_executionReverts], [test][test_whenYieldPointerChangesAfterQueue_executionReverts_AdminOnlySeed], [test][test_whenYieldPointerChangesAfterQueue_executionReverts_RevenueRoleOnlySeed], [test][test_whenYieldPointerChangesAfterQueue_executionReverts_RolesOverlapSeed] |

## Queue conflicts

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QDAR-Q01 | Fuzz permitted role caller | Conflict with existing per-asset action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [test][test_whenAssetKeyAlreadyOwned_secondQueueReverts], [test][test_whenAssetKeyAlreadyOwned_secondQueueReverts_AdminOnlySeed], [test][test_whenAssetKeyAlreadyOwned_secondQueueReverts_RevenueRoleOnlySeed], [test][test_whenAssetKeyAlreadyOwned_secondQueueReverts_RolesOverlapSeed] |

[test_whenUnauthorizedCallerQueues_reverts]: ./queueDisableAssetRoutes.t.sol#L85
[test_givenTimelockDisabled_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol#L105
[test_givenTimelockInactive_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol#L118
[test_givenOperatorRotated_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol#L138
[test_givenDistributorDisabled_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol#L157
[test_givenDistributorInactive_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol#L175
[test_whenActiveAssetDisableQueues_executesAfterDelay]: ./queueDisableAssetRoutes.t.sol#L202
[test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol#L29
[test_givenRetiredAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol#L54
[test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueDisableAssetRoutes.t.sol#L231
[test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt]: ./queueDisableAssetRoutes.t.sol#L291
[test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol#L268
[test_whenAssetRetiredAfterQueue_executionReverts]: ./queueDisableAssetRoutes.t.sol#L325
[test_whenYieldPointerChangesAfterQueue_executionReverts]: ./queueDisableAssetRoutes.t.sol#L362
[test_whenAssetKeyAlreadyOwned_secondQueueReverts]: ./queueDisableAssetRoutes.t.sol#L395
[test_givenDistributorInactive_whenQueued_reverts_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L427
[test_givenDistributorInactive_whenQueued_reverts_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L438
[test_givenDistributorInactive_whenQueued_reverts_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L449
[test_whenActiveAssetDisableQueues_executesAfterDelay_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L550
[test_whenActiveAssetDisableQueues_executesAfterDelay_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L561
[test_whenActiveAssetDisableQueues_executesAfterDelay_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L572
[test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L583
[test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L594
[test_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L607
[test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L454
[test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L464
[test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L476
[test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L486
[test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L499
[test_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L512
[test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L525
[test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L535
[test_givenRetiredAsset_whenDisableQueued_revertsAtQueue_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L545
[test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L675
[test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L686
[test_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L699
[test_whenAssetRetiredAfterQueue_executionReverts_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L645
[test_whenAssetRetiredAfterQueue_executionReverts_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L655
[test_whenAssetRetiredAfterQueue_executionReverts_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L665
[test_whenYieldPointerChangesAfterQueue_executionReverts_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L712
[test_whenYieldPointerChangesAfterQueue_executionReverts_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L722
[test_whenYieldPointerChangesAfterQueue_executionReverts_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L732
[test_whenAssetKeyAlreadyOwned_secondQueueReverts_AdminOnlySeed]: ./queueDisableAssetRoutes.t.sol#L618
[test_whenAssetKeyAlreadyOwned_secondQueueReverts_RevenueRoleOnlySeed]: ./queueDisableAssetRoutes.t.sol#L629
[test_whenAssetKeyAlreadyOwned_secondQueueReverts_RolesOverlapSeed]: ./queueDisableAssetRoutes.t.sol#L640
