# BurnerLoansRiskConfigTimelock.queueBatch scenario plan

Source: [queueBatch](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L198).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-BATCH`. queueBatch(BatchAction[]) admits only the three Risk setting selectors. Maximum 15 actions and 15 total config keys; one key per admitted action. R7-R9,R19,R21,R25; AE29,AE31-AE32. The validator and error declarations are implemented in the Risk queue and interface.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Independent domains: max-age, referral BPS and membership(referrer) may be pending simultaneously on the same Risk. Snapshot only the relevant setting plus selected operator; applying another domain must not stale this action. A second pending update to the same global setting or the same referrer still conflicts under the shared queue.

## Caller and local admission

Otherwise valid changed setting, usable T and free key. Proposer calls are real queue entry points; direct target authority is tested in Risk setters.

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-BATCH-A01 | Fuzz unauthorized proposer; include operator-only and EMERGENCY-only | true | true | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorizedProposer_reverts][test_whenUnauthorizedProposer_reverts] |
| BLRCT-BATCH-L01 | Each proposer class | false | true | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-BATCH-L02 | Each proposer class | false | false | BurnerLoans_PolicyNotActive(BLRCT) before pause/auth/input faults | Unchanged | Covered: [test_givenInactive_whenQueued_reverts][test_givenInactive_whenQueued_reverts] |
| BLRCT-BATCH-L03 | Each proposer class | true | false | IEnabler.NotEnabled() before target/input faults | Unchanged | Covered: [test_givenDisabled_whenQueued_reverts][test_givenDisabled_whenQueued_reverts] |
| BLRCT-BATCH-L04 | Each proposer class | true | true; initial/re-enabled/reactivated | Return next action ID | Store queue record only; no Risk setter call | Covered: [test_whenPermittedProposer][test_whenPermittedProposer], [test_givenReEnabled_whenQueued][test_givenReEnabled_whenQueued] |

## Direct Risk admission

Queue operational; permitted proposer; canonical metadata unless a row names its fault. Independently mutate T after initial queue enablement.

| ID | Caller | Risk active | Risk enabled | Risk operator | Metadata / upstream | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-BATCH-D01 | Each proposer class | false | true | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-BATCH-D02 | Each proposer class | true | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-BATCH-D03 | Each proposer class | false | false | BLRCT | Same K | PolicyDependency_NotActive(T) | Unchanged | Covered: [test_givenRiskUnavailable_whenQueued_reverts][test_givenRiskUnavailable_whenQueued_reverts] |
| BLRCT-BATCH-D04 | Each proposer class | true | true | Zero or distinct nonzero; seed both | Same K | BurnerLoansRiskTimelock_NotController() | Unchanged; proposer ADMIN does not lend ADMIN identity to queue | Covered: [test_givenOperatorChanged_whenQueued_reverts][test_givenOperatorChanged_whenQueued_reverts] |
| BLRCT-BATCH-D05 | Each proposer class | false | false | BLRCT | Readable foreign Kernel KF | PolicyDependency_KernelMismatch(T,K,KF) before readiness | Unchanged | Covered: [test_givenForeignKernel_whenQueued_reverts][test_givenForeignKernel_whenQueued_reverts] |
| BLRCT-BATCH-D06 | Each proposer class | true | true | BLRCT | Kernel()/isEnabled() fails or returns malformed word; each getter/fault separately | PolicyDependency_InvalidDependency(T) | Unchanged | Covered: [test_givenMalformedKernel_whenQueued_reverts][test_givenMalformedKernel_whenQueued_reverts], [test_givenMalformedEnablement_whenQueued_reverts][test_givenMalformedEnablement_whenQueued_reverts], [test_givenInvalidStatusMetadata_whenQueueRejected][test_givenInvalidStatusMetadata_whenQueueRejected], [test_givenDirtyStatusWords_whenQueueRejected][test_givenDirtyStatusWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-BATCH-D07 | Each proposer class | true | true | Unreadable/dirty configOperator word | Same K | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged | Covered: [test_givenMalformedOperator_whenQueued_reverts][test_givenMalformedOperator_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLRCT-BATCH-D08 | Each proposer class | true | true | BLRCT | Config/Core activity and enablement fuzz independently; getters revert | Return next ID | No Config/Core service read; T remains stored immutable target | Covered: [test_givenConfigUnavailable_whenRiskOnlyBatchQueued_thenAccepted][test_givenConfigUnavailable_whenRiskOnlyBatchQueued_thenAccepted], [test_givenUpstreamUnavailable_whenQueued][test_givenUpstreamUnavailable_whenQueued], [test_givenIndependentUpstreamStates_whenQueued][test_givenIndependentUpstreamStates_whenQueued], [test_givenEveryIndependentUpstreamState_whenQueued][test_givenEveryIndependentUpstreamState_whenQueued] |
| BLRCT-BATCH-D09 | Each proposer class | true | true | BLRCT | Relevant current-setting getter reverts or malformed return; seed BPS/age/membership independently as consumed | BurnerLoansRiskTimelock_InvalidRisk(T) | Unchanged; no partial state commitment or reservation | Covered: [test_givenMalformedSetting_whenQueued_reverts][test_givenMalformedSetting_whenQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |

## Batch bounds and canonical ABI

Proposer authorized and queue/target ready. A reverted batch preserves nextActionId even if earlier sub-actions acquired keys. Separately test the specified field rather than combining malformed words.

| ID | Caller | Batch length | Target / selector / payload | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRCT-BATCH-I01 | Each proposer class | 0 | Empty | ITimelockBatchQueue_BatchEmpty() | Unchanged | Covered: [test_whenEmpty_reverts][test_whenEmpty_reverts] |
| BLRCT-BATCH-N01 | Each proposer class | Fuzz1..15; seed1,15 | Unique valid domains; use 15 distinct referrers for cap | Success | One ID, ordered payloads; ≤15 keys; no settings change | Covered: [test_whenValidSize][test_whenValidSize], [test_whenPermittedProposer][test_whenPermittedProposer] |
| BLRCT-BATCH-I02 | Each proposer class | 16; larger feasible lengths fuzz separately | Otherwise canonical unique actions | ITimelockBatchQueue_BatchTooLarge(length,15) | Unchanged; do not allocate MAX256-length array; batch length is actual EVM collection size | Covered: [test_whenTooManyActions_reverts][test_whenTooManyActions_reverts] |
| BLRCT-BATCH-I03 | Each proposer class | 1 | Target zero/other Risk/Core/BLC; valid selector and payload | ITimelockBatchQueue_ActionInvalid(target,selector) | Unchanged | Covered: [test_whenWrongTarget_reverts][test_whenWrongTarget_reverts] |
| BLRCT-BATCH-I04 | Each proposer class | 1 | Target T; unknown selector, gross-fee/risk curve setter, oracle/cache-pointer setter; seed each | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged; no widened admin scope | Covered: [test_whenUnknownSelector_reverts][test_whenUnknownSelector_reverts] |
| BLRCT-BATCH-I05 | Each proposer class | 1 | Each admitted selector; payload short/long/empty; exact valid widths32/64/32 | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged; no ABI panic | Covered: [test_whenWrongPayloadLength_reverts][test_whenWrongPayloadLength_reverts] |
| BLRCT-BATCH-I06 | Each proposer class | 1 | BPS word10001..65535 canonical uint16 | BurnerLoansRisk_InvalidReferralFeeBps(bps) | Unchanged | Covered: [test_whenOutOfRangeBps_reverts][test_whenOutOfRangeBps_reverts] |
| BLRCT-BATCH-I07 | Each proposer class | 1 | BPS word65536..MAX256; seed65536,MAX256 | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged; reject dirty narrow word before decoding | Covered: [test_whenDirtyBps_reverts][test_whenDirtyBps_reverts] |
| BLRCT-BATCH-I08 | Each proposer class | 1 | Age wordMAX48+1..MAX256; seed both endpoints | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged | Covered: [test_whenDirtyAge_reverts][test_whenDirtyAge_reverts], [test_givenAgeWordAboveUint48_whenQueued_reverts][test_givenAgeWordAboveUint48_whenQueued_reverts], [test_givenRawAbiN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenRawAbiN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLRCT-BATCH-I09 | Each proposer class | 1 | Referrer wordMAX160+1..MAX256; seed both endpoints | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged | Covered: [test_whenDirtyReferrer_reverts][test_whenDirtyReferrer_reverts] |
| BLRCT-BATCH-I10 | Each proposer class | 1 | Boolean word2..MAX256; seed2,MAX256 | ITimelockBatchQueue_ActionInvalid(T,selector) | Unchanged | Covered: [test_whenDirtyBoolean_reverts][test_whenDirtyBoolean_reverts] |
| BLRCT-BATCH-I11 | Each proposer class | 1 | Referrer zero; boolean canonical false/true | BurnerLoans_ZeroAddress() | Unchanged | Covered: [test_whenZeroReferrer_reverts][test_whenZeroReferrer_reverts] |
| BLRCT-BATCH-P01 | Each proposer class | 2 | Duplicate global key or same referrer with opposite bool; seed each | IConfigTimelockBatchQueue_ConfigKeyPending(scopedKey,thisActionId) | Entire new batch rolled back; no partial keys/events | Covered: [test_whenDuplicateDomain_reverts][test_whenDuplicateDomain_reverts], [test_whenOppositeMembership_reverts][test_whenOppositeMembership_reverts] |
| BLRCT-BATCH-P02 | Each proposer class | 2..15 | Last action invalid or conflicts with older action | Exact failing row error | Earlier reservations/payloads/events and ID advancement roll back; older action untouched | Covered: [test_givenOlderPending_whenLastConflicts_reverts][test_givenOlderPending_whenLastConflicts_reverts] |

## Independent domains and notice

Each proposer class; canonical payloads and no pending collisions.

| ID | Caller | Actions / current settings | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRCT-BATCH-P03 | Each proposer class | Changed max-age + changed referral BPS + membership(r); optionally more distinct referrers, within15 actions | Success | Seed all six permutations of the three setting domains. One batch ID owns three distinct keys and independent current-value/operator commitments. Getters preserve input order; no Risk mutation while pending; no whole-Risk state hash or global configuration key. | Covered: [test_whenThreeDomainsInAnyBatchOrder][test_whenThreeDomainsInAnyBatchOrder] |
| BLRCT-BATCH-N02 | Each proposer class | Q=MAX48-D-W; final expiresAt=MAX48 | Success | Stored Q,E,X exact; no widening of timestamp policy or new delay API | Covered: [test_whenTimestampLastRepresentable][test_whenTimestampLastRepresentable] |
| BLRCT-BATCH-N03 | Each proposer class | Q in MAX48-D-W+1..MAX48, seed first invalid and MAX48 | Panic(0x11) from inherited E or X addition | Entire ID/key/payload/event state rolls back; no shared-base change. Timestamps above MAX48 are outside supported chain-time domain. | Covered: [test_whenTimestampOverflow_reverts][test_whenTimestampOverflow_reverts] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenAgeWordAboveUint48_whenQueued_reverts]: queueBatch.t.sol#L216
[test_givenConfigUnavailable_whenRiskOnlyBatchQueued_thenAccepted]: queueBatch.t.sol#L232
[test_givenDirtySettingWords_whenQueueRejected]: queueBatch.t.sol#L562
[test_givenDirtyStatusWords_whenQueueRejected]: queueBatch.t.sol#L542
[test_givenDisabled_whenQueued_reverts]: queueBatch.t.sol#L291
[test_givenEveryIndependentUpstreamState_whenQueued]: queueBatch.t.sol#L527
[test_givenForeignKernel_whenQueued_reverts]: queueBatch.t.sol#L326
[test_givenInactive_whenQueued_reverts]: queueBatch.t.sol#L277
[test_givenIndependentUpstreamStates_whenQueued]: queueBatch.t.sol#L495
[test_givenInvalidSettingMetadata_whenQueueRejected]: queueBatch.t.sol#L465
[test_givenInvalidStatusMetadata_whenQueueRejected]: queueBatch.t.sol#L435
[test_givenMalformedEnablement_whenQueued_reverts]: queueBatch.t.sol#L359
[test_givenMalformedKernel_whenQueued_reverts]: queueBatch.t.sol#L342
[test_givenMalformedOperator_whenQueued_reverts]: queueBatch.t.sol#L372
[test_givenMalformedSetting_whenQueued_reverts]: queueBatch.t.sol#L389
[test_givenMetadataShapeSeeds_whenQueueRejected]: queueBatch.t.sol#L584
[test_givenOlderPending_whenLastConflicts_reverts]: queueBatch.t.sol#L157
[test_givenOperatorChanged_whenQueued_reverts]: queueBatch.t.sol#L313
[test_givenRawAbiN03Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: queueBatch.t.sol#L251
[test_givenReEnabled_whenQueued]: queueBatch.t.sol#L425
[test_givenRiskUnavailable_whenQueued_reverts]: queueBatch.t.sol#L299
[test_givenUpstreamUnavailable_whenQueued]: queueBatch.t.sol#L407
[test_whenDirtyAge_reverts]: queueBatch.t.sol#L95
[test_whenDirtyBoolean_reverts]: queueBatch.t.sol#L111
[test_whenDirtyBps_reverts]: queueBatch.t.sol#L90
[test_whenDirtyReferrer_reverts]: queueBatch.t.sol#L103
[test_whenDuplicateDomain_reverts]: queueBatch.t.sol#L141
[test_whenEmpty_reverts]: queueBatch.t.sol#L21
[test_whenOppositeMembership_reverts]: queueBatch.t.sol#L149
[test_whenOutOfRangeBps_reverts]: queueBatch.t.sol#L119
[test_whenPermittedProposer]: queueBatch.t.sol#L416
[test_whenThreeDomainsInAnyBatchOrder]: queueBatch.t.sol#L172
[test_whenTimestampLastRepresentable]: queueBatch.t.sol#L185
[test_whenTimestampOverflow_reverts]: queueBatch.t.sol#L196
[test_whenTooManyActions_reverts]: queueBatch.t.sol#L30
[test_whenUnauthorizedProposer_reverts]: queueBatch.t.sol#L268
[test_whenUnknownSelector_reverts]: queueBatch.t.sol#L67
[test_whenValidSize]: queueBatch.t.sol#L45
[test_whenWrongPayloadLength_reverts]: queueBatch.t.sol#L79
[test_whenWrongTarget_reverts]: queueBatch.t.sol#L57
[test_whenZeroReferrer_reverts]: queueBatch.t.sol#L132
