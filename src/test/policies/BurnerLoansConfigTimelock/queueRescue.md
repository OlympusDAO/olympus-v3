# BurnerLoansConfigTimelock.queueRescue coverage plan

Scope: surplus-rescue queue validation/storage and rescue-specific integration at execution. BLCT = BurnerLoansConfigTimelock; BLC = bound BurnerLoansConfig; BL = BLC's BurnerLoans. Generic execution gates, timing boundaries, action flags, key release after cancel/expiry and malformed batch encodings belong to [execute](./execute.t.sol), [cancel](./cancel.t.sol) and [queueBatch](./queueBatch.t.sol).

## Domains and assertions

- Queue callers: Admin = ADMIN_ROLE holder; Burner Loans Admin = BURNER_LOANS_ADMIN_ROLE holder. Test each separately. Fuzz unauthorized callers excluding exactly authorized identities; seed zero, emergency-only and operator-only callers. No dual-role case.
- Default: BLCT/BLC enabled and Kernel-active; BLCT is BLC's current operator; BLC is BL's current Configurator; BL enabled and active. BLCT/BLC must be enabled and Kernel-active. BL may be locally disabled. A disabled or Kernel-inactive BLCT blocks queueing, execution and cancellation; direct admin recovery goes through BL. Both rescue previews reject Kernel-inactive BL, so queueing requires BL activity.
- B = BL token custody; R = pending reserve; S = max(B−R,0), in token base units. Ordinary debt buckets: keeper rewards=10, fees=20, seizure=30; surplus=5. Queue stores token/destination, never an amount. Use fixed quantities here; BL's [rescue plan](../BurnerLoans/rescue.md) owns numeric extremes and full owner partitions.
- Key = scope(BLC, hash(BURNER_LOANS_RESCUE, rescue selector, token)). Same-token surplus rescues conflict regardless of destination. Pending rescue uses a different selector plus token/recipient: same-token surplus and pending rescues may coexist.
- Queued: return actionId, increment nextActionId once; store proposer, BLC target, rescue selector, exact 64-byte token/destination payload, ready/expiry, facility hash and Key owner. Assert exact ConfigStateQueued → TimelockSubActionQueued → TimelockActionQueued events. No custody, debt or configuration changes.
- Executed: any executor at a ready timestamp; fuzz caller without exclusions. Pay live S once if positive; preserve each debt/aggregate/index and other tokens/configuration. Assert BL AssetRescued/Transfer once for positive S, then sub-action/action execution events. Mark completed and clear owned payload/guards/Key. For S=0 complete without token call or BL rescue event.
- Unchanged: balances, debt/index/configuration, counter, action payload/guards/flags and key owner unchanged; no committed events. Failed execution retains the action for a corrected retry before expiry. Error names use their declaring interface's full prefix below.
- Each row links to tests with reciprocal Scenarios comments.

## Authorization and queue lifecycle

Use valid token/destination, B=65, R=60, S=5. Every successful row queues without payment, then executes a nonzero rescue.

BLC and BL are Enabled and Kernel-active in the timelock table.

| ID | Caller | BLCT local state | BLCT Kernel membership | Operator status | Queue and execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| L-01 | Admin | Enabled | Active | Selected | Queued; pay 5 when ready | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| L-02 | Burner Loans Admin | Enabled | Active | Selected | Queued; pay 5 when ready | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| L-03 | Fuzz unauthorized caller | Enabled | Active | Selected | IPolicyAdmin.NotAuthorised(); Unchanged | Covered: [fuzzed callers][test_givenValidTimelock_whenUnauthorizedCallerQueues_reverts], [caller identities][test_givenUnauthorizedIdentities_whenQueueing_reverts] |
| L-04 | Admin; Burner Loans Admin separately | Disabled | Active | Selected | Typed and batch queue revert IEnabler.NotEnabled(); no ID/guard/key or payment | Covered: [rescue queued][test_givenTimelockDisabled_whenRescueQueued_reverts] |
| L-05 | Admin; Burner Loans Admin separately | Enabled | Inactive | Selected | BurnerLoansConfigTimelock_PolicyInactive(BLCT); Unchanged | Covered: [rescue queued][test_givenTimelockInactive_whenRescueQueued_reverts], [timelock inactive][test_givenQueuedRescue_whenTimelockInactive_reverts] |
| L-07 | Admin; Burner Loans Admin separately | Enabled | Active | Not selected | BurnerLoansConfig_UnauthorizedConfigOperator(BLCT); Unchanged | Covered: [rescue queued][test_givenOperatorRemoved_whenRescueQueued_reverts] |
| BLCT-E12 | Executor | Disabled after queue | Active | Selected | NotEnabled; no payment; action/key retained | Covered: [timelock disabled][test_givenQueuedRescue_whenTimelockDisabled_reverts] |

BLCT is Enabled, Kernel-active and selected throughout the downstream table. BLC is Enabled/Active in BL rows. BL is Enabled/Active in L-06; L-08 crosses BL Enabled/Disabled while Active.

