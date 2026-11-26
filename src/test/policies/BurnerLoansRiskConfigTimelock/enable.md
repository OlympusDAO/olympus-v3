# BurnerLoansRiskConfigTimelock.enable scenario plan

Source: [enable](../../../bases/EnablerV2.sol#L52).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-ENABLE`. ADMIN-only full enable(bytes), including after grace expiry. Payload must be empty. Inherited EnablerV2 order: already-enabled rejection→ADMIN role→payload→own/target readiness. R21,R25; AE28. Lifecycle getter assertions belong here and reEnable/disable.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Transition and payload

ROLES cached from prior activation, so deactivated state has readable authorization. Fresh unconfigured instances are tested via constructor/configureDependencies without assuming the same role-read failure.

| ID | Caller | Local active | Local enabled | Payload | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-ENABLE-A01 | Fuzz non-ADMIN; include BLA-only, EMERGENCY-only | true | false | Empty | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_whenNonAdmin_reverts][test_whenNonAdmin_reverts] |
| BLRCT-ENABLE-L02 | Fuzz every caller | Fuzz false/true | true | Empty or nonempty | IEnabler.NotDisabled() before caller/hooks | Unchanged | Covered: [test_givenEnabled_whenEnabledAgain_reverts][test_givenEnabled_whenEnabledAgain_reverts] |
| BLRCT-ENABLE-I01 | ADMIN | true | false | Nonempty bytes; seed1 byte,32 bytes | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test_whenNonemptyPayload_reverts][test_whenNonemptyPayload_reverts] |
| BLRCT-ENABLE-P02 | ADMIN | true | false | Empty; after initial deploy, pause or grace expiry | Success when target ready | Exact enabled/time/events; pending queue state untouched | Covered: [test_givenReady_whenEnabled][test_givenReady_whenEnabled] |

## Target readiness

Permitted transition caller; inherited state/history/grace checks already pass. T was compatible at construction; changeable Kernel/lifecycle/operator metadata is rechecked. No recursive Core/Config discovery.

| ID | Caller | Local active | Risk active | Risk enabled | Risk operator | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-ENABLE-L01 | Permitted transition caller | false | true | true | BLRCT | None | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenEnabled_reverts][test_givenInactive_whenEnabled_reverts] |
| BLRCT-ENABLE-D01 | Permitted transition caller | true | false | true | BLRCT | None | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenEnabled_reverts][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLRCT-ENABLE-D02 | Permitted transition caller | true | true | false | BLRCT | None | Success | Enable queue; preserve target settings, pending actions and balances | Covered: [test_givenPausedRisk_whenActivated][test_givenPausedRisk_whenActivated] |
| BLRCT-ENABLE-D03 | Permitted transition caller | true | false | false | BLRCT | None | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenEnabled_reverts][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLRCT-ENABLE-D04 | Permitted transition caller | true | true | true | Zero/other; seed both | None | BurnerLoansRiskTimelock_NotController() | Unchanged | Covered: [test_givenWrongOperator_whenEnabled_reverts][test_givenWrongOperator_whenEnabled_reverts] |
| BLRCT-ENABLE-D05 | Permitted transition caller | true | false | false | BLRCT | Canonical foreign KF | PolicyDependency_KernelMismatch(T,K,KF) | Compatibility before readiness | Covered: [test_givenForeignKernel_whenTransition_reverts][test_givenForeignKernel_whenTransition_reverts] |
| BLRCT-ENABLE-D06 | Permitted transition caller | true | true | true | BLRCT | Malformed/reverting Kernel getter | PolicyDependency_InvalidDependency(T) | Unchanged | Covered: [test_givenFailedKernelRead_whenTransition_reverts][test_givenFailedKernelRead_whenTransition_reverts], [test_givenMalformedKernelRead_whenTransition_reverts][test_givenMalformedKernelRead_whenTransition_reverts], [test_givenDirtyKernelWords_whenTransition_reverts][test_givenDirtyKernelWords_whenTransition_reverts] |
| BLRCT-ENABLE-D07 | Permitted transition caller | true | true | true | Unreadable/dirty operator | Operator metadata | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenFailedOperatorRead_whenTransition_reverts][test_givenFailedOperatorRead_whenTransition_reverts], [test_givenDirtyOperatorRead_whenTransition_reverts][test_givenDirtyOperatorRead_whenTransition_reverts], [test_givenInvalidOperatorMetadata_whenTransition_reverts][test_givenInvalidOperatorMetadata_whenTransition_reverts] |
| BLRCT-ENABLE-P01 | Permitted transition caller | true | true | true | BLRCT | Upstream Core/Config inactive/disabled/reverting getters | Success | enabled=true, transition=now; Enabled and Transition(caller,true,empty,now); settings/actions/reserves preserved | Covered: [test_givenReady_whenEnabled][test_givenReady_whenEnabled], [test_givenUpstreamPaused_whenTransition][test_givenUpstreamPaused_whenTransition] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

## Activation compatibility

Activation and reactivation require compatible target, ConfigOperator and Enabler interfaces, same Kernel, target Policy activity and this queue selected as configOperator. They do not read the target's enabled status. This allows queue repair while the target remains paused; each queued operation still enforces its own execution requirements. Other transition/caller/history/grace/payload guards retain their existing order.

Caller is authorized and every prerequisite not varied below is valid. An incompatible target leaves lifecycle history, pending actions, reservations, configuration and custody unchanged.

| ID | Target active | Target enabled | Input fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-ENABLE-D08 | true | Fuzz false/true | Reject each consumed interface advertisement; seed every interface | BurnerLoansRiskTimelock_InvalidRisk(Risk) | Unchanged | Covered: [test][test_givenMissingConsumedInterface_whenActivated_reverts] |

[test_givenMissingConsumedInterface_whenActivated_reverts]: enable.t.sol#L241

[test_givenDirtyKernelWords_whenTransition_reverts]: enable.t.sol#L196
[test_givenDirtyOperatorRead_whenTransition_reverts]: enable.t.sol#L168
[test_givenEnabled_whenEnabledAgain_reverts]: enable.t.sol#L34
[test_givenFailedKernelRead_whenTransition_reverts]: enable.t.sol#L120
[test_givenFailedOperatorRead_whenTransition_reverts]: enable.t.sol#L151
[test_givenForeignKernel_whenTransition_reverts]: enable.t.sol#L103
[test_givenInactive_whenEnabled_reverts]: enable.t.sol#L66
[test_givenInvalidOperatorMetadata_whenTransition_reverts]: enable.t.sol#L213
[test_givenMalformedKernelRead_whenTransition_reverts]: enable.t.sol#L135
[test_givenPausedRisk_whenActivated]: enable.t.sol#L232
[test_givenReady_whenEnabled]: enable.t.sol#L50
[test_givenRiskUnavailable_whenEnabled_reverts]: enable.t.sol#L79
[test_givenUpstreamPaused_whenTransition]: enable.t.sol#L185
[test_givenWrongOperator_whenEnabled_reverts]: enable.t.sol#L92
[test_whenNonAdmin_reverts]: enable.t.sol#L24
[test_whenNonemptyPayload_reverts]: enable.t.sol#L42
