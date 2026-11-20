# BurnerLoansRiskConfigTimelock.reEnable scenario plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-REENABLE`. ADMIN/BLA fast reEnable(); no bytes payload. Inherited order: disabled state→ever-enabled history→ADMIN/BLA authorization→inclusive grace→same own/target activation checks as enable. Let L=lastTransitionAt after disabling, G=gracePeriod, H=L+G computed wide then SafeCast.toUint48. R25; AE28,AE34.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## History, caller and grace

Target otherwise ready. All relevant time/history values independent; deterministic deadline-adjacent seeds alongside fuzzing.

| ID | Caller | Local active | Local enabled | History | Now / duration domain | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-REENABLE-L02 | Fuzz every caller | Fuzz false/true | true | Previously enabled | Any | IEnabler.NotDisabled() | Unchanged | Covered: [test_givenEnabled_whenReEnabled_reverts][test_givenEnabled_whenReEnabled_reverts] |
| BLRCT-REENABLE-I01 | Fuzz every caller | Fuzz false/true | false | Never enabled, transition0 | Any | IReEnabler.NeverEnabled() before role/grace | Unchanged | Covered: [test_givenNeverEnabled_whenReEnabled_reverts][test_givenNeverEnabled_whenReEnabled_reverts] |
| BLRCT-REENABLE-A01 | Fuzz caller excluding every ADMIN/BLA; include EMERGENCY-only | true | false | Initialized | Within H | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorized_reverts][test_whenUnauthorized_reverts] |
| BLRCT-REENABLE-N01 | Each ADMIN/BLA proposer class | true | false | Initialized, G>0 | Fuzz L..H; seedL,H-1,H | Success if target ready | New transition=now, enabled true, exact events; settings/actions/reserves retained | Covered: [test_givenWithinGrace_whenReEnabled][test_givenWithinGrace_whenReEnabled] |
| BLRCT-REENABLE-N02 | Each ADMIN/BLA proposer class | true | false | Initialized, H representable | Fuzz H+1..MAX48; seedH+1,MAX48 | GracePeriod_Expired(H) | Unchanged; ADMIN can use full enable after expiry | Covered: [test_givenAfterGrace_whenReEnabled_reverts][test_givenAfterGrace_whenReEnabled_reverts] |
| BLRCT-REENABLE-N03 | Each ADMIN/BLA proposer class | true | false | Initialized | L+G=MAX48+1..MAX48+MAX32; seed first overflow and full endpoint | SafeCastOverflowedUintDowncast(48,wideDeadline) | No arithmetic panic substituted; no transition mutation | Covered: [test_givenDeadlineOverflow_whenReEnabled_reverts][test_givenDeadlineOverflow_whenReEnabled_reverts] |
| BLRCT-REENABLE-N04 | Each ADMIN/BLA proposer class | true | false | Initialized | L+G=MAX48, now=MAX48 | Success if target ready | Exact uint48 deadline accepted; timestamp/events updated once | Covered: [test_givenMaximumDeadline_whenReEnabled][test_givenMaximumDeadline_whenReEnabled] |

## Target readiness

Permitted transition caller; inherited state/history/grace checks already pass. T was compatible at construction; changeable Kernel/lifecycle/operator metadata is rechecked. No recursive Core/Config discovery.

