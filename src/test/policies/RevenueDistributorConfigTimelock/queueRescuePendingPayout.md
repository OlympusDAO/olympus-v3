# RevenueDistributorConfigTimelock.queueRescuePendingPayout scenario plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

RDT = RevenueDistributorConfigTimelock; RD = its controlled RevenueDistributor. This plan tests queueing and rescue-specific changes before execution. [RD's plan](../RevenueDistributor/rescuePendingPayout.md) owns payout mechanics; [executeQueuedAction.t.sol](./executeQueuedAction.t.sol) covers route execution and operator rotation; [shared queue tests](../utils/TimelockBatchQueue/executeQueuedAction.t.sol) own timing, action flags, events and same-action reentrancy. The execution plan owns pending-rescue execution gates and permissionless callers. Queue suite: [queueRescuePendingPayout.t.sol](./queueRescuePendingPayout.t.sol). Grouped tests and their deterministic boundary drivers are mapped below.

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

## Domains and shared assertions

- Queue callers: admin and revenue_distributor_admin, tested separately. Fuzz unauthorized callers excluding all holders of either role; seed operator-only, emergency-only and payout recipient.
- Fixed default: RDT enabled/Kernel-active and selected as RD's operator; RD active; Active asset; accepting token and destination; originalRecipient owed 10 base units; queued amount=4. RD local enablement does not block pending rescue. A disabled or Kernel-inactive RDT blocks typed/batch queueing, execution and cancellation; admin recovery goes directly through RD.
- Use named arguments `asset`, `originalRecipient`, `destination`, `amount` and fixed addresses. No numeric or payout-bucket fuzzing in this queue plan.
- Queue success returns the pre-call nextActionId and increments once. Store one RD rescue action with exact `abi.encode(asset,originalRecipient,destination,4)`, proposer, timestamps, pending flags, RD destination and scoped asset-key owner. No entitlement or balances move.
- All route/retirement/surplus-rescue/pending-rescue actions for an asset share its RD-scoped key, regardless of recipient/destination/amount. Different assets and global yield-recipient changes have independent keys.
- Stored rescue state hash is `keccak256(abi.encode(RD.assetState(asset)))`. Active→Retired changes it. Balances, entitlement, yield recipient, Treasury and route edits preserving listing state do not.
- Unchanged = queue counter/actions/keys, configuration, entitlement/reserve and balances unchanged; no committed events.

Queue events, emitted by RDT in order: `ConfigStateQueued` → `TimelockSubActionQueued` → `TimelockActionQueued`. Assert exact action ID, target RD, selector, payload/batch hashes, scoped key, expected state hash, proposer and timestamps.

## Scenario setup

Use the valid request and amount=0. Independently fail each gate with earlier checks passing; combined faults establish precedence. Test current enabled/disabled and active/inactive states without restoration histories.

## Authorization

Fixed for this table: RD Kernel: Active.

| ID | Caller | Local active | Local enabled | Selected current configOperator without ADMIN_ROLE | Distributor enabled | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-L01 | Fuzz permitted role caller | true | true | Selected | true | Queue succeeds; store amount=4 without payout | Covered: [test][test_givenValidRequest_whenEachRoleQueues], [test][test_givenValidRequest_whenEachRoleQueues_AdminOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RevenueRoleOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RolesOverlapSeed] |
| RDT-L04 | Fuzz permitted role caller | true | true | Selected | false | Queue succeeds; store amount=4 without payout | Covered: [test][test_givenValidRequest_whenEachRoleQueues], [test][test_givenValidRequest_whenEachRoleQueues_AdminOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RevenueRoleOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RolesOverlapSeed] |
| RDT-L02 | Any unauthorized caller | true | true | Selected | true | `NotAuthorised()` before preview; Unchanged | Covered: [unauthorized caller queues pending rescue][test_givenDistributorInactive_whenUnauthorizedCallerQueuesPendingRescue_reverts], [fuzzed callers][test_whenQueueCallerIsUnauthorized_reverts], [caller identities][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| RDT-L03 | Authorized/unauthorized queue caller | true | false | Selected | true | `NotEnabled()`; Unchanged | Covered: [pending rescue queued][test_givenTimelockDisabled_whenPendingRescueQueued_reverts] |
| RDT-L07 | Authorized/unauthorized queue caller | false | true | Selected or not selected | true | `RevenueDistributorConfigTimelock_PolicyNotActive(RDT)`; Unchanged | Covered: [competing operator][test_givenInactiveTimelock_givenOperatorChanged_whenUnauthorizedQueues_reverts], [pending rescue queued][test_givenTimelockInactive_whenPendingRescueQueued_reverts], [queue faults compete][test_whenQueueFaultsCompete_reverts] |
| RDT-L08 | ADMIN or REVENUE_DISTRIBUTOR_ADMIN caller | true | true | Not selected | true | `ConfigOperator_Unauthorized(RDT)`; Unchanged | Covered: [pending rescue queued][test_givenOperatorChanged_whenPendingRescueQueued_reverts] |

## Competing admission faults

Queue amount is either the valid fixture amount of 4 raw units or zero where stated. Rejected calls retain exact queue state, entitlement, reserve, balances and committed logs.

| ID | Caller | Local active | Local enabled | Selected operator | Distributor active | Distributor enabled | Amount | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-L09 | EMERGENCY-only caller | false | false | Yes | false | true | 0 | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Unchanged before roles, RD status or amount validation | Covered: [test][test_givenInactiveDisabledTimelock_givenInactiveDistributor_whenUnauthorizedQueues_reverts], [seed][test_whenQueueFaultsCompete_reverts] |
| RDT-A01 | EMERGENCY-only caller | true | true | No | true | Fuzz false/true; seed both | 0 and 4 | NotAuthorised() | Unchanged before operator selection or amount validation | Covered: [test][test_givenOperatorChanged_whenUnauthorizedCallerQueues_reverts], [seed][test_whenQueueFaultsCompete_reverts] |

## Lifecycle

Fixed for this table: RDT local: Enabled; RDT Kernel: Active; Operator: Selected; RD local: Enabled/disabled; RD Kernel: Inactive; Queue outcome / effects: Preview and queue revert `RevenueDistributor_PolicyNotActive(RD)`; Unchanged.

| ID | Caller | Test |
| --- | --- | --- |
| RDT-L05 | Authorized queue caller | Covered: [admin queues pending rescue][test_givenDistributorInactive_whenAdminQueuesPendingRescue_reverts], [revenue admin queues pending rescue][test_givenDistributorInactive_whenRevenueAdminQueuesPendingRescue_reverts] |

Current queue order: RDT active → RDT enabled → caller role → selected operator → RD preview → conflict key. RD preview checks Kernel activity before inputs; its rejection occurs before any queue state commits.

## Queue behavior

| ID | Caller | Fixed request / state | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-Q01 | Fuzz permitted role caller | Valid request, amount=4; Active and Retired assets with pending entitlement tested separately | Store unchanged action and emit queue events; no payout | Covered: [test][test_givenValidRequest_whenEachRoleQueues], [test][test_givenValidRequest_whenEachRoleQueues_AdminOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RevenueRoleOnlySeed], [test][test_givenValidRequest_whenEachRoleQueues_RolesOverlapSeed] |
| RDCT-PENDING-RESCUE-Q02 | Authorized queue caller | Another action owns the same asset key; vary recipient/destination/valid amount or use an asset-scoped route action | `IConfigTimelockBatchQueue_ConfigKeyPending(key,owner)`; prior action unchanged | Covered: [another valid request queues][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts] |
| RDCT-PENDING-RESCUE-Q03 | Authorized queue caller | Different asset, or global yield-recipient action; both requests valid | Independent keys permit queueing | Covered: [queued][test_givenIndependentAssetAndGlobalAction_whenQueued] |

## Invalid inputs

One deterministic preview failure demonstrates propagation. RD's suite owns the complete invalid-input domain.

| ID | Caller | Invalid request | Queue outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-I01 | Authorized queue caller | amount=0; otherwise valid fixture | Bubble `RevenueDistributor_InvalidRescueAmount()`; no ID/key consumed; Unchanged | Covered: [preview rejects before conflict][test_whenPreviewRejectsBeforeConflict_reverts] |

Also use amount=0 with an already-owned asset key to prove preview failure precedes key conflict.

Execution, post-queue drift and transfer failures are specified in [executeQueuedAction](executeQueuedAction.md). Queue cases assert only admission and committed data.

Direct admin recovery belongs to [RD’s rescuePendingPayout scenarios](../RevenueDistributor/rescuePendingPayout.md); it bypasses the unavailable timelock.

Pending rescue requires debt on a managed Active/Retired asset, while surplus `rescue` requires NeverListed. They cannot both pass preview for the same current asset state; their shared key does not create a valid competing-queue case.

Use a fixed role-recipient fixture with no other debt for routing-change rejection, and a fixed-address pending recipient for routing changes that preserve success. No RD allocation matrix is repeated here.

[test_givenValidRequest_whenEachRoleQueues]: ./queueRescuePendingPayout.t.sol#L60
[test_givenDistributorInactive_whenUnauthorizedCallerQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L222
[test_whenQueueCallerIsUnauthorized_reverts]: ./queueRescuePendingPayout.t.sol#L254
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./queueRescuePendingPayout.t.sol#L261
[test_givenTimelockDisabled_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L92
[test_whenQueueFaultsCompete_reverts]: ./queueRescuePendingPayout.t.sol#L270
[test_givenTimelockInactive_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L113
[test_givenOperatorChanged_whenPendingRescueQueued_reverts]: ./queueRescuePendingPayout.t.sol#L139
[test_givenDistributorInactive_whenAdminQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L164
[test_givenDistributorInactive_whenRevenueAdminQueuesPendingRescue_reverts]: ./queueRescuePendingPayout.t.sol#L193
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts]: ./queueRescuePendingPayout.t.sol#L351
[test_givenIndependentAssetAndGlobalAction_whenQueued]: ./queueRescuePendingPayout.t.sol#L393
[test_whenPreviewRejectsBeforeConflict_reverts]: ./queueRescuePendingPayout.t.sol#L323
[test_givenValidRequest_whenEachRoleQueues_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1506
[test_givenValidRequest_whenEachRoleQueues_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1511
[test_givenValidRequest_whenEachRoleQueues_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1516
[test_givenInactiveTimelock_givenOperatorChanged_whenUnauthorizedQueues_reverts]: ./queueRescuePendingPayout.t.sol#L290
[test_givenInactiveDisabledTimelock_givenInactiveDistributor_whenUnauthorizedQueues_reverts]: ./queueRescuePendingPayout.t.sol#L280
[test_givenOperatorChanged_whenUnauthorizedCallerQueues_reverts]: ./queueRescuePendingPayout.t.sol#L299
