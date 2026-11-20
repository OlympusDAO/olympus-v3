# BurnerLoansRiskConfigTimelock.executeQueuedAction scenario plan

Source: [executeQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L138).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-EXECUTE`. Permissionless inherited executeQueuedAction(uint64 id). Shared existence/terminal/window validation precedes BLRCT lifecycle/target checks. Timely failed attempts leave pending action and reservations intact for repair/cancellation; no caller-role replay of proposer. Exact shared error arguments follow ITimelockBatchQueue and IConfigTimelockBatchQueue. R7-R9,R21-R25; AE10,AE23-AE35.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Independent domains: max-age, referral BPS and membership(referrer) may be pending simultaneously on the same Risk. Snapshot only the relevant setting plus selected operator; applying another domain must not stale this action. A second pending update to the same global setting or the same referrer still conflicts under the shared queue.

Cache-age execution cases moved from Config's queue are mapped to the shared Risk-setting rows below. Earlier Core-selected-Risk retarget checks are replaced by P04: this immutable queue continues to configure its original operational Risk after Core selects a replacement.

## Existence, terminal state and time

Fuzz caller across all addresses; guarantee unrelated executor, original proposer, ADMIN, BLA, and no-role caller. Default action is pending; Q,E,X read from actual queued record.

| ID | Caller | Action state | Now domain / seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-EXECUTE-I01 | Fuzz every caller | Never queued ID; seed0,nextID,MAX64 | Any representable time | ITimelockBatchQueue_ActionNotFound(id) | Unchanged before local readiness checks | Covered: [test_whenUnknownID_reverts][test_whenUnknownID_reverts] |
| BLRCT-EXECUTE-I02 | Fuzz every caller | Executed | Within original window | ITimelockBatchQueue_ActionAlreadyExecuted(id) | No duplicate target calls | Covered: [test_givenExecuted_whenRepeated_reverts][test_givenExecuted_whenRepeated_reverts] |
| BLRCT-EXECUTE-I03 | Fuzz every caller | Cancelled | Within original window | ITimelockBatchQueue_ActionCancelled(id) | No target calls | Covered: [test_givenCancelled_whenExecuted_reverts][test_givenCancelled_whenExecuted_reverts] |
| BLRCT-EXECUTE-N01 | Fuzz every caller | Pending | Fuzz Q..E-1; seedQ,E-1 | ITimelockBatchQueue_ActionNotReady(id,E) | Action/key remain pending | Covered: [test_givenPending_whenBeforeNotice_reverts][test_givenPending_whenBeforeNotice_reverts] |
| BLRCT-EXECUTE-N02 | Fuzz every caller | Pending | Fuzz E..X; seedE,E+1,X-1,X | Success if target unchanged/ready | One dispatch per sub-action; executed flag; key release; exact sub-action and final executed events with actual executor | Covered: [test_givenPending_whenWithinWindow][test_givenPending_whenWithinWindow], [test_givenDirectRiskDispatch_whenAgeExecuted_thenApplied][test_givenDirectRiskDispatch_whenAgeExecuted_thenApplied] |
| BLRCT-EXECUTE-N03 | Fuzz every caller | Pending | Fuzz X+1..MAX48; seedX+1,MAX48 | ITimelockBatchQueue_ActionExpired(id,X) | Retain reservations/payload; expiry is not automatic cancellation | Covered: [test_givenPending_whenExpired_reverts][test_givenPending_whenExpired_reverts] |

## Queue and target lifecycle drift

Pending timely valid action; caller permissionless. Seed each row after successful enable/queue; restoring relevant readiness within window permits retry.

| ID | Caller | Local active | Local enabled | Risk active | Risk enabled | Operator | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-EXECUTE-L01 | Fuzz every caller | false | Fuzz false/true | true | true | BLRCT | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenQueueInactive_whenExecuted_reverts][test_givenQueueInactive_whenExecuted_reverts] |
| BLRCT-EXECUTE-L02 | Fuzz every caller | true | false | true | true | BLRCT | IEnabler.NotEnabled() | Unchanged | Covered: [test_givenQueueDisabled_whenExecuted_reverts][test_givenQueueDisabled_whenExecuted_reverts] |
| BLRCT-EXECUTE-D01 | Fuzz every caller | true | true | false | true | BLRCT | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenExecuted_reverts][test_givenRiskUnavailable_whenExecuted_reverts], [test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeExecuted_reverts][test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeExecuted_reverts] |
| BLRCT-EXECUTE-D02 | Fuzz every caller | true | true | true | false | BLRCT | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenExecuted_reverts][test_givenRiskUnavailable_whenExecuted_reverts], [test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeExecuted_reverts][test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeExecuted_reverts] |
| BLRCT-EXECUTE-D03 | Fuzz every caller | true | true | false | false | BLRCT | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenExecuted_reverts][test_givenRiskUnavailable_whenExecuted_reverts], [test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeExecuted_reverts][test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeExecuted_reverts] |
| BLRCT-EXECUTE-D04 | Fuzz every caller | true | true | true | true | Zero/different; seed both | BurnerLoansRiskTimelock_NotController() | Unchanged; ADMIN executor cannot supply target ADMIN authority | Covered: [test_givenOperatorChanged_whenExecuted_reverts][test_givenOperatorChanged_whenExecuted_reverts], [test_givenRiskOperatorRevoked_whenAgeExecuted_thenRejected][test_givenRiskOperatorRevoked_whenAgeExecuted_thenRejected] |

## Metadata and committed-state drift

Timely pending action; other readiness checks pass. Source setters compare current state rather than historical rotation epochs.

| ID | Caller | Intervening change / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-EXECUTE-D05 | Fuzz every caller | Risk reports readable foreign KF after queue | PolicyDependency_KernelMismatch(T,K,KF) | Unchanged; no redirect to another target | Covered: [test_givenForeignRiskKernel_whenExecuted_reverts][test_givenForeignRiskKernel_whenExecuted_reverts], [test_givenRiskKernelDrift_whenAgeExecuted_reverts][test_givenRiskKernelDrift_whenAgeExecuted_reverts] |
| BLRCT-EXECUTE-D06 | Fuzz every caller | Risk kernel/isEnabled getter reverts/dirty ABI | PolicyDependency_InvalidDependency(T) | Unchanged; normalize metadata rather than bubbling arbitrary bytes | Covered: [test_givenFailedRiskStatus_whenExecuted_reverts][test_givenFailedRiskStatus_whenExecuted_reverts], [test_givenInvalidStatusMetadata_whenExecuted_reverts][test_givenInvalidStatusMetadata_whenExecuted_reverts] |
| BLRCT-EXECUTE-D07 | Fuzz every caller | Risk operator getter fails/dirty ABI | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenDirtyRiskOperator_whenExecuted_reverts][test_givenDirtyRiskOperator_whenExecuted_reverts], [test_givenInvalidConfigMetadata_whenExecuted_reverts][test_givenInvalidConfigMetadata_whenExecuted_reverts] |
| BLRCT-EXECUTE-D08 | Fuzz every caller | Relevant current-setting getter reverts/malformed word when recomputing commitment | BurnerLoansRiskTimelock_InvalidRisk(T) | Action/keys remain pending; no uncaught ABI panic or arbitrary candidate error | Covered: [test_givenSettingReadFails_whenExecuted_reverts][test_givenSettingReadFails_whenExecuted_reverts], [test_givenInvalidConfigMetadata_whenExecuted_reverts][test_givenInvalidConfigMetadata_whenExecuted_reverts] |
| BLRCT-EXECUTE-P02 | Fuzz every caller | ADMIN changes relevant bps, membership of queued R, or cache age; seed each domain | IConfigTimelockBatchQueue_ConfigStateChanged(id,index,scopedKey,expectedHash,currentHash) | No target write; retains old action/key for cancellation | Covered: [test_givenRelevantStateChanged_whenExecuted_reverts][test_givenRelevantStateChanged_whenExecuted_reverts], [test_givenAgeDrift_whenAgeExecuted_thenRejected][test_givenAgeDrift_whenAgeExecuted_thenRejected] |
| BLRCT-EXECUTE-P03 | Fuzz every caller | Three separately queued actions for max-age, referral BPS and membership(r), all timely and operator unchanged; queue order and execution order independent | All three succeed in any order | Seed all six queue orders and all six execution orders. Each success releases only its own key and changes only its own setting; other pending actions remain executable with unchanged commitments. No lowest-ID ordering or cross-domain staleness; final three settings/getters/events equal the intended values. | Covered: [test_whenIndependentQueueAndExecutionOrders][test_whenIndependentQueueAndExecutionOrders], [test_whenAllThirtySixIndependentOrderings][test_whenAllThirtySixIndependentOrderings] |
| BLRCT-EXECUTE-P04 | Fuzz every caller | Core chooses replacement Risk T2; old T operational and selected by old queue | Success only on immutable T; T2 unchanged | Never look up Core.risk(); reissuing on T2 requires new queue/new full delay | Covered: [test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted][test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted] |
| BLRCT-EXECUTE-P05 | Fuzz every caller | Queued setting equals current relevant value | Success, target event-free no-op | Queue still executes/emits and releases key; no forged target setter event | Covered: [test_givenSameValueIntent_whenExecuted][test_givenSameValueIntent_whenExecuted], [test_givenSameAge_whenExecuted_thenNoTargetEvent][test_givenSameAge_whenExecuted_thenNoTargetEvent], [test_givenUnchangedExecutedAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenUnchangedExecutedAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLRCT-EXECUTE-P06 | Fuzz every caller | Restored original setting/operator and queue/Risk readiness after temporary drift; seed queue reEnable and Kernel reactivation within the original window | Success | Framework compare-and-set, no historical rotation invalidation | Covered: [test_givenStateAndOperatorRestored_whenExecuted][test_givenStateAndOperatorRestored_whenExecuted] |
| BLRCT-EXECUTE-T01 | Fuzz every caller | Risk target setter returns stable typed custom error | Bubble exact bytes | No executed flag/key release or target writes committed | Covered: [test_givenTargetTypedFailure_whenExecuted_reverts][test_givenTargetTypedFailure_whenExecuted_reverts] |
| BLRCT-EXECUTE-T02 | Fuzz every caller | Risk setter fails with empty/oversized unsafe return data | BurnerLoansRiskTimelock_SubActionCallFailed(selector), following bounded dispatch precedent | Unchanged; no unbounded revert allocation | Covered: [test_givenTargetEmptyFailure_whenExecuted_reverts][test_givenTargetEmptyFailure_whenExecuted_reverts], [test_givenTargetOversizedFailure_whenExecuted_reverts][test_givenTargetOversizedFailure_whenExecuted_reverts] |

## Batch atomicity and in-flight reservations

Use independently valid share/age/referrer sub-actions. These are integration tests of inherited behavior through the new policy, not changes to the shared bases.

| ID | Caller | Batch / callback | Execution | Required proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-EXECUTE-P07 | Fuzz every caller | Earlier sub-action succeeds, later target sub-action reverts or committed state has changed | Exact later error | All earlier setting writes/events, executed flag and key cleanup roll back; old queued payload/hash preserved | Covered: [test_givenBatchLateDrift_whenExecuted_reverts][test_givenBatchLateDrift_whenExecuted_reverts] |
| BLRCT-EXECUTE-C01 | Permissionless executor and synthetic target callback | During target dispatch call executeQueuedAction(same id); callback catches failure | Nested ITimelockBatchQueue_ActionAlreadyExecuted(id); outer success | Terminal flag blocks duplicate; each target write/event once | Covered: [test_givenInFlightTarget_whenSameIDExecutedAgain][test_givenInFlightTarget_whenSameIDExecutedAgain] |
| BLRCT-EXECUTE-C02 | BLA-authorized synthetic callback | During dispatch queue same domain; callback catches failure | Nested IConfigTimelockBatchQueue_ConfigKeyPending(key,id); outer success | Reservations held throughout calls; release after completion only | Covered: [test_givenInFlightReservation_whenNewIntentQueued][test_givenInFlightReservation_whenNewIntentQueued] |
| BLRCT-EXECUTE-P08 | Fuzz every caller | Full batch success then queue new changes for released domains | Success | Old payloads/config records cleanup follows shared getters; terminal id remains executed; fresh ID and full notice for new intent | Covered: [test_givenExecutedDomains_whenRequeued][test_givenExecutedDomains_whenRequeued] |
| BLRCT-EXECUTE-P09 | Handler with authorized proposers/ADMIN/EMERGENCY and arbitrary executors | Stateful queue/execute/cancel/expire/direct-setting-drift/operator-pause-restore sequence over share, age and at least two referrers; vary Kernel activity independently from local enablement | Independent state model | Each live scoped key has exactly one pending owner; failed dispatch/cancellation preserves ownership; terminal actions cannot mutate again; settings change only through successful queued dispatch or authorized direct ADMIN/operator setters; expiry alone never releases; an active queue can cancel while locally paused; queue activation accepts an active paused Risk with operator selection intact, but Risk-setting writes still require Risk enabled; ordinary queueing/execution still require both queue and Risk active/enabled; no setting change alters funded rewards | Covered: [invariant_pendingKeysAndSettingsMatchIndependentModel][invariant_pendingKeysAndSettingsMatchIndependentModel] |
| BLRCT-EXECUTE-P10 | Fuzz every caller | Core/Config active and enabled each independently false/true; their target-discovery getters revert; bound Risk operational and selected operator unchanged | Success | Only immutable T is read/written; no Config/Core lookup or FLOAN write; current queue admission still required | Covered: [test_givenUpstreamUnavailable_whenExecuted][test_givenUpstreamUnavailable_whenExecuted], [test_givenIndependentUpstreamStates_whenExecuted][test_givenIndependentUpstreamStates_whenExecuted], [test_givenEveryIndependentUpstreamState_whenExecuted][test_givenEveryIndependentUpstreamState_whenExecuted], [test_givenConfigUnavailable_whenAgeExecuted_thenApplied][test_givenConfigUnavailable_whenAgeExecuted_thenApplied], [test_givenCoreUnavailable_whenAgeExecuted_thenApplied][test_givenCoreUnavailable_whenAgeExecuted_thenApplied] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[invariant_pendingKeysAndSettingsMatchIndependentModel]: executeQueuedAction.invariants.t.sol#L203
[test_givenAgeDrift_whenAgeExecuted_thenRejected]: executeCacheAge.t.sol#L17
[test_givenBatchLateDrift_whenExecuted_reverts]: executeQueuedAction.t.sol#L265
[test_givenCancelled_whenExecuted_reverts]: executeQueuedAction.t.sol#L144
[test_givenConfigUnavailable_whenAgeExecuted_thenApplied]: executeCacheAge.t.sol#L152
[test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted]: executeQueuedAction.t.sol#L432
[test_givenCoreUnavailable_whenAgeExecuted_thenApplied]: executeCacheAge.t.sol#L165
[test_givenDirectRiskDispatch_whenAgeExecuted_thenApplied]: executeCacheAge.t.sol#L27
[test_givenDirtyRiskOperator_whenExecuted_reverts]: executeQueuedAction.t.sol#L390
[test_givenEveryIndependentUpstreamState_whenExecuted]: executeQueuedAction.t.sol#L521
[test_givenExecutedDomains_whenRequeued]: executeQueuedAction.t.sol#L331
[test_givenExecuted_whenRepeated_reverts]: executeQueuedAction.t.sol#L129
[test_givenFailedRiskStatus_whenExecuted_reverts]: executeQueuedAction.t.sol#L371
[test_givenForeignRiskKernel_whenExecuted_reverts]: executeQueuedAction.t.sol#L354
[test_givenInFlightReservation_whenNewIntentQueued]: executeQueuedAction.t.sol#L476
[test_givenInFlightTarget_whenSameIDExecutedAgain]: executeQueuedAction.t.sol#L461
[test_givenIndependentUpstreamStates_whenExecuted]: executeQueuedAction.t.sol#L490
[test_givenInvalidConfigMetadata_whenExecuted_reverts]: executeQueuedAction.t.sol#L571
[test_givenInvalidStatusMetadata_whenExecuted_reverts]: executeQueuedAction.t.sol#L536
[test_givenOperatorChanged_whenExecuted_reverts]: executeQueuedAction.t.sol#L202
[test_givenPending_whenBeforeNotice_reverts]: executeQueuedAction.t.sol#L89
[test_givenPending_whenExpired_reverts]: executeQueuedAction.t.sol#L113
[test_givenPending_whenWithinWindow]: executeQueuedAction.t.sol#L105
[test_givenQueueDisabled_whenExecuted_reverts]: executeQueuedAction.t.sol#L174
[test_givenQueueInactive_whenExecuted_reverts]: executeQueuedAction.t.sol#L159
[test_givenRelevantStateChanged_whenExecuted_reverts]: executeQueuedAction.t.sol#L220
[test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeExecuted_reverts]: executeCacheAge.t.sol#L114
[test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeExecuted_reverts]: executeCacheAge.t.sol#L80
[test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeExecuted_reverts]: executeCacheAge.t.sol#L97
[test_givenRiskKernelDrift_whenAgeExecuted_reverts]: executeCacheAge.t.sol#L131
[test_givenRiskOperatorRevoked_whenAgeExecuted_thenRejected]: executeCacheAge.t.sol#L46
[test_givenRiskUnavailable_whenExecuted_reverts]: executeQueuedAction.t.sol#L182
[test_givenSameAge_whenExecuted_thenNoTargetEvent]: executeCacheAge.t.sol#L65
[test_givenSameValueIntent_whenExecuted]: executeQueuedAction.t.sol#L237
[test_givenSettingReadFails_whenExecuted_reverts]: executeQueuedAction.t.sol#L409
[test_givenStateAndOperatorRestored_whenExecuted]: executeQueuedAction.t.sol#L250
[test_givenTargetEmptyFailure_whenExecuted_reverts]: executeQueuedAction.t.sol#L293
[test_givenTargetOversizedFailure_whenExecuted_reverts]: executeQueuedAction.t.sol#L312
[test_givenTargetTypedFailure_whenExecuted_reverts]: executeQueuedAction.t.sol#L277
[test_givenUnchangedExecutedAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: executeCacheAge.t.sol#L177
[test_givenUpstreamUnavailable_whenExecuted]: executeQueuedAction.t.sol#L345
[test_whenAllThirtySixIndependentOrderings]: executeQueuedAction.t.sol#L67
[test_whenIndependentQueueAndExecutionOrders]: executeQueuedAction.t.sol#L22
[test_whenUnknownID_reverts]: executeQueuedAction.t.sol#L77
