# RevenueDistributorConfigTimelock.queueRescue coverage plan

Scope: surplus-rescue queue validation/storage and rescue-specific delayed integration. RDT = RevenueDistributorConfigTimelock; RD = bound RevenueDistributor. Generic execution lifecycle, timing, cancellation, action flags and expired-key handling belong to [executeQueuedAction](./executeQueuedAction.t.sol); malformed batch payloads belong to [queueBatch](./queueBatch.t.sol).

## Domains and assertions

- Queue callers: Admin = ADMIN_ROLE holder; Revenue Distributor Admin = REVENUE_DISTRIBUTOR_ADMIN_ROLE holder. Test separately. Fuzz unauthorized callers excluding exactly authorized identities; seed zero, emergency-only and operator-only. No dual-role case.
- Default: RDT/RD enabled and Kernel-active; RDT is RD's selected operator; NeverListed asset with custody B=7 base units and valid unrelated destination. RDT must be enabled/active/selected. RD may be locally disabled. A disabled or Kernel-inactive RDT blocks typed/batch queueing, execution and cancellation; admin can recover directly through RD. Both rescue previews require RD Kernel activity; inactive RD rejects queueing.
- Only NeverListed assets are rescuable; they have no pending debt through supported public flows. Active/Retired are managed even with no debt. Queue stores addresses, not an amount; execution uses full live B. RD's [rescue plan](../RevenueDistributor/rescue.md) owns numeric extremes, transfers and callbacks.
- Key = scope(RD, hash(REVENUE_DISTRIBUTOR_ASSET, asset)); independent of destination, shared with routes/retirement/pending-rescue actions. The stored rescue hash is listing state; custody changes do not stale it.
- Queued: return actionId, increment nextActionId once; store proposer, RD target, rescue selector, exact 64-byte asset/destination payload, ready/expiry, Key owner and listing hash. Assert ConfigStateQueued → TimelockSubActionQueued → TimelockActionQueued with exact fields. No payment/debt/route/configuration mutation.
- Executed: fuzz permissionless executor without exclusions, at a ready timestamp. Pay live B once if positive, with one RD AssetRescued and token Transfer, then sub-action/action execution events. Mark completed; clear payload/guards/owned Key. Preserve other assets and all RD configuration/debts/indexes. B=0 still completes without token call/rescue event.
- Unchanged: all balances, RD state, counter, action payload/guards/flags and Key ownership unchanged; no committed events. Failed execution retains the pending action for corrected retry before expiry. RD errors below omit RevenueDistributor_. Invalid destination includes zero under InvalidRescueDestination.
- Each row links to tests with reciprocal Scenarios comments.

## Authorization and queue lifecycle

Each success row uses nonzero B=7 and checks queue-only effects followed by the exact payment. Distinct RD activity rows have a single execution outcome.

RD is Enabled and Kernel-active in the timelock table. Each request uses B=7; the unauthorized row also checks asset=0.

| ID | Caller | RDT local state | RDT Kernel membership | Operator status | Queue and execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| L-01 | Admin | Enabled | Active | Selected | Queued; pay 7 | Covered: [fuzz][test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes], [fixed fixtures][test_givenPermissionlessExecutorIdentities_whenSeeded] |
| L-02 | Revenue Distributor Admin | Enabled | Active | Selected | Queued; pay 7 | Covered: [fuzz][test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes], [fixed fixtures][test_givenPermissionlessExecutorIdentities_whenSeeded] |
| L-03 | Fuzz unauthorized caller | Enabled | Active | Selected | IPolicyAdmin.NotAuthorised(); Unchanged | Covered: [fuzzed callers][test_givenEnabledActiveSelectedTimelock_whenCallerUnauthorized_reverts], [caller identities][test_givenUnauthorizedIdentities_whenQueueing_reverts] |
| L-04 | Each queue role separately | Disabled | Active | Selected | IEnabler.NotEnabled(); Unchanged | Covered: [rescue queued][test_givenTimelockDisabled_whenRescueQueued_reverts], [timelock disabled][test_givenQueuedRescue_whenTimelockDisabled_reverts] |
| L-05 | Each queue role separately | Enabled | Inactive | Selected | RevenueDistributorConfigTimelock_PolicyInactive(RDT); Unchanged | Covered: [rescue queued][test_givenTimelockInactive_whenRescueQueued_reverts], [timelock inactive][test_givenQueuedRescue_whenTimelockInactive_reverts] |
| L-06 | Each queue role separately | Enabled | Active | Not selected | IConfigOperator.ConfigOperator_Unauthorized(RDT); Unchanged | Covered: [rescue queued][test_givenOperatorRemoved_whenRescueQueued_reverts] |

RDT is Enabled, Kernel-active and selected throughout the downstream table; valid requests use B=7.

