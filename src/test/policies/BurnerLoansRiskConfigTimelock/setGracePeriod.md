# BurnerLoansRiskConfigTimelock.setGracePeriod scenario plan

Source: [setGracePeriod](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L541).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-GRACE`. ADMIN setter period:uint32; own activity check precedes inherited enabled→ADMIN→nonzero validation. Explicit inherited exception: same valid period emits GracePeriodSet once, without transition reset. No Risk readiness/operator gate.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Authority and boundaries

Cached ROLES usable. New grace period does not change lastTransitionAt and does not cap against a hypothetical future disable timestamp.

| ID | Caller | Local active | Local enabled | period | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-GRACE-A01 | Fuzz non-ADMIN; include BLA/EMERGENCY-only | true | true | Fuzz1..MAX32 | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_whenUnauthorized_reverts][test_whenUnauthorized_reverts] |
| BLRCT-GRACE-L01 | ADMIN | false | Fuzz false/true; seed both | Any uint32 | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenGraceSet_reverts][test_givenInactive_whenGraceSet_reverts] |
| BLRCT-GRACE-L02 | ADMIN | true | false | Any uint32 | IEnabler.NotEnabled() | Unchanged | Covered: [test_givenDisabled_whenGraceSet_reverts][test_givenDisabled_whenGraceSet_reverts] |
| BLRCT-GRACE-I01 | ADMIN | true | true | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [test_whenZeroGrace_reverts][test_whenZeroGrace_reverts] |
| BLRCT-GRACE-N01 | ADMIN | true | true | Fuzz1..MAX32; seed1,MAX32; differs from current | Success | Exact period stored; one GracePeriodSet(period); transition/enabled/actions unchanged | Covered: [test_whenGraceSet][test_whenGraceSet] |
| BLRCT-GRACE-P01 | ADMIN | true | true | Same nonzero period | Success | One GracePeriodSet(period), no timestamp reset or queue/statehash change | Covered: [test_whenGraceSet][test_whenGraceSet] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenDisabled_whenGraceSet_reverts]: setGracePeriod.t.sol#L58
[test_givenInactive_whenGraceSet_reverts]: setGracePeriod.t.sol#L46
[test_whenGraceSet]: setGracePeriod.t.sol#L18
[test_whenUnauthorized_reverts]: setGracePeriod.t.sol#L38
[test_whenZeroGrace_reverts]: setGracePeriod.t.sol#L32
