# BurnerLoansPayoutConfigTimelock.executeQueuedAction coverage plan

Shared action existence, terminal-status and execution-window checks precede concrete admission. Execution then requires own Kernel activity before local enablement and target checks; its caller remains permissionless.

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [executeQueuedAction](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-EXECUTE`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=true. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle and selection do not block recovery from an active Payout; its local pause is allowed. Recovery previews reject an inactive Payout. Core must be idle for target mutations. Proposers fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches. Execution caller is permissionless; action existence/flags/time are checked before local admission.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

After successful execution, assert getQueuedAction retains proposer/queuedAt/executableAt/expiresAt, sets executed=true and cancelled=false, and clears its actions. getQueuedActionLength/getQueuedSubAction reject with ActionAlreadyExecuted(id); each former configuration destination is zero, state count is zero, and getQueuedConfigState rejects ConfigStateIndexOutOfBounds(id,index,stateIndex,0). pendingActionId(key)=0 only for this action's keys. Failed execution preserves all of those stored values and key owners. Fuzz the read caller independently of the executor; stored reads require no target calls or lifecycle admission.

## Pending action states

| ID | Caller | State | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-I01 | Fuzz executor | Unknown id0 or fuzz1..MAX64, excluding queued IDs | ActionNotFound(id) | getQueuedAction/Length/SubAction also reject ActionNotFound(id), regardless of subIndex; configuration destination/count return zero; config-state read rejects ConfigStateIndexOutOfBounds(id,subIndex,stateIndex,0), fuzz indices 0..MAX256 with explicit 0,1,MAX256 seeds | Covered: [test_whenUnknownActionReadOrExecuted_reverts][test_whenUnknownActionReadOrExecuted_reverts], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |
| BLCUCT-EXECUTE-I02 | Fuzz executor | Already executed | ActionAlreadyExecuted(id) | No second dispatch; retained metadata and cleared getter state remain unchanged | Covered: [test_givenExecuted_whenExecutedAgain_reverts][test_givenExecuted_whenExecutedAgain_reverts] |
| BLCUCT-EXECUTE-I03 | Fuzz executor | Already cancelled | ActionCancelled(id) | No dispatch; metadata retains cancelled=true; length/sub-action reads reject ActionCancelled(id); destination/count remain zero | Covered: [test_givenCancelled_whenExecuted_reverts][test_givenCancelled_whenExecuted_reverts] |

## Timing

| ID | Caller | Time | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-N01 | Fuzz executor | now<executableAt; seed one second before | ActionNotReady(id,executableAt) | Keys/action retained | Covered: [test_givenBeforeNotice_whenExecuted_reverts][test_givenBeforeNotice_whenExecuted_reverts], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |
| BLCUCT-EXECUTE-N02 | Fuzz executor | Fuzz executableAt..expiresAt; seed both edges | Success | Execute in order; exact target/queue events; release keys and delete payload/guards | Covered: [test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup][test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup], [test_whenExactlyReady_thenExecuted][test_whenExactlyReady_thenExecuted], [test_whenExactlyAtExpiry_thenExecuted][test_whenExactlyAtExpiry_thenExecuted] |
| BLCUCT-EXECUTE-N03 | Fuzz executor | now>expiresAt; seed one second after | ActionExpired(id,expiresAt) | No automatic key release | Covered: [test_givenAfterExpiry_whenExecuted_reverts][test_givenAfterExpiry_whenExecuted_reverts], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |

## Lifecycle

Pending time-valid request.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-L01 | Fuzz executor | true | true | Success with unchanged commitments | Target dispatch only after time checks | Covered: [test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup][test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup], [test_whenExactlyReady_thenExecuted][test_whenExactlyReady_thenExecuted] |
| BLCUCT-EXECUTE-L02 | Fuzz executor | true | false | NotEnabled() | Action/key retained | Covered: [test_givenActiveDisabled_whenExecuted_reverts][test_givenActiveDisabled_whenExecuted_reverts] |
| BLCUCT-EXECUTE-L03 | Fuzz executor | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Action/key retained | Covered: [test_givenInactiveEnabled_whenExecuted_reverts][test_givenInactiveEnabled_whenExecuted_reverts] |
| BLCUCT-EXECUTE-L04 | Fuzz executor | false | false | BurnerLoans_PolicyNotActive(TL) | Action/key retained | Covered: [test_givenInactiveDisabled_whenExecuted_reverts][test_givenInactiveDisabled_whenExecuted_reverts] |

## Commitments and concrete targets

All other admission/time prerequisites pass. Pending amounts/balances stay live and are not committed. ADMIN distributor replacement is allowed while a flag proposal is pending; the proposal retains its key but rejects execution if the recorded distributor differs from the current one.

| ID | Caller | Drift | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-D01 | Fuzz executor | Bound Payout Kernel changed | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | No dispatch | Covered: [test_givenTargetKernelChanged_whenExecuted_reverts][test_givenTargetKernelChanged_whenExecuted_reverts] |
| BLCUCT-EXECUTE-D02 | Fuzz executor | Controller address changed | ConfigStateChanged(id,index,key,expected,current) | No unauthorized dispatch; action/key retained | Covered: [test_givenControllerReplaced_whenQueuedActionExecutes_reverts][test_givenControllerReplaced_whenQueuedActionExecutes_reverts] |
| BLCUCT-EXECUTE-D03 | Fuzz executor | Each committed flag/pointer/Treasury changes for the affected selector | ConfigStateChanged(id,index,key,expected,current) | No setter call; prior batch writes roll back | Covered: [test_givenEachPendingRescueCommitmentChanged_whenExecuted_reverts][test_givenEachPendingRescueCommitmentChanged_whenExecuted_reverts], [test_givenFeeOrYieldFlagChanged_whenExecuted_reverts][test_givenFeeOrYieldFlagChanged_whenExecuted_reverts] |
| BLCUCT-EXECUTE-D04 | Fuzz executor | Old Payout active but deselected; Core selects replacement and is inactive/disabled; old Payout local pause is allowed | Success against immutable old Payout | No migration/retargeting; old controller remains selected | Covered: [test_givenDeselectedActivePayout_whenQueuedRescueExecutes_thenOriginalInstancePays][test_givenDeselectedActivePayout_whenQueuedRescueExecutes_thenOriginalInstancePays] |
| BLCUCT-EXECUTE-D05 | Fuzz all executors | Queued setSendFeesToDistributor; ADMIN replacement of compatible RD A with distinct compatible RD B succeeds, preserving queued payload/hash/key owner; then execute the queued action; controller and current fee flag unchanged; independently seed requested true and false | ConfigStateChanged(id,0,key,expectedHash,currentHash), with expected/current hashes differing only by A/B | Reject before flag setter or transfer; original payload/guard/key retained even for an otherwise no-op false request | Covered: [test_givenFeeDistributorReplaced_whenExecuted_reverts][test_givenFeeDistributorReplaced_whenExecuted_reverts], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |
| BLCUCT-EXECUTE-D06 | Fuzz all executors | Queued setSendYieldToDistributor; ADMIN replacement of compatible RD A with distinct compatible RD B succeeds, preserving queued payload/hash/key owner; then execute the queued action; controller and current yield flag unchanged; independently seed requested true and false | ConfigStateChanged(id,0,key,expectedHash,currentHash), with expected/current hashes differing only by A/B | Reject before flag setter or transfer; original payload/guard/key retained even for an otherwise no-op false request | Covered: [test_givenYieldDistributorReplaced_whenExecuted_reverts][test_givenYieldDistributorReplaced_whenExecuted_reverts], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |

## Target failure and atomic rollback

This forwarding-layer suite owns bounded revert translation; target-specific token/bucket proofs remain at Payout.

| ID | Caller | Failure | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-T01 | Fuzz executor | Late sub-action validation/transfer failure after an earlier real setter succeeds | Exact short downstream error | Restore earlier target writes, executed flag, all keys, payload and logs; corrected retry may succeed | Covered: [test_givenLateDispatchFailure_whenExecuted_thenAtomicRollbackAndRetry][test_givenLateDispatchFailure_whenExecuted_thenAtomicRollbackAndRetry] |
| BLCUCT-EXECUTE-T02 | Fuzz executor | Target revert data empty | SubActionCallFailed(selector) | Whole transaction rollback | Covered: [test_givenEmptyRevert_whenExecuted_reverts][test_givenEmptyRevert_whenExecuted_reverts] |
| BLCUCT-EXECUTE-T03 | Fuzz executor | Target revert length1..255, seed1,255 | Exact original bytes | Whole transaction rollback | Covered: [test_givenShortRevert_whenExecuted_thenExactBytes][test_givenShortRevert_whenExecuted_thenExactBytes], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |
| BLCUCT-EXECUTE-T04 | Fuzz executor | Target revert exactly256 bytes | SubActionCallFailed(selector) | Bounded copy and rollback | Covered: [test_givenExactCapRevert_whenExecuted_thenWrapped][test_givenExactCapRevert_whenExecuted_thenWrapped] |
| BLCUCT-EXECUTE-T05 | Fuzz executor | Target revert>256 bytes; seed257 and return-data bomb | SubActionCallFailed(selector) | Bounded copy and rollback | Covered: [test_givenReturnDataBomb_whenExecuted_thenWrapped][test_givenReturnDataBomb_whenExecuted_thenWrapped], [test_whenExecutionBoundarySeedsUsed][test_whenExecutionBoundarySeedsUsed] |

## Callbacks

Ensure nested action is otherwise pending/time-valid/admitted so it reaches the intended guard.

| ID | Caller | Nested route | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-C01 | Fuzz executor | Target callback executes the same action; caught failure | Nested ActionAlreadyExecuted(id); outer completes | Exactly one target dispatch/key release | Covered: [test_givenSameActionCallbackCaught_whenExecuted_thenOneDispatch][test_givenSameActionCallbackCaught_whenExecuted_thenOneDispatch] |
| BLCUCT-EXECUTE-C02 | Fuzz executor | Same nested failure propagates | Exact nested error through bounded wrapper | All outer state/earlier target writes roll back | Covered: [test_givenSameActionCallbackPropagates_whenExecuted_thenRollback][test_givenSameActionCallbackPropagates_whenExecuted_thenRollback] |
| BLCUCT-EXECUTE-C03 | Fuzz executor | Different pending action touches the same Payout during its local guarded mutation; callback catches failure | Nested ReentrancyGuardReentrantCall(); outer completes | Nested queue unchanged; one outer payout only | Covered: [test_givenOtherActionCallbackCaught_whenExecuted_thenNestedQueueRetained][test_givenOtherActionCallbackCaught_whenExecuted_thenNestedQueueRetained] |
| BLCUCT-EXECUTE-C04 | Fuzz executor | Same nested route propagates failure | Exact guard error through bounded wrapper | Both queues and payout roll back; no payout | Covered: [test_givenOtherActionCallbackPropagates_whenExecuted_thenBothQueuesRestored][test_givenOtherActionCallbackPropagates_whenExecuted_thenBothQueuesRestored] |

## Recovery dispatch and live entitlement

These cases belong to executeQueuedAction, after a successfully queued request. They prove exact target dispatch, live validation and queue cleanup. Payout's own rescue/rescuePendingPayout plans own balance arithmetic, bucket overlap, token failures and local reentrancy. Existing IDs are retained from the former queueRescuePendingPayout integration rows. Fixed entitlement/request values below are raw token units. Quantities are not part of the pre-state hash: execution succeeds whenever current eligible entitlement still covers the originally requested amount; insufficient live entitlement is a target validation error, not ConfigStateChanged.

| ID | Caller | Execution pre-state | Expected dispatch / result | Queue assertions | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTRP-P09 | Fuzz all executors | Time-valid pending rescue; concrete target and arguments recorded at queue time | One call to bound Payout.rescuePendingPayout with the exact token, recipient, destination and amount | Successful dispatch clears this action's payload/guards and releases its keys; unrelated action unchanged | Covered: [test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount][test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount], [test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched][test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched], [test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched][test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched], [test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched][test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched] |
| BLCTRP-P10 | Fuzz all executors | Queued entitlement=20, requested amount=5; live entitlement falls to 4; routing/controller unchanged | Target rejects InsufficientPendingPayout(token,5,4); short data propagates exactly | Action remains pending; payload/guards/key owners retained; earlier sub-action writes roll back | Covered: [test_givenLiveEntitlementInsufficient_whenExecuted_thenTargetErrorAndRollback][test_givenLiveEntitlementInsufficient_whenExecuted_thenTargetErrorAndRollback] |
| BLCTRP-P11 | Fuzz all executors | Queued entitlement=20, requested amount=5; live entitlement grows to 30; routing/controller unchanged | Dispatch exactly 5; entitlement growth does not cause ConfigStateChanged | Release this action's keys only after success; no stale queue-time quote is substituted | Covered: [test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount][test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount], [test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched][test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched] |
| BLCTRP-P12 | Fuzz all executors | Queued entitlement=20, requested amount=5; live entitlement falls to 8; routing/controller unchanged | Success; dispatch exactly 5 using current eligibility | Decrease alone does not cause ConfigStateChanged; clear payload/guards and release this action's keys after success | Covered: [test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount][test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount], [test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched][test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched] |
| BLCTRP-P13 | Fuzz all executors | Queued entitlement=20, requested amount=5; live entitlement falls to exactly 5; routing/controller unchanged | Success; dispatch exactly 5 at the live-eligibility boundary | Exact equality accepted; clear payload/guards and release this action's keys after success | Covered: [test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount][test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount], [test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched][test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-D07 | Fuzz permissionless executor | true | true | Queued rescue; Payout deactivated then reactivated | BurnerLoans_PolicyNotActive(Payout); retry succeeds | Failure retains exact action/key/custody; retry pays 123 raw asset units once and clears queue | Covered: [test][test_givenInactivePayout_whenQueuedRescueExecutes_revertsThenRetries] |

## Referral fee recovery during notice

| ID | Executor and target state | Sequence | Expected outcome | Test |
| --- | --- | --- | --- | --- |
| BLCUCT-EXECUTE-P01 | Fuzz permissionless executor; Payout active, enabled/paused independently | Queue a referral-only redirect40; execute after notice | Exact referral rescue event and transfer40; clear referral/aggregate reserves and recipient index; mark executed and release reservations | Covered: [test_givenQueuedReferralRescue_whenExecuted][test_givenQueuedReferralRescue_whenExecuted] |
| BLCUCT-EXECUTE-D08 | Fuzz permissionless executor | Queue redirect40, normal retry pays original referrer during notice, execute with zero live entitlement, then restore40 and retry within the original window | Exact InsufficientPendingPayout(token,40,0); failed dispatch preserves action/keys/custody; restored live entitlement succeeds without requeue | Covered: [test_givenReferralPaidDuringNotice_whenQueuedRescueExecuted_reverts][test_givenReferralPaidDuringNotice_whenQueuedRescueExecuted_reverts] |

[test_givenInactivePayout_whenQueuedRescueExecutes_revertsThenRetries]: ./executeQueuedAction.t.sol#L889

[test_givenActiveDisabled_whenExecuted_reverts]: executeQueuedAction.t.sol#L275
[test_givenAfterExpiry_whenExecuted_reverts]: executeQueuedAction.t.sol#L204
[test_givenBeforeNotice_whenExecuted_reverts]: executeQueuedAction.t.sol#L186
[test_givenCancelled_whenExecuted_reverts]: executeQueuedAction.t.sol#L259
[test_givenControllerReplaced_whenQueuedActionExecutes_reverts]: executeQueuedAction.t.sol#L338
[test_givenDeselectedActivePayout_whenQueuedRescueExecutes_thenOriginalInstancePays]: executeQueuedAction.t.sol#L359
[test_givenEachPendingRescueCommitmentChanged_whenExecuted_reverts]: executeQueuedAction.t.sol#L440
[test_givenEmptyRevert_whenExecuted_reverts]: executeQueuedAction.t.sol#L551
[test_givenEntitlementEqualsFive_whenExecuted_thenFiveDispatched]: executeQueuedAction.t.sol#L884
[test_givenEntitlementFallsToEight_whenExecuted_thenFiveDispatched]: executeQueuedAction.t.sol#L879
[test_givenEntitlementGrowsToThirty_whenExecuted_thenFiveDispatched]: executeQueuedAction.t.sol#L871
[test_givenExactCapRevert_whenExecuted_thenWrapped]: executeQueuedAction.t.sol#L571
[test_givenExecuted_whenExecutedAgain_reverts]: executeQueuedAction.t.sol#L243
[test_givenFeeDistributorReplaced_whenExecuted_reverts]: executeQueuedAction.t.sol#L384
[test_givenFeeOrYieldFlagChanged_whenExecuted_reverts]: executeQueuedAction.t.sol#L488
[test_givenInactiveDisabled_whenExecuted_reverts]: executeQueuedAction.t.sol#L288
[test_givenInactiveEnabled_whenExecuted_reverts]: executeQueuedAction.t.sol#L304
[test_givenLateDispatchFailure_whenExecuted_thenAtomicRollbackAndRetry]: executeQueuedAction.t.sol#L523
[test_givenLiveEntitlementInsufficient_whenExecuted_thenTargetErrorAndRollback]: executeQueuedAction.t.sol#L771
[test_givenLiveEntitlementStillSufficient_whenExecuted_thenExactOriginalAmount]: executeQueuedAction.t.sol#L723
[test_givenOtherActionCallbackCaught_whenExecuted_thenNestedQueueRetained]: executeQueuedAction.t.sol#L658
[test_givenOtherActionCallbackPropagates_whenExecuted_thenBothQueuesRestored]: executeQueuedAction.t.sol#L686
[test_givenReadyAction_whenExecuted_thenExactDispatchAndCleanup]: executeQueuedAction.t.sol#L126
[test_givenReturnDataBomb_whenExecuted_thenWrapped]: executeQueuedAction.t.sol#L579
[test_givenSameActionCallbackCaught_whenExecuted_thenOneDispatch]: executeQueuedAction.t.sol#L612
[test_givenSameActionCallbackPropagates_whenExecuted_thenRollback]: executeQueuedAction.t.sol#L639
[test_givenShortRevert_whenExecuted_thenExactBytes]: executeQueuedAction.t.sol#L559
[test_givenTargetKernelChanged_whenExecuted_reverts]: executeQueuedAction.t.sol#L320
[test_givenYieldDistributorReplaced_whenExecuted_reverts]: executeQueuedAction.t.sol#L412
[test_whenExactlyAtExpiry_thenExecuted]: executeQueuedAction.t.sol#L862
[test_whenExactlyReady_thenExecuted]: executeQueuedAction.t.sol#L853
[test_whenExecutionBoundarySeedsUsed]: executeQueuedAction.t.sol#L813
[test_whenUnknownActionReadOrExecuted_reverts]: executeQueuedAction.t.sol#L222
[test_givenQueuedReferralRescue_whenExecuted]: ./executeQueuedAction.t.sol#L32
[test_givenReferralPaidDuringNotice_whenQueuedRescueExecuted_reverts]: ./executeQueuedAction.t.sol#L79
