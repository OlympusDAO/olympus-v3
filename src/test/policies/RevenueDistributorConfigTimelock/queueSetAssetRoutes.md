# queueSetAssetRoutes scenario plan

Scope: RDT wrapper for RD.setAssetRoutes(asset,repurchaseBps,routes). Store the supplied route on RD. Queueing validates the complete request against current RD state, and execution revalidates live conditions after its state-hash guard.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT enabled, RDT Kernel-active, selected as RD configOperator, permitted proposer, RD Kernel-active and locally enabled. Error order follows that list; guard errors are NotEnabled(), RevenueDistributorConfigTimelock_PolicyInactive(RDT/RD), ConfigOperator_Unauthorized(RDT), NotAuthorised(). Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: per-asset; expected hash: assetDistributionHash(asset).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `asset_`, `repurchaseBps_` and `routes_` against the complete downstream input rules in [setAssetRoutes](../RevenueDistributor/setAssetRoutes.md). This wrapper uses valid payloads plus one representative invalid request to prove queue-time rejection, then separately covers live drift after a valid queue.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and parameter domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSAR-A01 | Any caller outside the permitted proposer set, fuzz | All earlier RDT/operator gates and RD lifecycle valid; fuzz `asset_` as zero/EOA/contract, `repurchaseBps_` as 0/10,000/`type(uint16).max`, and `routes_` as empty/valid/invalid | NotAuthorised() | Queue unchanged | Covered: [fuzzed domain][testFuzz_whenCallerHasNoConfigRole_queueReverts], [seed identities][test_whenKnownUnauthorizedIdentitiesQueue_reverts] |

## Lifecycle

Fuzz all three queue parameters across the authorization domain above; they do not affect these guard outcomes.

| ID | RDT Kernel | RDT local | Selected operator | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-L01 | Active | Disabled | Yes | Active | Enabled | NotEnabled() | Queue unchanged | Covered: [roles, parameter fuzz and rollback][testFuzz_givenTimelockDisabled_whenRouteQueued_reverts] |
| QSAR-L02 | Inactive | Enabled | Yes | Active | Enabled | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Queue unchanged | Covered: [roles, parameter fuzz and rollback][testFuzz_givenTimelockInactive_whenRouteQueued_reverts] |
| QSAR-L03 | Active | Enabled | No | Active | Enabled | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [roles, parameter fuzz and rollback][testFuzz_givenOperatorRotated_whenRouteQueued_reverts] |
| QSAR-L04 | Active | Enabled | Yes | Active | Disabled | NotEnabled() | Queue unchanged | Covered: [roles, parameter fuzz and rollback][testFuzz_givenTargetDisabled_whenRouteQueued_revertsForEitherRole] |
| QSAR-L05 | Active | Enabled | Yes | Inactive | Enabled or disabled | RevenueDistributorConfigTimelock_PolicyInactive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [roles, local states, parameter fuzz and rollback][testFuzz_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState] |

## Behavior

| ID | Caller | Prior asset state | `asset_` | `repurchaseBps_` | `routes_` | Execution-time state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-P01 | Permitted proposer, fuzz | NeverListed | Valid nonzero contract | 0 | Valid representative nonempty route | Guarded state unchanged | Queue then ready execution succeeds | Exact forwarding; RD becomes Active with requested route | Covered: [exact queue, guard, payload, event and execution assertions][testFuzz_whenValidNonemptyRouteQueued_storesExactActionAndExecutes] |

## Invalid inputs

| ID | Caller | Prior asset state | `asset_` | `repurchaseBps_` | Route-recipient state | Route BPS state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-I01 | Admin; Revenue Distributor Admin separately | Any unchanged state | Valid nonzero contract | 0 | Unique, valid | Total 10,001 | Queue gives RevenueDistributor_InvalidBasisPoints(10001) | No action ID consumed or key acquired; no route mutation | Covered: [evidence][test_whenRouteBasisPointsExceedMaximum_revertsAtQueue] |

## State changes

