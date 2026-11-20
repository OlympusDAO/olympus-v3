# PriceCacherTask.enable coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `PCACHER-ENABLE`. Existing scenario IDs remain stable.

Cache compatibility is defined by the consumed interfaces and Kernel binding.
The task must neither require IVersioned support nor call the cache VERSION getter.

## Domains and assertions

ADMIN may enable. ADMIN or EMERGENCY may disable. reEnable permits ADMIN.
Unauthorized fuzzing excludes every permitted role and retains zero. Role-family fuzzing
and fixed drivers establish exclusive and overlapping grants. Kernel membership and local
enablement are independent. Unvaried dependencies are usable unless a row says otherwise.

EnablerV2 checks local transition state before authorization. enable then checks empty
payload, own membership and applicable dependency admission. disable checks empty payload
without membership/readiness gates. reEnable checks initialized history before authorization,
then grace before own membership and the identical activation predicate. Payload fuzzing is
length 1..256 (a practical fixture bound), with 0x00,0x01,ABI-zero and 256-byte seeds.

Let L=lastTransitionAt, G=gracePeriod and D=L+G, in seconds. G is uint32; timestamps are
uint48. The deadline is inclusive. A widened unrepresentable deadline gives
SafeCastOverflowedUintDowncast(48,L+G). Timestamp zero is the shared never-enabled sentinel.
enable remains the governance recovery route after grace expires.

Success updates only the packed lifecycle slot, with isEnabled and lastTransitionAt=now,
then emits the exact legacy Enabled/Disabled event followed by Transition(caller,flag,0x,now)
from the policy. All indexed fields, payload, emitter and event order are asserted.
Unchanged includes lifecycle on rejection, membership, bindings and the authoritative
configuration/data described below. No lifecycle transition moves tokens; reverted
transactions commit no logs. Tests assert exact error data and rollback.

