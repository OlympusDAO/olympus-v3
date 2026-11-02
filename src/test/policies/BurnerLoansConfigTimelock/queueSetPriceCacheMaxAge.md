# BurnerLoansConfigTimelock.queueSetPriceCacheMaxAge coverage plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [current queue wrapper](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L235). Required routing changes the target to [Risk.setPriceCacheMaxAge](../../../policies/burnerloans/BurnerLoansRisk.sol#L572); Config no longer forwards this setter.

## Domains and notation

Scenario scope: `BLCT-QUEUE-CACHE-AGE`. BLCT denotes this ConfigTimelock. Core is obtained from immutable Config's facility binding; the selected Risk address is captured at queue time. Config's read-only binding remains usable while inactive/disabled. Config, Core and Risk operator addresses are independent.

Permitted proposers are ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only, or both; fuzz independently and guarantee each class. Risk selects BLCT itself as configOperator; BLCT holds no ADMIN role. Unauthorized fuzzing excludes every holder of either proposer role. age:uint48 accepts 0..MAX48. No target setter executes during queueing.

Defaults: BLCT and selected Risk active/enabled in the same Kernel; Risk.configOperator()==BLCT; action key free; initialized module bindings. Own local enablement and proposer authorization precede target validation. Unchanged means nextActionId, all existing actions/payloads/keys/hashes, Risk age/operator/oracle/cache, Core/FLOAN and token/accounting state unchanged; a reverted transaction commits no logs.

## Authorization

