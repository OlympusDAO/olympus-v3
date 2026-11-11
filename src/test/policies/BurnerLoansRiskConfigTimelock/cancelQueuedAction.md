# BurnerLoansRiskConfigTimelock.cancelQueuedAction scenario plan

Source: [cancelQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L167).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Cancellation uses `BurnerLoans_PolicyNotActive(BLRCT)` for own inactivity and ROLES_RequireRole(EMERGENCY_ROLE) for an unauthorized caller. Shared action-existence and terminal-state checks run first; the hook then checks own activity and the EMERGENCY role. It does not check local enablement or read target interfaces, Kernel/status metadata, configuration or operator selection. Target-readiness errors used by queueing, execution and activation are outside this cancellation path.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-CANCEL`. R25; AE33. EMERGENCY role is required, matching DepositManager cancellation. ADMIN/BLA alone do not gain cancellation authority. Shared base existence/terminal validation runs before subject activity and cancellation role. Local queue pause, stale state, expiry, replaced operator, broken/paused/inactive Risk are not cancellation gates.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Cancellation authority and recovery

Existing pending action; independent target metadata may revert. Keep old hashes/payload/key record before call for rollback assertions.

| ID | Caller | Local active | Local enabled | Action timing / target | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-CANCEL-A01 | Fuzz EMERGENCY holders; include ADMIN overlap | true | Fuzz false/true; seed both | Before E / timely / after X; stale or unavailable T; seed each | Success | cancelled flag; all domain keys released; exact cancellation event with caller; no target read or setting/reward change | Covered: [test_givenPending_whenEmergencyCancels][test_givenPending_whenEmergencyCancels] |
| BLRCT-CANCEL-A02 | Fuzz callers excluding all EMERGENCY; include ADMIN-only, BLA-only, proposer, executor | true | Fuzz false/true | Any pending | ROLES_RequireRole(EMERGENCY_ROLE) | Unchanged | Covered: [test_whenUnauthorized_reverts][test_whenUnauthorized_reverts] |
| BLRCT-CANCEL-L01 | EMERGENCY | false | Fuzz false/true | Any pending | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenCancelled_reverts][test_givenInactive_whenCancelled_reverts] |
| BLRCT-CANCEL-I01 | Fuzz every caller | Fuzz false/true | Fuzz false/true | Never queued; id0,nextID,MAX64 | ITimelockBatchQueue_ActionNotFound(id) | No local/target reads after base rejection | Covered: [test_whenUnknownID_reverts][test_whenUnknownID_reverts] |
| BLRCT-CANCEL-I02 | Fuzz every caller | true | true | Already executed | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged | Covered: [test_givenExecuted_whenCancelled_reverts][test_givenExecuted_whenCancelled_reverts] |
| BLRCT-CANCEL-I03 | Fuzz every caller | true | false | Already cancelled | ITimelockBatchQueue_ActionCancelled(id) | No double release or duplicate event | Covered: [test_givenCancelled_whenRepeated_reverts][test_givenCancelled_whenRepeated_reverts] |
| BLRCT-CANCEL-P01 | EMERGENCY then proposer | true | true | Cancel expired intent then queue same domain | Success | Old intent not migrated; new record Q and fresh delay; setting/earned rewards unchanged | Covered: [test_givenPending_whenEmergencyCancels][test_givenPending_whenEmergencyCancels], [test_givenExpired_whenCancelledAndRequeued][test_givenExpired_whenCancelledAndRequeued] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenCancelled_whenRepeated_reverts]: cancelQueuedAction.t.sol#L94
[test_givenExecuted_whenCancelled_reverts]: cancelQueuedAction.t.sol#L80
[test_givenExpired_whenCancelledAndRequeued]: cancelQueuedAction.t.sol#L108
[test_givenInactive_whenCancelled_reverts]: cancelQueuedAction.t.sol#L50
[test_givenPending_whenEmergencyCancels]: cancelQueuedAction.t.sol#L17
[test_whenUnauthorized_reverts]: cancelQueuedAction.t.sol#L38
[test_whenUnknownID_reverts]: cancelQueuedAction.t.sol#L68
