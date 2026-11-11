# BurnerLoansRiskConfigTimelock.queueSetReferrerAllowed scenario plan

Source: [queueSetReferrerAllowed](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L159).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-QUEUE-REFERRER`. Signature: `queueSetReferrerAllowed(address referrer,bool allowed)`. Requirement trace: R3,R7-R9,R19,R25; AE10-AE12,AE22,AE29.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Independent domains: max-age, referral BPS and membership(referrer) may be pending simultaneously on the same Risk. Snapshot only the relevant setting plus selected operator; applying another domain must not stale this action. A second pending update to the same global setting or the same referrer still conflicts under the shared queue.

## Caller and local admission

Otherwise valid changed setting, usable T and free key. Proposer calls are real queue entry points; direct target authority is tested in Risk setters.

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-REFERRER-A01 | Fuzz unauthorized proposer; include operator-only and EMERGENCY-only | true | true | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorizedProposer_reverts][test_whenUnauthorizedProposer_reverts] |
| BLRCT-QUEUE-REFERRER-L01 | Each proposer class | false | true | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-L02 | Each proposer class | false | false | BurnerLoans_PolicyNotActive(BLRCT) before pause/auth/input faults | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-L03 | Each proposer class | true | false | IEnabler.NotEnabled() before target/input faults | Unchanged | Covered: [test_givenDisabled_whenQueued_reverts][test_givenDisabled_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-L04 | Each proposer class | true | true; initial/re-enabled/reactivated | Return next action ID | Store queue record only; no Risk setter call | Covered: [test_whenPermittedProposer][test_whenPermittedProposer], [test_givenReEnabled_whenQueued][test_givenReEnabled_whenQueued] |

## Direct Risk admission

Queue operational; permitted proposer; canonical metadata unless a row names its fault. Independently mutate T after initial queue enablement.

| ID | Caller | Risk active | Risk enabled | Risk operator | Metadata / upstream | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-REFERRER-D01 | Each proposer class | false | true | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-D02 | Each proposer class | true | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-D03 | Each proposer class | false | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-D04 | Each proposer class | true | true | Zero or distinct nonzero; seed both | Same K | BurnerLoansRiskTimelock_NotController() | Unchanged; proposer ADMIN does not lend ADMIN identity to queue | Covered: [test_givenOperatorChanged_whenQueued_reverts][test_givenOperatorChanged_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-D05 | Each proposer class | false | false | BLRCT | Readable foreign Kernel KF | PolicyDependency_KernelMismatch(T,K,KF) before readiness | Unchanged | Covered: [test_givenForeignKernel_whenQueued_reverts][test_givenForeignKernel_whenQueued_reverts] |
| BLRCT-QUEUE-REFERRER-D06 | Each proposer class | true | true | BLRCT | Kernel()/isEnabled() fails or returns malformed word; each getter/fault separately | PolicyDependency_InvalidDependency(T) | Unchanged | Covered: [test_givenMalformedKernel_whenQueued_reverts][test_givenMalformedKernel_whenQueued_reverts], [test_givenMalformedEnablement_whenQueued_reverts][test_givenMalformedEnablement_whenQueued_reverts], [test_givenInvalidStatusMetadata_whenQueueRejected][test_givenInvalidStatusMetadata_whenQueueRejected], [test_givenDirtyStatusWords_whenQueueRejected][test_givenDirtyStatusWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-QUEUE-REFERRER-D07 | Each proposer class | true | true | Unreadable/dirty configOperator word | Same K | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenMalformedOperator_whenQueued_reverts][test_givenMalformedOperator_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-QUEUE-REFERRER-D08 | Each proposer class | true | true | BLRCT | Config/Core activity and enablement fuzz independently; getters revert | Return next ID | No Config/Core service read; T remains stored immutable target | Covered: [test_givenUpstreamUnavailable_whenQueued][test_givenUpstreamUnavailable_whenQueued], [test_givenIndependentUpstreamStates_whenQueued][test_givenIndependentUpstreamStates_whenQueued], [test_givenEveryIndependentUpstreamState_whenQueued][test_givenEveryIndependentUpstreamState_whenQueued] |
| BLRCT-QUEUE-REFERRER-D09 | Each proposer class | true | true | BLRCT | Relevant current-setting getter reverts or malformed return; seed BPS/age/membership independently as consumed | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged; no partial state commitment or reservation | Covered: [test_givenMalformedSetting_whenQueued_reverts][test_givenMalformedSetting_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |

## Record, no-op intent and conflicts

No setter is executed on queueing. Numeric input type maximum is accepted for cache age and explicitly rejected for BPS; same-value intent is allowed and will later authorize/no-op on Risk.

| ID | Caller | Input / pending key | Queue result | Record / getter / event proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-REFERRER-N01 | Each proposer class | referrer nonzero EOA/contract; allowed false/true; guarantee both and absent/existing membership; changed from current setting | Return next uint64 ID | target=T; exact selector setReferrerAllowed(address,bool); canonical abi.encode(address referrer,bool allowed); destination T; commitment hashes isReferrerAllowed(referrer) plus selected operator; proposer,Q,E=Q+D,X=E+W; nextID+1 | Covered: [test_whenPermittedProposer][test_whenPermittedProposer], [test_whenMembershipIntent][test_whenMembershipIntent] |
| BLRCT-QUEUE-REFERRER-P01 | Each proposer class | Same value; seed numeric endpoints or both booleans | Return next ID | New intent and reservation recorded; current value unchanged, no Risk event; getQueuedAction/subAction/configDestination/configState match exact independent encoding | Covered: [test_whenMembershipIntent][test_whenMembershipIntent] |
| BLRCT-QUEUE-REFERRER-P02 | Each proposer class | Pending membership(referrer) | IConfigTimelockBatchQueue_ConfigKeyPending(scopedKey,owner) | Original record/hash/reservation retained; no ID consumed or target mutation | Covered: [test_givenPendingMembership_whenOppositeQueued_reverts][test_givenPendingMembership_whenOppositeQueued_reverts] |
| BLRCT-QUEUE-REFERRER-P03 | Each proposer class | Same Risk already has separate pending max-age and referral-BPS actions | Return next ID | All three coexist; membership(r) has its own key, independent of both global keys. Existing records unchanged; no target write; another referrer uses another independent membership key. | Covered: [test_givenOtherDomainsPending_whenQueued][test_givenOtherDomainsPending_whenQueued] |

## Zero and shared membership key

Queue and target admission pass.

| ID | Caller | Referrer | Requested membership / pending intent | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-QUEUE-REFERRER-I01 | Each proposer class | Zero | Fuzz false/true; seed both | BurnerLoans_ZeroAddress() | Unchanged, including zero removal no-op | Covered: [test_whenZeroReferrer_reverts][test_whenZeroReferrer_reverts] |
| BLRCT-QUEUE-REFERRER-P05 | Each proposer class | Same nonzero R | Add pending then remove; reverse order also seeded | IConfigTimelockBatchQueue_ConfigKeyPending(scopedKey,owner) | Both directions use one membership key, regardless of requested boolean | Covered: [test_givenPendingMembership_whenOppositeQueued_reverts][test_givenPendingMembership_whenOppositeQueued_reverts] |
| BLRCT-QUEUE-REFERRER-P06 | Each proposer class | Distinct R1,R2 | Add or remove independently | Separate accepted IDs | Per-address state commitments do not stale unrelated referrers | Covered: [test_givenOtherDomainsPending_whenQueued][test_givenOtherDomainsPending_whenQueued] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenDirtySettingWords_whenQueueRejected]: queueSetReferrerAllowed.t.sol#L354
[test_givenDirtyStatusWords_whenQueueRejected]: queueSetReferrerAllowed.t.sol#L334
[test_givenDisabled_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L45
[test_givenEveryIndependentUpstreamState_whenQueued]: queueSetReferrerAllowed.t.sol#L319
[test_givenForeignKernel_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L80
[test_givenInactive_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L31
[test_givenIndependentUpstreamStates_whenQueued]: queueSetReferrerAllowed.t.sol#L287
[test_givenInvalidSettingMetadata_whenQueueRejected]: queueSetReferrerAllowed.t.sol#L257
[test_givenInvalidStatusMetadata_whenQueueRejected]: queueSetReferrerAllowed.t.sol#L227
[test_givenMalformedEnablement_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L113
[test_givenMalformedKernel_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L96
[test_givenMalformedOperator_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L126
[test_givenMalformedSetting_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L143
[test_givenMetadataShapeSeeds_whenQueueRejected]: queueSetReferrerAllowed.t.sol#L376
[test_givenOperatorChanged_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L67
[test_givenOtherDomainsPending_whenQueued]: queueSetReferrerAllowed.t.sol#L215
[test_givenPendingMembership_whenOppositeQueued_reverts]: queueSetReferrerAllowed.t.sol#L207
[test_givenReEnabled_whenQueued]: queueSetReferrerAllowed.t.sol#L179
[test_givenRiskUnavailable_whenQueued_reverts]: queueSetReferrerAllowed.t.sol#L53
[test_givenUpstreamUnavailable_whenQueued]: queueSetReferrerAllowed.t.sol#L161
[test_whenMembershipIntent]: queueSetReferrerAllowed.t.sol#L198
[test_whenPermittedProposer]: queueSetReferrerAllowed.t.sol#L170
[test_whenUnauthorizedProposer_reverts]: queueSetReferrerAllowed.t.sol#L22
[test_whenZeroReferrer_reverts]: queueSetReferrerAllowed.t.sol#L189