| ID | Caller | Risk operator | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-A01 | Fuzz caller excluding every ADMIN and BL-admin role holder | BLCT | NotAuthorised() | Unchanged | Covered: [test_givenUnauthorizedProposer_whenAgeQueued_reverts][test_givenUnauthorizedProposer_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A03 | Fuzz permitted proposer | Distinct nonzero address | NotAuthorised() | No ADMIN fallback granted to BLCT; no action/key acquired | Covered: [test_givenRiskOperatorDifferent_whenAgeQueued_reverts][test_givenRiskOperatorDifferent_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A04 | Fuzz permitted proposer | Zero | NotAuthorised() | Unchanged | Covered: [test_givenRiskOperatorCleared_whenAgeQueued_reverts][test_givenRiskOperatorCleared_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-A05 | Fuzz permitted proposer | BLCT | Return next action ID | Exact queue record below | Covered: [test_givenPermittedProposer_whenAgeQueued_thenStored][test_givenPermittedProposer_whenAgeQueued_thenStored]; [test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds] |

Former A02 duplicated unauthorized admission with Config disabled; target independence below covers that state without a second authorization case.

## Local lifecycle

Permitted proposer; Risk ready and independently selects BLCT. Config lifecycle is not an admission gate for this Risk-targeted action.

| ID | Caller | Local active | Local enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-L01 | Fuzz permitted proposer | true | false | NotEnabled() | Unchanged | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-L05 | Fuzz permitted proposer | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-L09 | Fuzz permitted proposer | false | true | BurnerLoans_PolicyNotActive(BLCT) | Unchanged | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts] |

The remaining old L02-L04/L06-L08/L10-L15 multiplied Config lifecycle into this direct Risk operation and are retired.

## Target dependencies

Local active/enabled; permitted proposer; Risk operator=BLCT. Core selection getters are readable; Core activity/enablement does not gate this numeric setter. No authority getter on Config is used.

| ID | Caller | Risk active | Risk enabled | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-D03 | Fuzz permitted proposer | true | true | Return next ID | No target mutation | Covered: [test_givenOperationalRisk_whenAgeQueued_thenStored][test_givenOperationalRisk_whenAgeQueued_thenStored] |
| BLCT-QUEUE-CACHE-AGE-D04 | Fuzz permitted proposer | false | true | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts][test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D05 | Fuzz permitted proposer | true | false | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts][test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D06 | Fuzz permitted proposer | false | false | PolicyDependency_NotActive(Risk) | Unchanged | Covered: [test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts][test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts] |

| ID | Caller | Binding / independent authority | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-D07 | Fuzz permitted proposer | Selected Risk reports another Kernel | PolicyDependency_KernelMismatch(Risk,expectedKernel,reportedKernel) | Unchanged | Covered: [test_givenForeignRiskKernel_whenAgeQueued_reverts][test_givenForeignRiskKernel_whenAgeQueued_reverts] |
| BLCT-QUEUE-CACHE-AGE-D08 | Fuzz permitted proposer | Config active/enabled independently false/true; Config.configOperator differs from BLCT | Return ID | No Config activity/enablement/operator admission or setter call; target is selected Risk | Covered: [test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate][test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate] |
| BLCT-QUEUE-CACHE-AGE-D09 | Fuzz permitted proposer | Core active/enabled independently false/true; readable Risk selection unchanged | Return ID | No Core lifecycle admission or mutation | Covered: [test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate][test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate] |

## Numeric inputs and queue record

| ID | Caller | Age / current value | Queue result | Effects / getter assertions | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-I01 | Fuzz permitted proposer | 0; old age nonzero | Return ID | Zero is valid, not an invalid input | Covered: [test_givenNonzeroOldAge_whenZeroQueued_thenAccepted][test_givenNonzeroOldAge_whenZeroQueued_thenAccepted] |
| BLCT-QUEUE-CACHE-AGE-N01 | Fuzz permitted proposer | Fuzz 1..MAX48; seed 1,MAX48; old age independently different | Return ID | Canonical 32-byte uint48 ABI payload | Covered: [test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload][test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload]; [test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-QUEUE-CACHE-AGE-P01 | Fuzz permitted proposer | Changed age; key free | Return next ID | Store target=concrete selected Risk, selector=Risk.setPriceCacheMaxAge, payload=abi.encode(age); getQueuedSubAction/getQueuedConfigDestination agree; Risk-scoped selector key; hash=keccak256(abi.encode(Core,Risk,oldAge)); exact proposer, ordered payload, queuedAt, +1-day execution and +3-day expiry; queue events from BLCT; no Risk setter event/write | Covered: [test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget][test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget] |
| BLCT-QUEUE-CACHE-AGE-P07 | Fuzz permitted proposer | Request equals stored age, including 0/MAX48 | Return ID | Queue still records the same target/pre-state; target no-op is checked in executeQueuedAction | Covered: [test_givenSameAge_whenQueued_thenStillCommitted][test_givenSameAge_whenQueued_thenStillCommitted]; [test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Queue conflicts

| ID | Caller | Pending keys | Queue result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-P02 | Fuzz permitted proposer | Same Risk/selector key owned by pending action | IConfigTimelockBatchQueue_ConfigKeyPending(key,owner) | No ID consumed; original payload/key/hash retained | Covered: [test_givenRiskKeyPending_whenAgeQueuedAgain_reverts][test_givenRiskKeyPending_whenAgeQueuedAgain_reverts] |
| BLCT-QUEUE-CACHE-AGE-P03 | Fuzz permitted proposer | Unrelated Config market-setting key pending | Return new ID | Independent target-scoped key; earlier action untouched; neither target mutated | Covered: [test_givenMarketKeyPending_whenAgeQueued_thenIndependent][test_givenMarketKeyPending_whenAgeQueued_thenIndependent] |

## Execution coverage placement

Cache-age drift, Risk replacement, operator/lifecycle drift and successful direct dispatch belong to [executeQueuedAction](executeQueuedAction.md), including the retained IDs P04/P05/P06/D01/D02 from this scope. Queue tests assert admission and committed data only. [queueBatch](queueBatch.md) covers raw malformed ABI and selector/target allowlisting.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-QUEUE-CACHE-AGE-L10 | Fuzz all callers | false | false | Config.facility() rejects; period=0 | BurnerLoans_PolicyNotActive(TL) | No metadata read or consumed ID | Covered: [test][test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts] |

[test_givenUnauthorizedProposer_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L107
[test_givenRiskOperatorDifferent_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L118
[test_givenRiskOperatorCleared_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L132
[test_givenPermittedProposer_whenAgeQueued_thenStored]: ./queueSetPriceCacheMaxAge.t.sol#L18
[test_givenEachProposerRole_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetPriceCacheMaxAge.t.sol#L353
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L146
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L161
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L181
[test_givenOperationalRisk_whenAgeQueued_thenStored]: ./queueSetPriceCacheMaxAge.t.sol#L32
[test_givenRiskActiveFalse_givenRiskEnabledTrue_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L201
[test_givenRiskActiveTrue_givenRiskEnabledFalse_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L221
[test_givenRiskActiveFalse_givenRiskEnabledFalse_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L241
[test_givenForeignRiskKernel_whenAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L261
[test_givenConfigUnavailable_whenAgeQueued_thenNoLifecycleGate]: ./queueSetPriceCacheMaxAge.t.sol#L287
[test_givenCoreUnavailable_whenAgeQueued_thenNoLifecycleGate]: ./queueSetPriceCacheMaxAge.t.sol#L305
[test_givenNonzeroOldAge_whenZeroQueued_thenAccepted]: ./queueSetPriceCacheMaxAge.t.sol#L76
[test_givenChangedAge_whenFullWidthAgeQueued_thenCanonicalPayload]: ./queueSetPriceCacheMaxAge.t.sol#L91
[test_givenCacheAgeN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetPriceCacheMaxAge.t.sol#L364
[test_givenFreeRiskKey_whenAgeQueued_thenExactDirectTarget]: ./queueSetPriceCacheMaxAge.t.sol#L46
[test_givenSameAge_whenQueued_thenStillCommitted]: ./queueSetPriceCacheMaxAge.t.sol#L60
[test_givenUnchangedCacheAgeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./queueSetPriceCacheMaxAge.t.sol#L381
[test_givenRiskKeyPending_whenAgeQueuedAgain_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L322
[test_givenMarketKeyPending_whenAgeQueued_thenIndependent]: ./queueSetPriceCacheMaxAge.t.sol#L343
[test_givenInactiveDisabled_givenBrokenFacility_whenPriceAgeQueued_reverts]: ./queueSetPriceCacheMaxAge.t.sol#L398