| ID | Caller | RD local state | RD Kernel membership | Queue and execution | Test |
| --- | --- | --- | --- | --- | --- |
| L-07 | Each queue role separately | Disabled | Active | Queued; pay 7 | Covered: [fuzz][test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes], [fixed fixtures][test_givenPermissionlessExecutorIdentities_whenSeeded] |
| L-08 | Each queue role separately | Enabled | Inactive | RD PolicyInactive() at queue; Unchanged | Covered: [inactive before queue][test_givenDistributorInactive_whenSurplusRescueQueued_reverts] |
| L-09 | Each queue role separately | Disabled | Inactive | Queued; execution gives RD PolicyInactive(); Unchanged at execution | Covered: [inactive before queue][test_givenDistributorInactive_whenSurplusRescueQueued_reverts] |

Competing queue faults follow RDT enablement → activity → operator selection → caller authorization → preview → conflict. Invalid asset must not mask an earlier gate. Generic execution rechecks belong to executeQueuedAction tests. Direct admin recovery is mapped in [RD’s rescue plan](../RevenueDistributor/rescue.md).

## Requests and invalid inputs

| ID | Caller | State / input | Queue / effects | Ready rescue execution | Test |
| --- | --- | --- | --- | --- | --- |
| P-01 | Each queue role separately | NeverListed B=7; destination=Treasury, operator or unrelated; existing destination balance=3 | Queued; no payment | Pay 7, destination becomes 10; preserve RD/other assets | Covered: [fuzz][test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes], [fixed fixtures][test_givenPermissionlessExecutorIdentities_whenSeeded] |
| P-02 | Each queue role separately | NeverListed B=0; token transfer would reject | Queued | No-op payment; action completes without transfer/error/rescue event | Covered: [executed][test_givenZeroCustodyAtQueue_whenExecuted] |
| I-01 | Each queue role separately | asset=0 or nonzero without code | RD InvalidAsset(asset); Unchanged | No new action | Covered: [asset has no code][test_whenAssetHasNoCode_reverts] |
| I-02 | Each queue role separately | destination=0, Kernel, RD or asset | RD InvalidRescueDestination(destination); Unchanged | No new action | Covered: [destination is forbidden][test_whenDestinationIsForbidden_reverts] |
| I-03 | Each queue role separately | Active asset, with zero debt/positive balance | RD AssetManaged(asset); Unchanged | No new action | Covered: [rescue queued][test_givenManagedAsset_whenRescueQueued_reverts] |
| I-05 | Each queue role separately | Retired asset, with zero debt/positive balance | RD AssetManaged(asset); Unchanged | No new action | Covered: [rescue queued][test_givenManagedAsset_whenRescueQueued_reverts] |
| I-04 | Each queue role separately | NeverListed token with controlled balanceOf failure | Exact preview dependency error; Unchanged | No new action | Covered: [balance query reverts][test_whenBalanceQueryReverts_reverts] |

## Conflict keys

| ID | Caller | Existing pending request / new request | Queue / effects | Test |
| --- | --- | --- | --- | --- |
| Q-01 | Each queue role separately | Same-asset surplus rescue (same/different destination), or valid route action; guarantee rescue→route and route→rescue orders | ConfigKeyPending(Key, owningId); Unchanged; existing request remains usable | Covered: [rescue and route queues conflict][test_givenAssetKeyOwned_whenRescueAndRouteQueuesConflict] |
| Q-02 | Each queue role separately | Different-asset rescues, or rescue plus independent yield-recipient action | Both queued with independent keys; either execution order affects only the owning keys/state | Covered: [surplus rescue queued and executed in either order][test_givenIndependentAsset_whenSurplusRescueQueuedAndExecutedInEitherOrder], [surplus rescue queued and executed in either order][test_givenYieldConfigurationAction_whenSurplusRescueQueuedAndExecutedInEitherOrder] |

The key is also shared with pending-payout rescue, but both surplus and pending requests cannot be valid simultaneously for the same asset through public flows: surplus requires NeverListed; pending debt requires a managed asset. The mixed-batch cases below prove that the invalid second request's preview runs before the shared-key conflict without fabricating a successful overlap.

## Mixed-batch rescue preview precedence

The second rescue request is validated before its shared-key conflict is checked. Its preview error therefore rejects the complete batch and rolls back the first sub-action's provisional key acquisition and action ID.

| ID | Caller | Ordered batch | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| I-06 | Each queue role separately | NeverListed asset: valid surplus rescue, then positive pending-payout rescue for the same asset | RevenueDistributor_InsufficientPendingDistribution(asset,requested,0) before key conflict | No action ID consumed; roll back the first key acquisition | Covered: [evidence][test_givenSurplusThenInvalidPendingRescue_previewFailurePrecedesKeyConflict] |
| I-07 | Each queue role separately | Managed asset with debt: valid pending-payout rescue, then surplus rescue for the same asset | RevenueDistributor_AssetManaged(asset) before key conflict | No action ID consumed; roll back the first key acquisition | Covered: [evidence][test_givenPendingThenInvalidSurplusRescue_previewFailurePrecedesKeyConflict] |

