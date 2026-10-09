# RevenueDistributorConfigTimelock.queueRescuePendingPayout scenario plan

RDT = RevenueDistributorConfigTimelock; RD = its controlled RevenueDistributor. This plan tests queueing and rescue-specific changes before execution. [RD's plan](../RevenueDistributor/rescuePendingPayout.md) owns payout mechanics; [executeQueuedAction.t.sol](./executeQueuedAction.t.sol) covers route execution and operator rotation; [shared queue tests](../utils/TimelockBatchQueue/executeQueuedAction.t.sol) own timing, action flags, events and same-action reentrancy. This suite also covers pending-rescue execution gates and permissionless callers. Queue suite: [queueRescuePendingPayout.t.sol](./queueRescuePendingPayout.t.sol). Grouped tests and their deterministic boundary drivers are mapped below.

## Domains and shared assertions

- Queue callers: admin and revenue_distributor_admin, tested separately. Fuzz unauthorized callers excluding all holders of either role; seed operator-only, emergency-only and payout recipient.
- Fixed default: RDT enabled/Kernel-active and selected as RD's operator; RD active; Active asset; accepting token and destination; originalRecipient owed 10 base units; queued amount=4. RD local enablement does not block pending rescue. A disabled or Kernel-inactive RDT blocks typed/batch queueing, execution and cancellation; admin recovery goes directly through RD.
- Use named arguments `asset`, `originalRecipient`, `destination`, `amount` and fixed addresses. No numeric or payout-bucket fuzzing in this queue plan.
- Queue success returns the pre-call nextActionId and increments once. Store one RD rescue action with exact `abi.encode(asset,originalRecipient,destination,4)`, proposer, timestamps, pending flags, RD destination and scoped asset-key owner. No entitlement or balances move.
- All route/retirement/surplus-rescue/pending-rescue actions for an asset share its RD-scoped key, regardless of recipient/destination/amount. Different assets and global yield-recipient changes have independent keys.
- Stored rescue state hash is `keccak256(abi.encode(RD.assetState(asset)))`. Active→Retired changes it. Balances, entitlement, yield recipient, Treasury and route edits preserving listing state do not.
- Unchanged = queue counter/actions/keys, configuration, entitlement/reserve and balances unchanged; no committed events.

Queue events, emitted by RDT in order: `ConfigStateQueued` → `TimelockSubActionQueued` → `TimelockActionQueued`. Assert exact action ID, target RD, selector, payload/batch hashes, scoped key, expected state hash, proposer and timestamps.

## Queue authorization and lifecycle

Use the valid request and amount=0. Independently fail each gate with earlier checks passing; combined faults establish precedence. Test current enabled/disabled and active/inactive states without restoration histories.

| ID | Caller | RDT local | RDT Kernel | Operator | RD local | RD Kernel | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-L01 | Admin; revenue_distributor_admin | Enabled | Active | Selected | Enabled/disabled | Active | Queue succeeds; ready execution pays stored 4 | Covered: [role queues][test_givenValidRequest_whenEachRoleQueues] |
| RDT-L02 | Any unauthorized caller | Enabled | Active | Selected | Enabled | Active | `NotAuthorised()` before preview; Unchanged | Covered: [unauthorized caller queues pending rescue][test_givenDistributorInactive_whenUnauthorizedCallerQueuesPendingRescue_reverts], [fuzzed callers][test_whenQueueCallerIsUnauthorized_reverts], [caller identities][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| RDT-L03 | Authorized/unauthorized queue caller | Disabled | Active | Selected | Enabled | Active | `NotEnabled()`; Unchanged | Covered: [pending rescue queued][test_givenTimelockDisabled_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| RDT-L07 | Authorized/unauthorized queue caller | Enabled | Inactive | Selected | Enabled | Active | `RevenueDistributorConfigTimelock_PolicyInactive(RDT)`; Unchanged | Covered: [pending rescue queued][test_givenTimelockInactive_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| RDT-L08 | Authorized/unauthorized queue caller | Enabled | Active | Not selected | Enabled | Active | `ConfigOperator_Unauthorized(RDT)`; Unchanged | Covered: [pending rescue queued][test_givenOperatorChanged_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| RDT-L05 | Authorized queue caller | Enabled | Active | Selected | Enabled/disabled | Inactive | Preview and queue revert `RevenueDistributor_PolicyInactive()`; Unchanged | Covered: [admin queues pending rescue][test_givenDistributorInactive_whenAdminQueuesPendingRescue_reverts], [revenue admin queues pending rescue][test_givenDistributorInactive_whenRevenueAdminQueuesPendingRescue_reverts] |

Current queue order: RDT enabled → RDT active → selected operator → caller role → RD preview → conflict key. RD preview checks Kernel activity before inputs; its rejection occurs before any queue state commits.

## Queue behavior

| ID | Caller | Fixed request / state | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-Q01 | Admin; revenue_distributor_admin | Valid request, amount=4; Active and Retired assets with pending entitlement tested separately | Store unchanged action and emit queue events; no payout | Covered: [role queues][test_givenValidRequest_whenEachRoleQueues] |
| RDT-Q02 | Authorized queue caller | Another action owns the same asset key; vary recipient/destination/valid amount or use an asset-scoped route action | `IConfigTimelockBatchQueue_ConfigKeyPending(key,owner)`; prior action unchanged | Covered: [another valid request queues][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts] |
| RDT-Q03 | Authorized queue caller | Different asset, or global yield-recipient action; both requests valid | Independent keys permit queueing | Covered: [queued][test_givenIndependentAssetAndGlobalAction_whenQueued] |

## Invalid inputs

One deterministic preview failure demonstrates propagation. RD's suite owns the complete invalid-input domain.

| ID | Caller | Invalid request | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-I01 | Authorized queue caller | amount=0; otherwise valid fixture | Bubble `RevenueDistributor_InvalidRescueAmount()`; no ID/key consumed; Unchanged | Covered: [preview rejects before conflict][test_whenPreviewRejectsBeforeConflict_reverts] |

Also use amount=0 with an already-owned asset key to prove preview failure precedes key conflict.

## Rescue-specific changes before execution

Execute the stored amount=4 at a valid ready timestamp. Expect one unchanged RD call. Success pays 4, updates entitlement, completes the action and releases its key. Failure preserves the pending action/key and rolls back payment/debt; match exact error data. The rows below also cover concrete RDT execution gates and permissionless callers.

| ID | Caller | Change after queue | Execution outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-E03 | Executor | Entitlement increases to 12, decreases to 6, or equals 4; separately custody/surplus grows with entitlement still 10 | Hash unchanged; original amount 4 pays, leaving entitlement 8,2,0,6 respectively | Covered: [entitlement increases][test_givenQueuedRequest_whenEntitlementIncreases], [entitlement decreases but remains sufficient][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient], [entitlement equals amount][test_givenQueuedRequest_whenEntitlementEqualsAmount], [custody increases][test_givenQueuedRequest_whenCustodyIncreases] |
| RDT-E04 | Executor | Entitlement falls to 3 or 0; separately yield/Treasury recipient changes remove originalRecipient's entitlement | `RevenueDistributor_InsufficientPendingDistribution(asset,4,currentEntitlement)`, not stale-state error; no payment | Covered: [entitlement is insufficient][test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts], [entitlement already paid][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts], [repurchase recipient changes][test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts], [treasury upgraded][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts] |
| RDT-E05 | Executor | Asset Active→Retired after queue; also seed entitlement below 4 | `IConfigTimelockBatchQueue_ConfigStateChanged(actionId,0,key,expectedHash,currentHash)` before RD input checks; action/key retained | Covered: [retired][test_givenQueuedActiveAsset_whenRetired_reverts] |
| RDT-E06 | Executor | Token/destination rejects delivery or custody becomes insufficient | Exact RD/token error; full rollback, no payment | Covered: [token rejects transfer][test_givenQueuedRequest_whenTokenRejectsTransfer_reverts], [custody is insufficient][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts] |
| RDT-E09 | Executor | Routes change while asset remains Active; yield/Treasury recipient changes while originalRecipient retains entitlement ≥4 | No stale-state rejection; pay only stored 4 using current entitlement | Covered: [route changes][test_givenQueuedFixedRecipient_whenRouteChanges], [yield recipient changes][test_givenQueuedFixedRecipient_whenYieldRecipientChanges], [treasury upgraded][test_givenQueuedFixedRecipient_whenTreasuryUpgraded] |
| RDT-E10 | Executor | RD becomes Kernel-inactive after a valid queue | `RevenueDistributor_PolicyInactive()`; action/key retained, no payment | Covered: [distributor becomes inactive][test_givenQueuedRequest_whenDistributorBecomesInactive_reverts] |
| RDT-E11 | Executor | RDT disabled after a valid queue; other gates pass | `NotEnabled()`; action/key retained, no payment | Covered: [executed][test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts] |
| RDT-E12 | Executor | RDT Kernel-inactive after a valid queue; other gates pass | `RevenueDistributorConfigTimelock_PolicyInactive(RDT)`; action/key retained, no payment | Covered: [executed][test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts] |
| RDT-E13 | Any caller (fuzz, no exclusions) | Mature valid request; RDT enabled/active/selected | Permissionless execution pays stored 4 once and releases key | Covered: [fuzz][test_givenQueuedRequest_whenAnyCallerExecutes] |

Direct admin recovery belongs to [RD’s rescuePendingPayout scenarios](../RevenueDistributor/rescuePendingPayout.md); it bypasses the unavailable timelock.

Pending rescue requires debt on a managed Active/Retired asset, while surplus `rescue` requires NeverListed. They cannot both pass preview for the same current asset state; their shared key does not create a valid competing-queue case.

Use a fixed role-recipient fixture with no other debt for routing-change rejection, and a fixed-address pending recipient for routing changes that preserve success. No RD allocation matrix is repeated here.

[test_givenValidRequest_whenEachRoleQueues]: ./queueRescuePendingPayout.t.sol#L59
[test_givenDistributorInactive_whenUnauthorizedCallerQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L230
[test_whenQueueCallerIsUnauthorized_reverts]: ./queueRescuePendingPayout.t.sol#L264
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./queueRescuePendingPayout.t.sol#L271
[test_givenTimelockDisabled_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L88
[test_whenQueueFaultsCompete_reverts]: ./queueRescuePendingPayout.t.sol#L280
[test_givenTimelockInactive_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L112
[test_givenOperatorChanged_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L141
[test_givenDistributorInactive_whenAdminQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L168
[test_givenDistributorInactive_whenRevenueAdminQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L199
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts]: ./queueRescuePendingPayout.t.sol#L327
[test_givenIndependentAssetAndGlobalAction_whenQueued]: ./queueRescuePendingPayout.t.sol#L365
[test_whenPreviewRejectsBeforeConflict_reverts]: ./queueRescuePendingPayout.t.sol#L298
[test_givenQueuedRequest_whenEntitlementIncreases]: ./queueRescuePendingPayout.t.sol#L424
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient]: ./queueRescuePendingPayout.t.sol#L446
[test_givenQueuedRequest_whenEntitlementEqualsAmount]: ./queueRescuePendingPayout.t.sol#L468
[test_givenQueuedRequest_whenCustodyIncreases]: ./queueRescuePendingPayout.t.sol#L490
[test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L509
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts]: ./queueRescuePendingPayout.t.sol#L541
[test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts]: ./queueRescuePendingPayout.t.sol#L660
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts]: ./queueRescuePendingPayout.t.sol#L692
[test_givenQueuedActiveAsset_whenRetired_reverts]: ./queueRescuePendingPayout.t.sol#L574
[test_givenQueuedRequest_whenTokenRejectsTransfer_reverts]: ./queueRescuePendingPayout.t.sol#L722
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L739
[test_givenQueuedFixedRecipient_whenRouteChanges]: ./queueRescuePendingPayout.t.sol#L602
[test_givenQueuedFixedRecipient_whenYieldRecipientChanges]: ./queueRescuePendingPayout.t.sol#L619
[test_givenQueuedFixedRecipient_whenTreasuryUpgraded]: ./queueRescuePendingPayout.t.sol#L640
[test_givenQueuedRequest_whenDistributorBecomesInactive_reverts]: ./queueRescuePendingPayout.t.sol#L758
[test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L776
[test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L785
[test_givenQueuedRequest_whenAnyCallerExecutes]: ./queueRescuePendingPayout.t.sol#L794