| ID | Caller | Local active | Risk active | Risk enabled | Risk operator | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-REENABLE-L01 | Permitted transition caller | false | true | true | BLRCT | None | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenReEnabled_reverts][test_givenInactive_whenReEnabled_reverts] |
| BLRCT-REENABLE-D01 | Permitted transition caller | true | false | true | BLRCT | None | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenReEnabled_reverts][test_givenRiskUnavailable_whenReEnabled_reverts] |
| BLRCT-REENABLE-D02 | Permitted transition caller | true | true | false | BLRCT | None | Success | Enable queue; preserve target settings, pending actions and balances | Covered: [test_givenPausedRisk_whenActivated][test_givenPausedRisk_whenActivated] |
| BLRCT-REENABLE-D03 | Permitted transition caller | true | false | false | BLRCT | None | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenReEnabled_reverts][test_givenRiskUnavailable_whenReEnabled_reverts] |
| BLRCT-REENABLE-D04 | Permitted transition caller | true | true | true | Zero/other; seed both | None | BurnerLoansRiskTimelock_NotController() | Unchanged | Covered: [test_givenWrongOperator_whenReEnabled_reverts][test_givenWrongOperator_whenReEnabled_reverts] |
| BLRCT-REENABLE-D05 | Permitted transition caller | true | false | false | BLRCT | Canonical foreign KF | PolicyDependency_KernelMismatch(T,K,KF) | Compatibility before readiness | Covered: [test_givenForeignKernel_whenTransition_reverts][test_givenForeignKernel_whenTransition_reverts] |
| BLRCT-REENABLE-D06 | Permitted transition caller | true | true | true | BLRCT | Malformed/reverting Kernel getter | PolicyDependency_InvalidDependency(T) | Unchanged | Covered: [test_givenFailedKernelRead_whenTransition_reverts][test_givenFailedKernelRead_whenTransition_reverts], [test_givenMalformedKernelRead_whenTransition_reverts][test_givenMalformedKernelRead_whenTransition_reverts], [test_givenDirtyKernelWords_whenTransition_reverts][test_givenDirtyKernelWords_whenTransition_reverts] |
| BLRCT-REENABLE-D07 | Permitted transition caller | true | true | true | Unreadable/dirty operator | Operator metadata | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenFailedOperatorRead_whenTransition_reverts][test_givenFailedOperatorRead_whenTransition_reverts], [test_givenDirtyOperatorRead_whenTransition_reverts][test_givenDirtyOperatorRead_whenTransition_reverts], [test_givenInvalidOperatorMetadata_whenTransition_reverts][test_givenInvalidOperatorMetadata_whenTransition_reverts] |
| BLRCT-REENABLE-P01 | Permitted transition caller | true | true | true | BLRCT | Upstream Core/Config inactive/disabled/reverting getters | Success | enabled=true, transition=now; Enabled and Transition(caller,true,empty,now); settings/actions/reserves preserved | Covered: [test_givenUpstreamPaused_whenTransition][test_givenUpstreamPaused_whenTransition] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

## Activation compatibility

Activation and reactivation require compatible target, ConfigOperator and Enabler interfaces, same Kernel, target Policy activity and this queue selected as configOperator. They do not read the target's enabled status. This allows queue repair while the target remains paused; each queued operation still enforces its own execution requirements. Other transition/caller/history/grace/payload guards retain their existing order.

Caller is authorized and every prerequisite not varied below is valid. An incompatible target leaves lifecycle history, pending actions, reservations, configuration and custody unchanged.

| ID | Target active | Target enabled | Input fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-REENABLE-D08 | true | Fuzz false/true | Reject each consumed interface advertisement; seed every interface | BurnerLoansRiskTimelock_InvalidRisk(Risk) | Unchanged | Covered: [test][test_givenMissingConsumedInterface_whenActivated_reverts] |

[test_givenMissingConsumedInterface_whenActivated_reverts]: reEnable.t.sol#L275

[test_givenAfterGrace_whenReEnabled_reverts]: reEnable.t.sol#L64
[test_givenDeadlineOverflow_whenReEnabled_reverts]: reEnable.t.sol#L75
[test_givenDirtyKernelWords_whenTransition_reverts]: reEnable.t.sol#L230
[test_givenDirtyOperatorRead_whenTransition_reverts]: reEnable.t.sol#L202
[test_givenEnabled_whenReEnabled_reverts]: reEnable.t.sol#L33
[test_givenFailedKernelRead_whenTransition_reverts]: reEnable.t.sol#L154
[test_givenFailedOperatorRead_whenTransition_reverts]: reEnable.t.sol#L185
[test_givenForeignKernel_whenTransition_reverts]: reEnable.t.sol#L137
[test_givenInactive_whenReEnabled_reverts]: reEnable.t.sol#L113
[test_givenInvalidOperatorMetadata_whenTransition_reverts]: reEnable.t.sol#L247
[test_givenMalformedKernelRead_whenTransition_reverts]: reEnable.t.sol#L169
[test_givenMaximumDeadline_whenReEnabled]: reEnable.t.sol#L90
[test_givenNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L25
[test_givenPausedRisk_whenActivated]: reEnable.t.sol#L266
[test_givenRiskUnavailable_whenReEnabled_reverts]: reEnable.t.sol#L100
[test_givenUpstreamPaused_whenTransition]: reEnable.t.sol#L219
[test_givenWithinGrace_whenReEnabled]: reEnable.t.sol#L49
[test_givenWrongOperator_whenReEnabled_reverts]: reEnable.t.sol#L126
[test_whenUnauthorized_reverts]: reEnable.t.sol#L40
