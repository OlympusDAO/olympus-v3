# BurnerLoansRiskConfigTimelock.queueSetPriceCacheMaxAge coverage plan

Source: [queueSetPriceCacheMaxAge](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L184).

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source precedent: [Risk setter](../../../policies/burnerloans/BurnerLoansRisk.sol#L597). This is the existing function matrix moved to the new directly bound Risk timelock, not an API-removal test plan.

Review status: desired BLRCT behavior. The cache-age tests are ported to the immutable Risk queue. The Test column identifies direct-binding, caller, commitment and error evidence; it does not claim coverage from the former Config queue fixture.

Independent domains: max-age, referral BPS and membership(referrer) may be pending simultaneously on the same Risk. Snapshot only the relevant setting plus selected operator; applying another domain must not stale this action. A second pending update to the same global setting or the same referrer still conflicts under the shared queue.

## Domains and notation

Scenario scope: `BLCT-QUEUE-CACHE-AGE`. The BLCT-QUEUE-CACHE-AGE IDs are preserved after moving this matrix to BLRCT. BLRCT binds one immutable Risk directly at construction; no Config.facility() or Core.risk() target discovery occurs. Config, Core and Risk operator addresses are independent.

Permitted proposers are ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only, or both; fuzz independently and guarantee each class. Risk selects BLRCT itself as configOperator; BLRCT holds no ADMIN role. Unauthorized fuzzing excludes every holder of either proposer role. age:uint48 accepts 0..MAX48. No target setter executes during queueing.

Defaults: BLRCT and selected Risk active/enabled in the same Kernel; Risk.configOperator()==BLRCT; action key free; initialized module bindings. Own local enablement and proposer authorization precede target validation. Unchanged means nextActionId, all existing actions/payloads/keys/hashes, Risk age/operator/oracle/cache, Core/FLOAN and token/accounting state unchanged; a reverted transaction commits no logs.

## Authorization

| ID | Caller | Risk operator | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-A01 | Fuzz caller excluding every ADMIN and BL-admin role holder | BLRCT | NotAuthorised() | Unchanged | Covered: [test_givenUnauthorizedProposer_whenAgeQueued_reverts][test_givenUnauthorizedProposer_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A03 | Fuzz permitted proposer | Distinct nonzero address | BurnerLoansRiskTimelock_NotController() | No ADMIN fallback granted to BLRCT; no action/key acquired | Covered: [test_givenRiskOperatorDifferent_whenAgeQueued_reverts][test_givenRiskOperatorDifferent_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A04 | Fuzz permitted proposer | Zero | BurnerLoansRiskTimelock_NotController() | Unchanged | Covered: [test_givenRiskOperatorCleared_whenAgeQueued_reverts][test_givenRiskOperatorCleared_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A05 | Fuzz permitted proposer | BLRCT | Return next action ID | Exact queue record below | Covered: [test_givenPermittedProposer_whenAgeQueued_thenStored][test_givenPermittedProposer_whenAgeQueued_thenStored], [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

Former A02 duplicated unauthorized admission with Config disabled; target independence below covers that state without a second authorization case.

## Local lifecycle

Permitted proposer; Risk ready and independently selects BLRCT. Config lifecycle is not an admission gate for this Risk-targeted action.

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-L01 | Fuzz permitted proposer | true | false | NotEnabled() | Unchanged | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-L05 | Fuzz permitted proposer | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-L09 | Fuzz permitted proposer | false | true | BurnerLoans_PolicyNotActive(BLRCT) | Unchanged | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts] |

The remaining old L02-L04/L06-L08/L10-L15 multiplied Config lifecycle into this direct Risk operation and are retired.

## Target dependencies

Local active/enabled; permitted proposer; Risk operator=BLRCT. No Core selection, Config authority, or upstream lifecycle getter is used. Core/Config getters may revert while the bound Risk remains usable.

| ID | Caller | Risk active | Risk enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-D03 | Fuzz permitted proposer | true | true | Return next ID | No target mutation | Covered: [test_givenOperationalRisk_whenAgeQueued_thenStored][test_givenOperationalRisk_whenAgeQueued_thenStored] |
| BLCT-QUEUE-CACHE-AGE-D04 | Fuzz permitted proposer | false | true | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts][test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D05 | Fuzz permitted proposer | true | false | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts][test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D06 | Fuzz permitted proposer | false | false | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts][test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts] |

| ID | Caller | Binding / independent authority | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-D07 | Fuzz permitted proposer | Immutable Risk reports another Kernel | PolicyDependency_KernelMismatch(Risk,expectedKernel,reportedKernel) | Unchanged | Covered: [test_givenForeignRiskKernel_whenAgeQueued_reverts][test_givenForeignRiskKernel_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D08 | Fuzz permitted proposer | Config active/enabled independently false/true; Config.configOperator differs from BLRCT | Return ID | No Config activity/enablement/operator admission or setter call; target is immutable Risk | Covered: [test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate][test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate], [test_givenIndependentUpstreamStates_whenQueued][test_givenIndependentUpstreamStates_whenQueued], [test_givenEveryIndependentUpstreamState_whenQueued][test_givenEveryIndependentUpstreamState_whenQueued] |
| BLCT-QUEUE-CACHE-AGE-D09 | Fuzz permitted proposer | Core active/enabled independently false/true; Core.risk() may revert or select another Risk | Return ID | No Core lifecycle/target-discovery read or mutation | Covered: [test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate][test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate], [test_givenIndependentUpstreamStates_whenQueued][test_givenIndependentUpstreamStates_whenQueued], [test_givenEveryIndependentUpstreamState_whenQueued][test_givenEveryIndependentUpstreamState_whenQueued] |

## Numeric inputs and queue record

| ID | Caller | Age / current value | Queue result | Effects / getter assertions | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-I01 | Fuzz permitted proposer | 0; old age nonzero | Return ID | Zero is valid, not an invalid input | Covered: [test_givenNonzeroOldAge_whenZeroQueued_thenAccepted][test_givenNonzeroOldAge_whenZeroQueued_thenAccepted] |
| BLCT-QUEUE-CACHE-AGE-N01 | Fuzz permitted proposer | Fuzz 1..MAX48; seed 1,MAX48; old age independently different | Return ID | Canonical 32-byte uint48 ABI payload | Covered: [test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload][test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload], [test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-QUEUE-CACHE-AGE-P01 | Fuzz permitted proposer | Changed age; key free | Return next ID | Store target=immutable Risk, selector=Risk.setPriceCacheMaxAge, payload=abi.encode(age); getQueuedSubAction/getQueuedConfigDestination agree; Risk-scoped selector key; hash=keccak256(abi.encode(Risk.configOperator(),oldAge)); scoped key=keccak256(abi.encode(Risk,keccak256(abi.encode(Risk.setPriceCacheMaxAge.selector)))); exact proposer, ordered payload, queuedAt, +1-day execution and +3-day expiry; queue events from BLRCT; no Risk setter event/write | Covered: [test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget][test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget] |
| BLCT-QUEUE-CACHE-AGE-P07 | Fuzz permitted proposer | Request equals stored age, including 0/MAX48 | Return ID | Queue still records the same target/pre-state; target no-op is checked in executeQueuedAction | Covered: [test_givenSameAge_whenQueued_thenStillCommitted][test_givenSameAge_whenQueued_thenStillCommitted], [test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Queue conflicts

| ID | Caller | Pending keys | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-P02 | Fuzz permitted proposer | Same Risk/selector key owned by pending action | IConfigTimelockBatchQueue_ConfigKeyPending(key,owner) | No ID consumed; original payload/key/hash retained | Covered: [test_givenRiskKeyPending_whenAgeQueuedAgain_reverts][test_givenRiskKeyPending_whenAgeQueuedAgain_reverts] |
| BLCT-QUEUE-CACHE-AGE-P03 | Fuzz permitted proposer | Same Risk has separate pending referral-BPS and membership(r) actions | Return new ID | All three coexist with distinct scoped keys and unchanged earlier records/commitments; no global Risk-wide lock or target mutation | Covered: [test_givenMarketKeyPending_whenAgeQueued_thenIndependent][test_givenMarketKeyPending_whenAgeQueued_thenIndependent] |

## Execution coverage placement

Cache-age drift, Risk replacement, operator/lifecycle drift and successful direct dispatch belong to [executeQueuedAction](executeQueuedAction.md), using the same setting/authority boundaries and immutable-target replacement behavior. Queue tests assert admission and committed data only. [queueBatch](queueBatch.md) covers raw malformed ABI and selector/target allowlisting.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-L10 | Fuzz all callers | false | false | Config.facility() rejects; age=0 | BurnerLoans_PolicyNotActive(TL) | No metadata read or consumed ID | Covered: [test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts][test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts] |

## Additional direct-binding cases

Risk active/enabled, same Kernel, queue active/enabled and selected as Risk operator. Permitted proposer is ADMIN-only, BLA-only or overlap; guarantee each. All reverts preserve IDs, payloads, keys, settings, rewards, balances and committed logs. Product errors are declared in the new timelock interface. Numeric width, timestamp and common batch validation are specified in queueBatch; executeQueuedAction owns live-state drift and inclusive execution boundaries.

| ID | Caller | Condition | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-D10 | Each proposer class | kernel()/isEnabled() reverts or malformed ABI; seed each getter/fault | PolicyDependency_InvalidDependency(Risk) | Unchanged | Covered: [test_givenFailedRiskStatus_whenAgeQueued_reverts][test_givenFailedRiskStatus_whenAgeQueued_reverts], [test_givenInvalidStatusMetadata_whenQueueRejected][test_givenInvalidStatusMetadata_whenQueueRejected], [test_givenDirtyStatusWords_whenQueueRejected][test_givenDirtyStatusWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLCT-QUEUE-CACHE-AGE-D11 | Each proposer class | configOperator() or current age getter reverts/malformed word; seed separately | BurnerLoansRiskTimelock_InvalidRisk(Risk) | Unchanged; no partial commitment | Covered: [test_givenFailedSettingMetadata_whenAgeQueued_reverts][test_givenFailedSettingMetadata_whenAgeQueued_reverts], [test_givenInvalidSettingMetadata_whenQueueRejected][test_givenInvalidSettingMetadata_whenQueueRejected], [test_givenDirtySettingWords_whenQueueRejected][test_givenDirtySettingWords_whenQueueRejected], [test_givenMetadataShapeSeeds_whenQueueRejected][test_givenMetadataShapeSeeds_whenQueueRejected] |
| BLCT-QUEUE-CACHE-AGE-P08 | Each proposer class | Risk remains immutable target; Core selects another instance | Return ID | Only original Risk is committed; new Core selection is neither read nor mutated | Covered: [test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted][test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted] |

- [x] Review the moved matrix and new direct-binding cases.
- [x] Port existing tests to BLRCT, add direct-binding cases, execute and refresh mappings.

[test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: queueSetPriceCacheMaxAge.t.sol#L377
[test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload]: queueSetPriceCacheMaxAge.t.sol#L90
[test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate]: queueSetPriceCacheMaxAge.t.sol#L285
[test_givenCoreSelectsAnotherRisk_whenOldIntentExecuted]: executeQueuedAction.t.sol#L432
[test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate]: queueSetPriceCacheMaxAge.t.sol#L302
[test_givenDirtySettingWords_whenQueueRejected]: queueSetPriceCacheMaxAge.t.sol#L596
[test_givenDirtyStatusWords_whenQueueRejected]: queueSetPriceCacheMaxAge.t.sol#L576
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: queueSetPriceCacheMaxAge.t.sol#L366
[test_givenEveryIndependentUpstreamState_whenQueued]: queueSetPriceCacheMaxAge.t.sol#L561
[test_givenFailedRiskStatus_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L433
[test_givenFailedSettingMetadata_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L450
[test_givenForeignRiskKernel_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L260
[test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget]: queueSetPriceCacheMaxAge.t.sol#L48
[test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L411
[test_givenIndependentUpstreamStates_whenQueued]: queueSetPriceCacheMaxAge.t.sol#L529
[test_givenInvalidSettingMetadata_whenQueueRejected]: queueSetPriceCacheMaxAge.t.sol#L499
[test_givenInvalidStatusMetadata_whenQueueRejected]: queueSetPriceCacheMaxAge.t.sol#L469
[test_givenMarketKeyPending_whenAgeQueued_thenIndependent]: queueSetPriceCacheMaxAge.t.sol#L338
[test_givenMetadataShapeSeeds_whenQueueRejected]: queueSetPriceCacheMaxAge.t.sol#L618
[test_givenNonzeroOldAge_whenZeroQueued_thenAccepted]: queueSetPriceCacheMaxAge.t.sol#L76
[test_givenOperationalRisk_whenAgeQueued_thenStored]: queueSetPriceCacheMaxAge.t.sol#L35
[test_givenPermittedProposer_whenAgeQueued_thenStored]: queueSetPriceCacheMaxAge.t.sol#L22
[test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L241
[test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L203
[test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L222
[test_givenRiskKeyPending_whenAgeQueuedAgain_reverts]: queueSetPriceCacheMaxAge.t.sol#L318
[test_givenRiskOperatorCleared_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L133
[test_givenRiskOperatorDifferent_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L115
[test_givenSameAge_whenQueued_thenStillCommitted]: queueSetPriceCacheMaxAge.t.sol#L61
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L165
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L184
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L151
[test_givenUnauthorizedProposer_whenAgeQueued_reverts]: queueSetPriceCacheMaxAge.t.sol#L105
[test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: queueSetPriceCacheMaxAge.t.sol#L394