ROLES is a Kernel module. PriceCache is the direct operational Policy dependency: activation
requires IPriceCache and IEnabler, a canonical matching Kernel and canonical
status, plus authoritative membership and enablement. Constructors do not require readiness.
Compatibility precedes readiness. The fixture preserves ordered pairs, pointer and cache-call
counters. Kernel errors retain the established product-specific selectors.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-A01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables], [test][test_whenAdminAndOverlapSeedsEnable] |
| PCACHER-ENABLE-A02 | Fuzz callers excluding every ADMIN; retain zero and secondary roles | true | false | empty payload | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerEnables_reverts], [test][test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-L01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables] |
| PCACHER-ENABLE-L02 | ADMIN_ROLE holder | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAdminEnables_reverts] |
| PCACHER-ENABLE-L03 | ADMIN_ROLE holder | false | false |  | PriceCacherTask_PolicyInactive(subject) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminEnables_reverts] |
| PCACHER-ENABLE-L04 | ADMIN_ROLE holder | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAdminEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-I01 | Fuzz ADMIN_ROLE holder | true | false | Payload length 1..256, independently fuzz caller | PriceCacherTask_InvalidData() | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts], [test][test_givenDisabled_whenPayloadBoundarySeeds_reverts] |
| PCACHER-ENABLE-I02 | Fuzz unauthorized callers | true | false | nonempty payload | ROLES_RequireRole(ADMIN_ROLE), before payload | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHER-ENABLE-I03 | ADMIN_ROLE holder | true | true | nonempty payload | NotDisabled(), before payload | Unchanged | Covered: [test][test_givenEnabled_whenAdminUsesNonemptyPayload_reverts] |
| PCACHER-ENABLE-I04 | Fuzz unauthorized callers | true | true | nonempty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHER-ENABLE-I05 | Fuzz unauthorized callers | true | true | empty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts] |
| PCACHER-ENABLE-I06 | ADMIN_ROLE holder | false | false | nonempty payload | PriceCacherTask_InvalidData(), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenNonemptyPayload_reverts] |
| PCACHER-ENABLE-I07 | Fuzz unauthorized callers | false | false | empty payload | ROLES_RequireRole(ADMIN_ROLE), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts] |
| PCACHER-ENABLE-I08 | ADMIN_ROLE holder | false | false | Own inactivity and broken dependency compete | Own-policy inactivity before dependency probes | Unchanged | Covered: [test][test_givenInactiveAndBrokenDependency_whenActivation_reverts] |
| PCACHER-ENABLE-I09 | ADMIN_ROLE holder | true | false | Nonempty payload plus broken dependency | PriceCacherTask_InvalidData(), before dependency probes | Unchanged | Covered: [test][test_givenBrokenDependency_whenNonemptyPayload_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated then reactivated | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenAdminEnables] |
| PCACHER-ENABLE-P02 | ADMIN_ROLE holder | true | false | Fresh configured active policy; no transition history | Success | Exact transition; preserve other state | Covered: [test][test_givenNeverEnabled_whenAdminEnables] |
| PCACHER-ENABLE-P03 | ADMIN_ROLE holder | true | false | Paused after grace expires; enable remains the governance recovery route | Success | Exact transition; preserve other state | Covered: [test][test_givenExpiredGrace_whenAdminEnables] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Dependency active | Dependency enabled | Compatibility or recovery condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-D01 | ADMIN_ROLE holder | true | true | Cache no longer advertises IPriceCache | PriceCacherTask_InvalidPriceCache(cache) | Unchanged | Covered: [test][test_givenMissingPriceCacheInterface_whenActivation_reverts] |
| PCACHER-ENABLE-D02 | ADMIN_ROLE holder | true | true | Cache no longer advertises IEnabler | PriceCacherTask_InvalidPriceCache(cache) | Unchanged | Covered: [test][test_givenMissingEnablerInterface_whenActivation_reverts] |
| PCACHER-ENABLE-D03 | ADMIN_ROLE holder | true | true | Compatible cache does not advertise IVersioned | Success without a VERSION query | Exact transition; other state preserved | Covered: [test][test_givenNoVersionInterface_whenActivated_thenAccepted] |
| PCACHER-ENABLE-D05 | ADMIN_ROLE holder | true | false | Foreign reported Kernel plus cache paused; compatibility before readiness | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenForeignKernelAndPausedCache_whenActivation_reverts] |
| PCACHER-ENABLE-D06 | ADMIN_ROLE holder | true | true | Compatible cache VERSION getter reverts | Success without a VERSION query | Exact transition; other state preserved | Covered: [test][test_givenVersionGetterReverts_whenActivated_thenIgnored] |
| PCACHER-ENABLE-D08 | ADMIN_ROLE holder | true | true | Kernel getter reverts | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenKernelReadReverts_whenActivation_reverts] |
| PCACHER-ENABLE-D10 | ADMIN_ROLE holder | true | true | Status getter reverts | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenStatusReadReverts_whenActivation_reverts] |
| PCACHER-ENABLE-D09 | ADMIN_ROLE holder | true | true | Noncanonical Kernel ABI words | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenNoncanonicalKernel_whenActivation_reverts], [test][test_givenMalformedKernelLength_whenActivation_reverts] |
| PCACHER-ENABLE-D11 | ADMIN_ROLE holder | true | true | Noncanonical Status ABI words | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenNoncanonicalStatus_whenActivation_reverts], [test][test_givenMalformedStatusLength_whenActivation_reverts] |
| PCACHER-ENABLE-L05 | ADMIN_ROLE holder | true | true | Cache active=true; enabled=true | Success | Exact transition; other state preserved | Covered: [test][test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds] |
| PCACHER-ENABLE-L06 | ADMIN_ROLE holder | true | false | Cache active=true; enabled=false | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveTrueEnabledFalse_whenActivation_reverts] |
| PCACHER-ENABLE-L07 | ADMIN_ROLE holder | false | true | Cache active=false; enabled=true | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveFalseEnabledTrue_whenActivation_reverts] |
| PCACHER-ENABLE-L08 | ADMIN_ROLE holder | false | false | Cache active=false; enabled=false | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveFalseEnabledFalse_whenActivation_reverts] |
| PCACHER-ENABLE-D13 | ADMIN_ROLE holder | true | false | Paused cache restored before activation; no stale failure cached | Success | Exact transition; other state preserved | Covered: [test][test_givenCacheReadinessRestored_whenActivationSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

## Compatibility before readiness

| ID | Caller | Local active | Local enabled | Dependency active | Dependency enabled getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ENABLE-D18 | ADMIN | true | false | false | Noncanonical bool=2 | PolicyDependency_InvalidDependency(dependency) | Unchanged | Covered: [test][test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts] |

[test_givenBrokenDependency_whenNonemptyPayload_reverts]: enable.t.sol#L441
[test_givenCacheActiveFalseEnabledFalse_whenActivation_reverts]: enable.t.sol#L396
[test_givenCacheActiveFalseEnabledTrue_whenActivation_reverts]: enable.t.sol#L381
[test_givenCacheActiveTrueEnabledFalse_whenActivation_reverts]: enable.t.sol#L367
[test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds]: enable.t.sol#L359
[test_givenCacheReadinessRestored_whenActivationSucceeds]: enable.t.sol#L412
[test_givenDisabled_whenAdminEnables]: enable.t.sol#L21
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L96
[test_givenDisabled_whenPayloadBoundarySeeds_reverts]: enable.t.sol#L108
[test_givenDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L38
[test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts]: enable.t.sol#L50
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L124
[test_givenEnabled_whenAdminEnables_reverts]: enable.t.sol#L72
[test_givenEnabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L137
[test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts]: enable.t.sol#L161
[test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L148
[test_givenExpiredGrace_whenAdminEnables]: enable.t.sol#L212
[test_givenForeignKernelAndPausedCache_whenActivation_reverts]: enable.t.sol#L250
[test_givenInactiveAndBrokenDependency_whenActivation_reverts]: enable.t.sol#L422
[test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts]: enable.t.sol#L458
[test_givenInactiveDisabled_whenAdminEnables_reverts]: enable.t.sol#L77
[test_givenInactiveDisabled_whenNonemptyPayload_reverts]: enable.t.sol#L173
[test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L184
[test_givenInactiveEnabled_whenAdminEnables_reverts]: enable.t.sol#L91
[test_givenKernelReadReverts_whenActivation_reverts]: enable.t.sol#L271
[test_givenMalformedKernelLength_whenActivation_reverts]: enable.t.sol#L316
[test_givenMalformedStatusLength_whenActivation_reverts]: enable.t.sol#L345
[test_givenMissingEnablerInterface_whenActivation_reverts]: enable.t.sol#L236
[test_givenMissingPriceCacheInterface_whenActivation_reverts]: enable.t.sol#L222
[test_givenNeverEnabled_whenAdminEnables]: enable.t.sol#L206
[test_givenNoVersionInterface_whenActivated_thenAccepted]: enable.t.sol#L482
[test_givenNoncanonicalKernel_whenActivation_reverts]: enable.t.sol#L301
[test_givenNoncanonicalStatus_whenActivation_reverts]: enable.t.sol#L330
[test_givenReactivated_whenAdminEnables]: enable.t.sol#L196
[test_givenStatusReadReverts_whenActivation_reverts]: enable.t.sol#L286
[test_givenVersionGetterReverts_whenActivated_thenIgnored]: enable.t.sol#L492
[test_whenAdminAndOverlapSeedsEnable]: enable.t.sol#L28
