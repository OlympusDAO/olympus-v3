# BurnerLoansRiskConfigTimelock.queueSetReferralFeeBps scenario plan

Source: [queueSetReferralFeeBps](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L135).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-QUEUE-BPS`. Signature: `queueSetReferralFeeBps(uint16 bps)`. Requirement trace: R4,R7-R9,R19,R25; AE10,AE29,AE35.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Independent domains: max-age, referral BPS and membership(referrer) may be pending simultaneously on the same Risk. Snapshot only the relevant setting plus selected operator; applying another domain must not stale this action. A second pending update to the same global setting or the same referrer still conflicts under the shared queue.

## Caller and local admission

Otherwise valid changed setting, usable T and free key. Proposer calls are real queue entry points; direct target authority is tested in Risk setters.

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-BPS-A01 | Fuzz unauthorized proposer; include operator-only and EMERGENCY-only | true | true | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorizedProposer_reverts][test_whenUnauthorizedProposer_reverts] |
| BLRCT-QUEUE-BPS-L01 | Each proposer class | false | true | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-L02 | Each proposer class | false | false | BurnerLoans_PolicyNotActive(BLRCT) before pause/auth/input faults | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-L03 | Each proposer class | true | false | IEnabler.NotEnabled() before target/input faults | Unchanged | Covered: [test_givenDisabled_whenQueued_reverts][test_givenDisabled_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-L04 | Each proposer class | true | true; initial/re-enabled/reactivated | Return next action ID | Store queue record only; no Risk setter call | Covered: [test_whenPermittedProposer][test_whenPermittedProposer], [test_givenReEnabled_whenQueued][test_givenReEnabled_whenQueued] |

## Direct Risk admission

Queue operational; permitted proposer; canonical metadata unless a row names its fault. Independently mutate T after initial queue enablement.

| ID | Caller | Risk active | Risk enabled | Risk operator | Metadata / upstream | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-BPS-D01 | Each proposer class | false | true | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-D02 | Each proposer class | true | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-D03 | Each proposer class | false | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-D04 | Each proposer class | true | true | Zero or distinct nonzero; seed both | Same K | BurnerLoansRiskTimelock_NotController() | Unchanged; proposer ADMIN does not lend ADMIN identity to queue | Covered: [test_givenOperatorChanged_whenQueued_reverts][test_givenOperatorChanged_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-D05 | Each proposer class | false | false | BLRCT | Readable foreign Kernel KF | PolicyDependency_KernelMismatch(T,K,KF) before readiness | Unchanged | Covered: [test_givenForeignKernel_whenQueued_reverts][test_givenForeignKernel_whenQueued_reverts] |
| BLRCT-QUEUE-BPS-D06 | Each proposer class | true | true | BLRCT | Kernel()/isEnabled() fails or returns malformed word; each getter/fault separately | PolicyDependency_InvalidDependency(T) | Unchanged | Covered: [test_givenMalformedKernel_whenQueued_reverts][test_givenMalformedKernel_whenQueued_reverts], [test_givenMalformedEnablement_whenQueued_reverts][test_givenMalformedEnablement_whenQueued_reverts], [test_givenInvalidStatusMetadata_whenQueueRejected][test_givenInvalidStatusMetadata_whenQueueRejected], [test_givenDirtyStatusWords_whenQueueRejected][test_givenDirtyStatusWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-QUEUE-BPS-D07 | Each proposer class | true | true | Unreadable/dirty configOperator word | Same K | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenMalformedOperator_whenQueued_reverts][test_givenMalformedOperator_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-QUEUE-BPS-D08 | Each proposer class | true | true | BLRCT | Config/Core activity and enablement fuzz independently; getters revert | Return next ID | No Config/Core service read; T remains stored immutable target | Covered: [test_givenUpstreamUnavailable_whenQueued][test_givenUpstreamUnavailable_whenQueued], [test_givenIndependentUpstreamStates_whenQueued][test_givenIndependentUpstreamStates_whenQueued], [test_givenEveryIndependentUpstreamState_whenQueued][test_givenEveryIndependentUpstreamState_whenQueued] |
| BLRCT-QUEUE-BPS-D09 | Each proposer class | true | true | BLRCT | Relevant current-setting getter reverts or malformed return; seed BPS/age/membership independently as consumed | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged; no partial state commitment or reservation | Covered: [test_givenMalformedSetting_whenQueued_reverts][test_givenMalformedSetting_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |

## Record, no-op intent and conflicts

No setter is executed on queueing. Numeric input type maximum is accepted for cache age and explicitly rejected for BPS; same-value intent is allowed and will later authorize/no-op on Risk.

| ID | Caller | Input / pending key | Queue result | Record / getter / event proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-BPS-N01 | Each proposer class | 0..10000; seed0,1,9999,10000; changed from current setting | Return next uint64 ID | target=T; exact selector setReferralFeeBps(uint16); canonical abi.encode(uint16 bps); destination T; commitment hashes referralFeeBps plus selected operator; proposer,Q,E=Q+D,X=E+W; nextID+1 | Covered: [test_whenPermittedProposer][test_whenPermittedProposer], [test_whenPercentageBoundaries][test_whenPercentageBoundaries] |
| BLRCT-QUEUE-BPS-P01 | Each proposer class | Same value; seed numeric endpoints or both booleans | Return next ID | New intent and reservation recorded; current value unchanged, no Risk event; getQueuedAction/subAction/configDestination/configState match exact independent encoding | Covered: [test_whenPercentageBoundaries][test_whenPercentageBoundaries], [test_givenMaximumCurrentPercentage_whenSameValueQueued][test_givenMaximumCurrentPercentage_whenSameValueQueued] |
| BLRCT-QUEUE-BPS-P02 | Each proposer class | Pending global referral percentage | IConfigTimelockBatchQueue_ConfigKeyPending(scopedKey,owner) | Original record/hash/reservation retained; no ID consumed or target mutation | Covered: [test_givenPendingPercentage_whenQueuedAgain_reverts][test_givenPendingPercentage_whenQueuedAgain_reverts] |
| BLRCT-QUEUE-BPS-P03 | Each proposer class | Same Risk already has separate pending max-age and membership(r) actions | Return next ID | All three action IDs remain pending with three distinct scoped keys. Age/membership payloads and commitments unchanged; percentage owns only its selector key; no Risk write. Seed all six queue-call orders across this and companion cases. | Covered: [test_givenOtherDomainsPending_whenQueued][test_givenOtherDomainsPending_whenQueued] |

## Invalid percentage

Queue and target admission pass.

| ID | Caller | BPS | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-BPS-I01 | Each proposer class | Fuzz10001..MAX16; seed10001,65535 | BurnerLoansRisk_InvalidReferralFeeBps(bps) | Unchanged; no action ID/key allocation | Covered: [test_whenInvalidPercentage_reverts][test_whenInvalidPercentage_reverts] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenDirtySettingWords_whenQueueRejected]: queueSetReferralFeeBps.t.sol#L363
[test_givenDirtyStatusWords_whenQueueRejected]: queueSetReferralFeeBps.t.sol#L343
[test_givenDisabled_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L45
[test_givenEveryIndependentUpstreamState_whenQueued]: queueSetReferralFeeBps.t.sol#L328
[test_givenForeignKernel_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L80
[test_givenInactive_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L31
[test_givenIndependentUpstreamStates_whenQueued]: queueSetReferralFeeBps.t.sol#L296
[test_givenInvalidSettingMetadata_whenQueueRejected]: queueSetReferralFeeBps.t.sol#L266
[test_givenInvalidStatusMetadata_whenQueueRejected]: queueSetReferralFeeBps.t.sol#L236
[test_givenMalformedEnablement_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L113
[test_givenMalformedKernel_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L96
[test_givenMalformedOperator_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L126
[test_givenMalformedSetting_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L143
[test_givenMaximumCurrentPercentage_whenSameValueQueued]: queueSetReferralFeeBps.t.sol#L412
[test_givenMetadataShapeSeeds_whenQueueRejected]: queueSetReferralFeeBps.t.sol#L385
[test_givenOperatorChanged_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L67
[test_givenOtherDomainsPending_whenQueued]: queueSetReferralFeeBps.t.sol#L222
[test_givenPendingPercentage_whenQueuedAgain_reverts]: queueSetReferralFeeBps.t.sol#L214
[test_givenReEnabled_whenQueued]: queueSetReferralFeeBps.t.sol#L179
[test_givenRiskUnavailable_whenQueued_reverts]: queueSetReferralFeeBps.t.sol#L53
[test_givenUpstreamUnavailable_whenQueued]: queueSetReferralFeeBps.t.sol#L161
[test_whenInvalidPercentage_reverts]: queueSetReferralFeeBps.t.sol#L189
[test_whenPercentageBoundaries]: queueSetReferralFeeBps.t.sol#L202
[test_whenPermittedProposer]: queueSetReferralFeeBps.t.sol#L170
[test_whenUnauthorizedProposer_reverts]: queueSetReferralFeeBps.t.sol#L22
