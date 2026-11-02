# BurnerLoansPayoutConfigTimelock.cancelQueuedAction coverage plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity, then local enablement and EMERGENCY authorization. Cancellation does not probe target readiness or operator selection.

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [cancelQueuedAction](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-CANCEL`. Valid default: real same-Kernel Payout, stored controller=this timelock, cached ROLES initialized, Local active=true and Local enabled=true. Payout has IEnabler, but recovery ignores its paused state; Core lifecycle and selection do not block recovery from an active Payout; its local pause is allowed. Recovery previews reject an inactive Payout. Core must be idle for target mutations. Proposers fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap; distributor replacement is direct ADMIN-only and is not admitted by this queue or batches. Only EMERGENCY_ROLE cancels. Target/controller/Core health must not prevent cancellation. Standard action-state checks precede local/role checks.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

After a successful cancellation, assert getQueuedAction retains its original proposer/timestamps with cancelled=true, executed=false and an empty actions array. getQueuedActionLength/getQueuedSubAction reject ActionCancelled(id); former destinations/counts return zero; getQueuedConfigState rejects ConfigStateIndexOutOfBounds(id,index,stateIndex,0). Only this action's pendingActionId keys are released; unrelated queued actions remain readable and unchanged. Fuzz getter callers independently; broken targets or local lifecycle changes must not gate stored reads.

## Caller authorization

| ID | Caller | Authority | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CANCEL-A01 | Fuzz EMERGENCY holder | Exclusive EMERGENCY; seed overlap with ADMIN | Success | Cancel flag; payload/guards deleted; owned keys released; ActionCancelled | Covered: [test][test_givenEmergencyCaller_whenCancelled_thenExactCleanup], [test][test_whenCancellationBoundarySeedsUsed] |
| BLCUCT-CANCEL-A02 | Fuzz outside every EMERGENCY holder | Seed ADMIN-only, BL admin-only, proposer-only and unrelated | ROLES_RequireRole(EMERGENCY_ROLE) | No cancellation/keys/events | Covered: [test][test_givenNoEmergencyRole_whenCancelled_reverts], [test][test_whenCancellationBoundarySeedsUsed] |

## Lifecycle

Pending action; cached ROLES retained for inactive fixtures.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-CANCEL-L01 | Fuzz EMERGENCY holder | true | true | Success | Exact cancellation effects | Covered: [test][test_givenEmergencyCaller_whenCancelled_thenExactCleanup] |
| BLCUCT-CANCEL-L02 | Fuzz all callers | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabled_whenCancelled_reverts] |
| BLCUCT-CANCEL-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) | Unchanged | Covered: [test][test_givenInactiveEnabled_whenCancelled_reverts] |
| BLCUCT-CANCEL-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenCancelled_reverts] |

## Pending state

| ID | Caller | Action state | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CANCEL-I01 | Fuzz all callers | Unknown id0 or fuzz1..MAX64 excluding real IDs | ActionNotFound(id) | No earlier role/local check; co-located action/length/sub-action getters reject ActionNotFound; configuration count/destination are zero and config-state read rejects its zero-length bounds error | Covered: [test][test_whenUnknownIdCancelled_reverts], [test][test_whenCancellationBoundarySeedsUsed] |
| BLCUCT-CANCEL-I02 | Fuzz all callers | Executed action | ActionAlreadyExecuted(id) | Unchanged | Covered: [test][test_givenExecuted_whenCancelled_reverts] |
| BLCUCT-CANCEL-I03 | Fuzz all callers | Cancelled action | ActionCancelled(id) | Unchanged | Covered: [test][test_givenCancelled_whenCancelled_reverts] |

## Broken target and time independence

Timelock active/enabled; cancellation checks no target binding or current controller selection.

| ID | Caller | Condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-CANCEL-D01 | Fuzz EMERGENCY holder | Before ready, during window, after expiry; independent boundary seeds | Success | Expiry-held keys can be released and reused by a new proposal | Covered: [test][test_givenEmergencyCaller_whenCancelled_thenExactCleanup], [test][test_whenCancellationBoundarySeedsUsed] |
| BLCUCT-CANCEL-D02 | Fuzz EMERGENCY holder | Payout deactivated/retired, different controller or Kernel; kernel()/configOperator() getters reject | Success | No target reads; no transfer or liability change | Covered: [test][test_givenBrokenRetiredTarget_whenCancelled_thenNoTargetReads] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenBrokenRetiredTarget_whenCancelled_thenNoTargetReads]: ./cancelQueuedAction.t.sol#L169
[test_givenCancelled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L153
[test_givenActiveDisabled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L82
[test_givenEmergencyCaller_whenCancelled_thenExactCleanup]: ./cancelQueuedAction.t.sol#L19
[test_givenExecuted_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L139
[test_givenInactiveEnabled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L109
[test_givenNoEmergencyRole_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L70
[test_whenCancellationBoundarySeedsUsed]: ./cancelQueuedAction.t.sol#L183
[test_whenUnknownIdCancelled_reverts]: ./cancelQueuedAction.t.sol#L124
[test_givenInactiveDisabled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L94
