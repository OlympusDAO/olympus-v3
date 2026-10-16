# queueDisableAssetRoutes scenario plan

Scope: RDT wrapper for RD.disableAssetRoutes(asset). Retire a requested Active asset. Queueing validates that the asset is Active, and execution rejects guarded state drift before forwarding the request.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT enabled, RDT Kernel-active, selected as RD configOperator, permitted proposer, RD Kernel-active and locally enabled. Error order follows that list; guard errors are NotEnabled(), RevenueDistributorConfigTimelock_PolicyInactive(RDT/RD), ConfigOperator_Unauthorized(RDT), NotAuthorised(). Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: per-asset; expected hash: assetDistributionHash(asset).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `asset_` activity against the same rule documented in [disableAssetRoutes](../RevenueDistributor/disableAssetRoutes.md). Execution still protects against a once-valid asset changing after queueing.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and `asset_` domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QDAR-A01 | Any caller outside the permitted proposer set, fuzz | All earlier RDT/operator gates and RD lifecycle valid; fuzz `asset_` as zero, EOA, NeverListed, Active and Retired | NotAuthorised() | Queue unchanged | Covered: [evidence][testFuzz_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle

Fuzz `asset_` across the authorization domain above; it does not affect these guard outcomes.

| ID | RDT Kernel | RDT local | Selected operator | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-L01 | Active | Disabled | Yes | Active | Enabled | NotEnabled() | Queue unchanged | Covered: [evidence][testFuzz_givenTimelockDisabled_whenQueued_reverts] |
| QDAR-L02 | Inactive | Enabled | Yes | Active | Enabled | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Queue unchanged | Covered: [evidence][testFuzz_givenTimelockInactive_whenQueued_reverts] |
| QDAR-L03 | Active | Enabled | No | Active | Enabled | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [evidence][testFuzz_givenOperatorRotated_whenQueued_reverts] |
| QDAR-L04 | Active | Enabled | Yes | Active | Disabled | NotEnabled() | Queue unchanged | Covered: [evidence][testFuzz_givenDistributorDisabled_whenQueued_reverts] |
| QDAR-L05 | Active | Enabled | Yes | Inactive | Enabled or disabled | RevenueDistributorConfigTimelock_PolicyInactive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [evidence][testFuzz_givenDistributorInactive_whenQueued_reverts] |

## Behavior

| ID | Caller | Asset state at queue | Route state | Pending bucket mask | Asset state at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-P01 | Permitted proposer, fuzz | Active | Representative nonempty route | Representative nonempty debt | Unchanged | Queue then ready execution succeeds | Exact forwarding; retire route; pending debt preserved | Covered: [base][testFuzz_whenActiveAssetDisableQueues_executesAfterDelay], [route and debt][testFuzz_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt] |

## Invalid inputs

| ID | Caller | `asset_` kind | Asset state at queue | Asset state at execution | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-I01 | Permitted proposer, fuzz | Fuzz zero, EOA, contract | NeverListed | No execution | Queue gives RevenueDistributor_AssetNotActive(asset) | No action ID consumed or key acquired; no route/state mutation | Covered: [contract][test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue], [zero and EOA][testFuzz_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue] |
| QDAR-I02 | Permitted proposer, fuzz | Nonzero contract | Retired | No execution | Queue gives RevenueDistributor_AssetNotActive(asset) | No action ID consumed or key acquired; pending debt and retired state unchanged | Covered: [evidence][test_givenRetiredAsset_whenDisableQueued_revertsAtQueue] |

## State changes

| ID | Caller | Queued asset state | Post-queue route state | Post-queue listing state | Post-queue yield pointer | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QDAR-S01 | Admin; Revenue Distributor Admin separately | Active | Changed | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key and action | Covered: [both proposers and executor fuzz][testFuzz_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey] |
| QDAR-S02 | Admin; Revenue Distributor Admin separately | Active | Cleared by direct Active→Retired transition | Active→Retired | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged before downstream execution | Failed execution retains key and action; the independently committed retirement remains | Covered: [evidence][testFuzz_whenAssetRetiredAfterQueue_executionReverts] |
| QDAR-S03 | Admin; Revenue Distributor Admin separately | Active | Unchanged | Unchanged | Changed | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key and action | Covered: [evidence][testFuzz_whenYieldPointerChangesAfterQueue_executionReverts] |

## Queue conflicts

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QDAR-Q01 | Each permitted proposer | Conflict with existing per-asset action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [evidence][testFuzz_whenAssetKeyAlreadyOwned_secondQueueReverts] |

[testFuzz_whenUnauthorizedCallerQueues_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenTimelockDisabled_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenTimelockInactive_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenOperatorRotated_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenDistributorDisabled_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenDistributorInactive_whenQueued_reverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_whenActiveAssetDisableQueues_executesAfterDelay]: ./queueDisableAssetRoutes.t.sol
[test_givenNeverListedAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol#L27
[test_givenRetiredAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol#L49
[testFuzz_whenRouteChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueDisableAssetRoutes.t.sol
[testFuzz_whenActiveAssetHasRouteAndDebt_retirementPreservesDebt]: ./queueDisableAssetRoutes.t.sol
[testFuzz_givenNonContractNeverListedAsset_whenDisableQueued_revertsAtQueue]: ./queueDisableAssetRoutes.t.sol
[testFuzz_whenAssetRetiredAfterQueue_executionReverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_whenYieldPointerChangesAfterQueue_executionReverts]: ./queueDisableAssetRoutes.t.sol
[testFuzz_whenAssetKeyAlreadyOwned_secondQueueReverts]: ./queueDisableAssetRoutes.t.sol