| ID | Caller | Policy | Local state | Kernel membership | Queue and execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| L-06 | Admin; Burner Loans Admin separately | BLC | Enabled | Inactive | BurnerLoansConfigTimelock_PolicyInactive(BLC); Unchanged | Covered: [rescue queued][test_givenConfigInactive_whenRescueQueued_reverts], [config inactive][test_givenQueuedRescue_whenConfigInactive_reverts] |
| L-08 | Admin; Burner Loans Admin separately | BLC | Disabled before queue/execution | Active | NotEnabled at queue/execution; retain pending action/key and all funds | Covered: [rescue queued][test_givenConfigDisabled_whenRescueQueued_reverts], [config disabled][test_givenQueuedRescue_whenConfigDisabled_reverts] |
| L-09 | Admin; Burner Loans Admin separately | BL | Disabled | Active | Queued; pay 5 when ready | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| L-10 | Admin; Burner Loans Admin separately | BL | Enabled/disabled | Inactive | BurnerLoans_PolicyInactive() at queue; Unchanged | Covered: [rescue queued][test_givenFacilityInactive_whenRescueQueued_reverts] |

Competing queue faults follow BLCT enablement → BLCT/BLC activity → caller authorization → operator selection → BLC enabled → preview → conflict. Exercise invalid token beside each earlier failing gate; do not reproduce generic execution gate tests here.

## Queued surplus by bucket state

For each row use Admin and Burner Loans Admin separately. Compare BL preview before queue and preserve raw debts/indexes across queue and execution.

| ID | Caller | BL state | Queue | Ready execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| P-01 | Each queue role | No pending debt; B=5 | Queued | Pay 5; custody=0 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-04 | Each queue role | Only keeper rewards=10; B=15 | Queued | Pay 5; retain reward 10 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-05 | Each queue role | Only fees=20; B=25 | Queued | Pay 5; retain fee 20 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-06 | Each queue role | Only seizure=30; B=35 | Queued | Pay 5; retain seizure 30 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-07 | Each queue role | Reward=10, fee=20; B=35 | Queued | Pay 5; retain reserve 30 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-08 | Each queue role | Reward=10, seizure=30; B=45 | Queued | Pay 5; retain reserve 40 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-09 | Each queue role | Fee=20, seizure=30; B=55 | Queued | Pay 5; retain reserve 50 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-10 | Each queue role | All three buckets; R=60, B=65 | Queued | Pay 5; retain reserve 60 | Covered: [fuzz][test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes], [fixed fixtures][test_givenBucketSubsets_whenLocalStatesAreSeeded] |
| P-02 | Each queue role | B=R=0 or B=R=60; transfer would reject if attempted | Queued | No-op payment; action completes without transfer/error/rescue event | Covered: [queued execution completes][test_givenNoSurplus_whenQueuedExecutionCompletes] |
| P-03 | Each queue role | B=59 below R=60 | Queued | No-op payment; retain underfunded custody/debt; action completes | Covered: [queued execution completes][test_givenNoSurplus_whenQueuedExecutionCompletes] |

## Invalid inputs

One representative underlying failure proves queue-time propagation; invalid destinations also exercise the rescue-specific address restriction.

| ID | Caller | Input | Queue / effects | Test |
| --- | --- | --- | --- | --- |
| I-01 | Each queue role | token=0; valid destination | BurnerLoans_InvalidAsset(0); Unchanged; no ID/key consumed | Covered: [asset has no code][test_whenAssetHasNoCode_reverts] |
| I-02 | Each queue role | destination=0, BL, token, BLC or Kernel | BurnerLoans_InvalidRescueDestination(destination); Unchanged | Covered: [destination is forbidden][test_whenDestinationIsForbidden_reverts] |
| I-03 | Each queue role | Controlled balanceOf failure | Bubble exact preview dependency error; Unchanged | Covered: [balance query reverts][test_whenBalanceQueryReverts_reverts] |
| I-04 | Burner Loans Admin through raw queue harness | 63 or 65 bytes instead of the exact two-word token/destination payload | ITimelockBatchQueue_ActionInvalid(BLC, selector); no preview | Unchanged; no ID/key consumed. Covered: [invalid payload length][test_whenSurplusRescuePayloadLengthIsInvalid_reverts] |

## Conflict keys

| ID | Caller | Existing pending request / new request | Queue / effects | Test |
| --- | --- | --- | --- | --- |
| Q-01 | Each queue role | Surplus rescue for same token; same or different destination | ConfigKeyPending(Key, owningId); Unchanged; original request remains usable | Covered: [same or different destination queued][test_givenSurplusKeyOwned_whenSameOrDifferentDestinationQueued_reverts] |
| Q-02 | Each queue role | Same token: surplus rescue plus pending-payout rescue, and two distinct pending recipients; guarantee both queue orders | All accepted under independent keys; execute either rescue first using amounts valid in both orders; preserve debt except the pending payment | Covered: [queue and execution orders vary][test_givenSurplusAndTwoPendingRecipients_whenQueueAndExecutionOrdersVary] |
| Q-05 | Each queue role | Surplus rescues for different tokens | Both queued; independent key owners; each affects only its token | Covered: [rescues queued and executed][test_givenDifferentTokens_whenRescuesQueuedAndExecuted] |