[test_givenSurplusThenInvalidPendingRescue_previewFailurePrecedesKeyConflict]: ./queueRescue.t.sol#L50
[test_givenPendingThenInvalidSurplusRescue_previewFailurePrecedesKeyConflict]: ./queueRescue.t.sol#L93

## Changes during delay and transfers

| ID | Caller | Change after queue | Ready execution / effects | Test |
| --- | --- | --- | --- | --- |
| LIVE-01 | Any executor | Receive 5 more units after queueing B=7 | Pay full live 12; no stale-balance rejection | Covered: [custody increases][test_givenQueuedRescue_whenCustodyIncreases] |
| LIVE-02 | Any executor | Another direct rescue clears B=7 | No-op payment; no token call/RD rescue event; action completes | Covered: [admin already rescued][test_givenQueuedRescue_whenAdminAlreadyRescued] |
| LIVE-03 | Any executor | NeverListed becomes Active | ConfigStateChanged(id,index,Key,expectedHash,currentHash); Unchanged | Covered: [activated][test_givenQueuedNeverListedAsset_whenActivated_reverts] |
| LIVE-04 | Any executor | NeverListed becomes Active then Retired | ConfigStateChanged(id,index,Key,expectedHash,currentHash); Unchanged | Covered: [activated then retired][test_givenQueuedNeverListedAsset_whenActivatedThenRetired_reverts] |
| LIVE-05 | Any executor | RD becomes Kernel-inactive after queue | RD PolicyInactive(); Unchanged; reactivation permits payment retry | Covered: [deactivation during delay][test_givenQueuedSurplusRescue_whenDistributorBecomesInactive_revertsThenRetries] |
| TX-01 | Any executor | Positive live B; transfer rejects destination | Queue succeeded; bubble exact token error at execution; Unchanged; unblock and retry once | Covered: [transfer fails then recovers][test_givenQueuedSurplus_whenTransferFailsThenRecovers] |

RD's transfer/callback matrix owns false-return and guard behavior. Generic callback reexecution/cancellation belongs to executeQueuedAction tests.

[test_givenDistributorLocalStates_whenEachRoleQueuesAndAnyExecutorExecutes]: ./queueRescue.t.sol#L125
[test_givenPermissionlessExecutorIdentities_whenSeeded]: ./queueRescue.t.sol#L151
[test_givenEnabledActiveSelectedTimelock_whenCallerUnauthorized_reverts]: ./queueRescue.t.sol#L171
[test_givenUnauthorizedIdentities_whenQueueing_reverts]: ./queueRescue.t.sol#L192
[test_givenTimelockDisabled_whenRescueQueued_reverts]: ./queueRescue.t.sol#L200
[test_givenQueuedRescue_whenTimelockDisabled_reverts]: ./queueRescue.t.sol#L253
[test_givenTimelockInactive_whenRescueQueued_reverts]: ./queueRescue.t.sol#L215
[test_givenQueuedRescue_whenTimelockInactive_reverts]: ./queueRescue.t.sol#L265
[test_givenOperatorRemoved_whenRescueQueued_reverts]: ./queueRescue.t.sol#L235
[test_givenDistributorInactive_whenSurplusRescueQueued_reverts]: ./queueRescue.t.sol#L282
[test_givenZeroCustodyAtQueue_whenExecuted]: ./queueRescue.t.sol#L159
[test_whenAssetHasNoCode_reverts]: ./queueRescue.t.sol#L334
[test_whenDestinationIsForbidden_reverts]: ./queueRescue.t.sol#L354
[test_givenManagedAsset_whenRescueQueued_reverts]: ./queueRescue.t.sol#L408
[test_whenBalanceQueryReverts_reverts]: ./queueRescue.t.sol#L381
[test_givenAssetKeyOwned_whenRescueAndRouteQueuesConflict]: ./queueRescue.t.sol#L437
[test_givenIndependentAsset_whenSurplusRescueQueuedAndExecutedInEitherOrder]: ./queueRescue.t.sol#L485
[test_givenYieldConfigurationAction_whenSurplusRescueQueuedAndExecutedInEitherOrder]: ./queueRescue.t.sol#L546
[test_givenQueuedRescue_whenCustodyIncreases]: ./queueRescue.t.sol#L608
[test_givenQueuedRescue_whenAdminAlreadyRescued]: ./queueRescue.t.sol#L615
[test_givenQueuedNeverListedAsset_whenActivated_reverts]: ./queueRescue.t.sol#L625
[test_givenQueuedNeverListedAsset_whenActivatedThenRetired_reverts]: ./queueRescue.t.sol#L649
[test_givenQueuedSurplusRescue_whenDistributorBecomesInactive_revertsThenRetries]: ./queueRescue.t.sol#L303
[test_givenQueuedSurplus_whenTransferFailsThenRecovers]: ./queueRescue.t.sol#L676
