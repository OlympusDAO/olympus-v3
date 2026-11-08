# BurnerLoansRiskConfigTimelock.disable scenario plan

Source: [disable](../../../bases/EnablerV2.sol#L72).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-DISABLE`. ADMIN or EMERGENCY may disable(bytes); BLA alone may not. Payload empty; inherited already-disabled rejection precedes caller and payload. Pausing requires no own activity or target readiness. R25.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Containment

Guarantee ADMIN-only, EMERGENCY-only and overlap for accepted callers. T metadata may be malformed/unavailable, and operator selection may already be lost.

| ID | Caller | Local active | Local enabled | Payload | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-DISABLE-P01 | ADMIN or EMERGENCY | Fuzz false/true; seed both | true | Empty | Success without target/Core/Config reads | enabled=false; lastTransitionAt=now; Disabled and Transition(caller,false,empty,now); actions/keys/settings/rewards unchanged | Covered: [test_whenAdminOrEmergencyDisables][test_whenAdminOrEmergencyDisables] |
| BLRCT-DISABLE-A01 | Fuzz caller excluding every ADMIN and EMERGENCY; include BLA-only | Fuzz false/true | true | Empty | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorized_reverts][test_whenUnauthorized_reverts] |
| BLRCT-DISABLE-L01 | Fuzz every caller | Fuzz false/true | false | Empty/nonempty | IEnabler.NotEnabled() before auth/hooks | Unchanged | Covered: [test_givenDisabled_whenDisabledAgain_reverts][test_givenDisabled_whenDisabledAgain_reverts] |
| BLRCT-DISABLE-I01 | ADMIN or EMERGENCY | Fuzz false/true | true | Nonempty bytes; seed1 byte,32 bytes | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test_whenNonemptyPayload_reverts][test_whenNonemptyPayload_reverts] |
| BLRCT-DISABLE-P02 | ADMIN or EMERGENCY then EMERGENCY | true | true before pause | Empty | Disable then cancel pending action while paused | No target-dependent re-enable required just to cancel; cancellation releases keys only | Covered: [test_givenDisabled_whenPendingCancelled][test_givenDisabled_whenPendingCancelled] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenDisabled_whenDisabledAgain_reverts]: disable.t.sol#L48
[test_givenDisabled_whenPendingCancelled]: disable.t.sol#L63
[test_whenAdminOrEmergencyDisables]: disable.t.sol#L19
[test_whenNonemptyPayload_reverts]: disable.t.sol#L56
[test_whenUnauthorized_reverts]: disable.t.sol#L40