## Changes during delay and transfers

| ID | Caller | Change after queue | Ready execution / effects | Test |
| --- | --- | --- | --- | --- |
| LIVE-01 | Any executor | Queue B=65/R=60; receive 7 more units | Pay live 12; retain R=60; no stale-balance rejection | Covered: [custody increases][test_givenQueuedRescue_whenCustodyIncreases] |
| LIVE-02 | Any executor | Queue B=65/R=60; pending retry pays 10, leaving B=55/R=50 | Pay 5; preserve remaining reserve 50 | Covered: [keeper retry pays debt][test_givenQueuedRescue_whenKeeperRetryPaysDebt] |
| LIVE-03 | Any executor | Queue B=65/R=60; new pending debt consumes the 5 surplus | No-op payment; action completes and preserves current reserve | Covered: [new debt consumes surplus][test_givenQueuedRescue_whenNewDebtConsumesSurplus] |
| LIVE-04 | Any executor | BL becomes Kernel-inactive after queue | BurnerLoans_PolicyInactive(); Unchanged; reactivation permits payment retry | Covered: [facility becomes inactive reverts then][test_givenQueuedRescue_whenFacilityBecomesInactive_revertsThenRetries] |
| BIND-01 | Any executor | BL selects a different Configurator | NotAuthorised(); Unchanged | Covered: [facility configurator changes][test_givenQueuedRescue_whenFacilityConfiguratorChanges_reverts] |
| TX-01 | Any executor | Token rejects the positive payment | Preview allowed queue; exact token error at execution; Unchanged; unblock and retry once | Covered: [transfer fails then recovers][test_givenQueuedRescue_whenTransferFailsThenRecovers] |

BL's transfer/callback matrix owns false-return and guard behavior. Generic reexecution/cancellation from callbacks belongs to execute/cancel tests; this wrapper needs no duplicate matrix.

[test_givenBucketSubset_whenEachRoleQueuesAndExecutorExecutes]: ./queueRescue.t.sol#L38
[test_givenBucketSubsets_whenLocalStatesAreSeeded]: ./queueRescue.t.sol#L51
[test_givenValidTimelock_whenUnauthorizedCallerQueues_reverts]: ./queueRescue.t.sol#L106
[test_givenUnauthorizedIdentities_whenQueueing_reverts]: ./queueRescue.t.sol#L114
[test_givenTimelockDisabled_whenRescueQueued_reverts]: ./queueRescue.t.sol#L121
[test_givenTimelockInactive_whenRescueQueued_reverts]: ./queueRescue.t.sol#L136
[test_givenQueuedRescue_whenTimelockInactive_reverts]: ./queueRescue.t.sol#L217
[test_givenOperatorRemoved_whenRescueQueued_reverts]: ./queueRescue.t.sol#L187
[test_givenQueuedRescue_whenTimelockDisabled_reverts]: ./queueRescue.t.sol#L205
[test_givenConfigInactive_whenRescueQueued_reverts]: ./queueRescue.t.sol#L169
[test_givenQueuedRescue_whenConfigInactive_reverts]: ./queueRescue.t.sol#L244
[test_givenConfigDisabled_whenRescueQueued_reverts]: ./queueRescue.t.sol#L154
[test_givenQueuedRescue_whenConfigDisabled_reverts]: ./queueRescue.t.sol#L232
[test_givenFacilityInactive_whenRescueQueued_reverts]: ./queueRescue.t.sol#L259
[test_givenNoSurplus_whenQueuedExecutionCompletes]: ./queueRescue.t.sol#L89
[test_whenAssetHasNoCode_reverts]: ./queueRescue.t.sol#L312
[test_whenDestinationIsForbidden_reverts]: ./queueRescue.t.sol#L331
[test_whenBalanceQueryReverts_reverts]: ./queueRescue.t.sol#L356
[test_whenSurplusRescuePayloadLengthIsInvalid_reverts]: ./queueAction.t.sol#L202
[test_givenSurplusKeyOwned_whenSameOrDifferentDestinationQueued_reverts]: ./queueRescue.t.sol#L383
[test_givenSurplusAndTwoPendingRecipients_whenQueueAndExecutionOrdersVary]: ./queueRescue.t.sol#L451
[test_givenDifferentTokens_whenRescuesQueuedAndExecuted]: ./queueRescue.t.sol#L408
[test_givenQueuedRescue_whenCustodyIncreases]: ./queueRescue.t.sol#L536
[test_givenQueuedRescue_whenKeeperRetryPaysDebt]: ./queueRescue.t.sol#L554
[test_givenQueuedRescue_whenNewDebtConsumesSurplus]: ./queueRescue.t.sol#L563
[test_givenQueuedRescue_whenFacilityBecomesInactive_revertsThenRetries]: ./queueRescue.t.sol#L286
[test_givenQueuedRescue_whenFacilityConfiguratorChanges_reverts]: ./queueRescue.t.sol#L587
[test_givenQueuedRescue_whenTransferFailsThenRecovers]: ./queueRescue.t.sol#L603