| ID | Caller | Route/listing after queue | Yield pointer/availability after queue | Custody/debt after queue | Treasury after queue | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSAR-S01 | Admin; Revenue Distributor Admin separately | Same asset route changed | Unchanged | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [evidence][testFuzz_whenRouteChanges_executionRevertsAndRetainsKey] |
| QSAR-S04 | Admin; Revenue Distributor Admin separately | Same asset listing changed | Unchanged | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [evidence][testFuzz_whenListingChanges_executionRevertsAndRetainsKey] |
| QSAR-S05 | Admin; Revenue Distributor Admin separately | Unchanged | Changed | Unchanged | Unchanged | IConfigTimelockBatchQueue_ConfigStateChanged with actual key and hashes | Target/action/key unchanged by failed execution | Covered: [evidence][testFuzz_whenYieldPointerChanges_executionRevertsAndRetainsKey] |
| QSAR-S02 | Admin; Revenue Distributor Admin separately | Unchanged | Unchanged | Custody donation only | Unchanged | Expected hash remains valid | Ready execution applies requested route | Covered: [evidence][testFuzz_whenCustodyChangesAfterQueue_executionStillSucceeds] |
| QSAR-S06 | Admin; Revenue Distributor Admin separately | Unchanged | Unchanged | Pending debt paid only | Unchanged | Expected hash remains valid | Ready execution applies requested route | Covered: [evidence][testFuzz_whenPendingDebtPaidAfterQueue_executionStillSucceeds] |
| QSAR-S07 | Admin; Revenue Distributor Admin separately | Unchanged | Unchanged | Unchanged | Upgraded to non-colliding address | Expected hash remains valid | Ready execution applies requested route using live Treasury validation | Covered: [evidence][testFuzz_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds] |
| QSAR-S03 | Admin; Revenue Distributor Admin separately | Unchanged | Unchanged | Unchanged | Upgraded to queued configured recipient | Hash unchanged; execution gives RevenueDistributor_InvalidRecipient(newTreasury) | Retain queued action/key; no route, liability or custody mutation | Covered: [evidence][testFuzz_whenQueuedRecipientBecomesTreasury_executionReverts] |
| QSAR-S08 | Admin; Revenue Distributor Admin separately | Unchanged; queued repurchase 2,000 BPS | Same pointer; Kernel-active; locally disabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives RevenueDistributor_InvalidYieldRecipient(yieldRecipient) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [live validation and retry][test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries] |
| QSAR-S09 | Admin; Revenue Distributor Admin separately | Unchanged; queued repurchase 2,000 BPS | Same pointer; Kernel-inactive; locally enabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives RevenueDistributor_InvalidYieldRecipient(yieldRecipient) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [live validation and retry][test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries] |
| QSAR-S10 | Admin; Revenue Distributor Admin separately | Unchanged; queued repurchase 2,000 BPS | Same pointer; active/enabled; asset registration disabled | Unchanged | Unchanged | Guard hash unchanged; live validation gives RevenueDistributor_YieldRecipientUnavailable(yieldRecipient,asset) | No events or RD mutation; action/payload/key retained; restore dependency and retry successfully | Covered: [live validation and retry][test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries] |

## Queue conflicts

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSAR-Q01 | Each permitted proposer | Conflict with existing per-asset action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [evidence][testFuzz_whenAssetKeyAlreadyOwned_secondRouteQueueReverts] |

[testFuzz_whenCallerHasNoConfigRole_queueReverts]: ./queueSetAssetRoutes.t.sol#L134
[test_whenKnownUnauthorizedIdentitiesQueue_reverts]: ./queueSetAssetRoutes.t.sol#L155
[testFuzz_whenValidNonemptyRouteQueued_storesExactActionAndExecutes]: ./queueSetAssetRoutes.t.sol#L309
[testFuzz_givenTimelockDisabled_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L165
[testFuzz_givenTimelockInactive_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L189
[testFuzz_givenOperatorRotated_whenRouteQueued_reverts]: ./queueSetAssetRoutes.t.sol#L220
[testFuzz_givenTargetDisabled_whenRouteQueued_revertsForEitherRole]: ./queueSetAssetRoutes.t.sol#L249
[testFuzz_givenTargetInactive_whenRouteQueued_revertsBeforeLocalState]: ./queueSetAssetRoutes.t.sol#L273
[test_whenRouteBasisPointsExceedMaximum_revertsAtQueue]: ./queueSetAssetRoutes.t.sol#L89
[testFuzz_whenRouteChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L417
[testFuzz_whenListingChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L447
[testFuzz_whenYieldPointerChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L475
[testFuzz_whenCustodyChangesAfterQueue_executionStillSucceeds]: ./queueSetAssetRoutes.t.sol#L505
[testFuzz_whenPendingDebtPaidAfterQueue_executionStillSucceeds]: ./queueSetAssetRoutes.t.sol#L527
[testFuzz_whenTreasuryUpgradesToNoncollidingAddress_executionSucceeds]: ./queueSetAssetRoutes.t.sol#L559
[testFuzz_whenQueuedRecipientBecomesTreasury_executionReverts]: ./queueSetAssetRoutes.t.sol#L581
[testFuzz_whenAssetKeyAlreadyOwned_secondRouteQueueReverts]: ./queueSetAssetRoutes.t.sol#L608

[test_givenQueuedRepurchase_whenYieldRecipientDisabled_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L712
[test_givenQueuedRepurchase_whenYieldRecipientInactive_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L738
[test_givenQueuedRepurchase_whenYieldRecipientAssetUnsupported_revertsThenRetries]: ./queueSetAssetRoutes.t.sol#L766
