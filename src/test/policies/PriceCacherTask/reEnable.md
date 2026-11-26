# PriceCacherTask.reEnable coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `PCACHER-REENABLE`. Existing scenario IDs remain stable.

Cache compatibility is defined by the consumed interfaces and Kernel binding.
The task must neither require IVersioned support nor call the cache VERSION getter.

## Domains and assertions

ADMIN may enable. ADMIN or EMERGENCY may disable. reEnable permits ADMIN or PRICE_ADMIN (the `price_admin` role).
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
| PCACHER-REENABLE-A01 | Fuzz ADMIN-only, PRICE_ADMIN-only and both roles | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenPaused_whenPriceAdminReEnables], [test][test_givenPaused_whenBothRolesReEnable], [test][test_whenPermittedCallerSeedsReEnable] |
| PCACHER-REENABLE-A02 | Fuzz callers excluding ADMIN and PRICE_ADMIN | true | false | initialized; within grace | NotAuthorised() | Unchanged | Covered: [test][test_givenPaused_whenUnauthorizedCallerReEnables_reverts], [test][test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-L01 | Fuzz ADMIN-only, PRICE_ADMIN-only and both roles | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenPaused_whenPriceAdminReEnables], [test][test_givenPaused_whenBothRolesReEnable] |
| PCACHER-REENABLE-L02 | Fuzz all callers | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenEnabled_whenCallerSeedsReEnable_reverts] |
| PCACHER-REENABLE-L03 | ADMIN_ROLE holder | false | false | initialized; within grace | PriceCacherTask_PolicyInactive(subject) | Unchanged | Covered: [test][test_givenInactivePaused_whenReEnabled_reverts] |
| PCACHER-REENABLE-L04 | Fuzz all callers | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAnyCallerReEnables_reverts] |
| PCACHER-REENABLE-L05 | Fuzz all callers | true | false | Fresh active/configured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts] |
| PCACHER-REENABLE-L06 | Fuzz all callers | false | false | Fresh inactive/unconfigured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-I01 | Fuzz unauthorized callers | false | false | Expired grace and inactive subject | Authorization error before grace or own activity | Unchanged | Covered: [test][test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts] |
| PCACHER-REENABLE-I02 | PRICE_ADMIN-only holder | false | false | Own inactivity and expired grace compete | GracePeriod_Expired(D), before own activity | Unchanged | Covered: [test][test_givenInactive_whenGraceExpired_reverts] |
| PCACHER-REENABLE-I08 | ADMIN_ROLE holder | false | false | Own inactivity and broken dependency compete | Own-policy inactivity before dependency probes | Unchanged | Covered: [test][test_givenInactiveAndBrokenDependency_whenActivation_reverts] |
| PCACHER-REENABLE-I03 | ADMIN_ROLE holder | true | false | Expired grace and broken dependency compete | GracePeriod_Expired(D), before dependency probes | Unchanged | Covered: [test][test_givenBrokenDependency_whenExpiredGrace_reverts] |

## Grace boundaries

Subject active and initially enabled for pause setup; caller is otherwise permitted.

| ID | Caller | Grace G | Pause timestamp L | Evaluation timestamp | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-N01 | ADMIN | Fuzz 1..MAX32 | Fuzz 1..MAX48-G | Fuzz L..D | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenIndependentGraceAndTimeWithinWindow] |
| PCACHER-REENABLE-N02 | PRICE_ADMIN-only | Fuzz 1..MAX32 | Fuzz 1..MAX48-G-1 | Fuzz D+1..MAX48; seed MAX48 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenIndependentGraceAndTimeExpired_reverts], [test][test_whenMaximumTimestampIsExpired_reverts] |
| PCACHER-REENABLE-N03 | PRICE_ADMIN-only | Seeds 1,7,MAX32 | 100; MAX48-1 | L,D-1,D; MAX48 | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenImmediately], [test][test_whenOneBeforeDeadline], [test][test_whenAtDeadline], [test][test_whenAtMaximumGraceDeadline], [test][test_whenDeadlineIsMaximumTimestamp] |
| PCACHER-REENABLE-N04 | PRICE_ADMIN-only | 1 | 100 | 102=D+1 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenFirstTimestampAfterDeadline_reverts] |
| PCACHER-REENABLE-N05 | PRICE_ADMIN-only | Fuzz 1..MAX32 | Fuzz MAX48-G+1..MAX48 | L; widened D overflows uint48 | SafeCastOverflowedUintDowncast(48,L+G) | Unchanged | Covered: [test][test_whenDeadlineOverflows_reverts], [test][test_whenMaximumTimestampMakesDeadlineOverflow_reverts] |
| PCACHER-REENABLE-N06 | ADMIN | Initial nonzero | 0 | 0 | NeverEnabled(); zero is the shared history sentinel | Unchanged | Covered: [test][test_givenZeroTransitionTimestamp_whenReEnabled_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-P01 | PRICE_ADMIN-only holder | true | false | Paused policy deactivated and reactivated within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenReEnabled] |
| PCACHER-REENABLE-P02 | PRICE_ADMIN-only holder | true | false | Two pauses, distinct timestamps; each uses its latest deadline | Success | Exact transition; preserve other state | Covered: [test][test_whenRepeatedCyclesRestartGrace] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Dependency active | Dependency enabled | Compatibility or recovery condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-D01 | ADMIN_ROLE holder | true | true | Cache no longer advertises IPriceCache | PriceCacherTask_InvalidPriceCache(cache) | Unchanged | Covered: [test][test_givenMissingPriceCacheInterface_whenActivation_reverts] |
| PCACHER-REENABLE-D02 | ADMIN_ROLE holder | true | true | Cache no longer advertises IEnabler | PriceCacherTask_InvalidPriceCache(cache) | Unchanged | Covered: [test][test_givenMissingEnablerInterface_whenActivation_reverts] |
| PCACHER-REENABLE-D03 | ADMIN_ROLE holder | true | true | Compatible cache does not advertise IVersioned | Success without a VERSION query | Exact transition; other state preserved | Covered: [test][test_givenNoVersionInterface_whenActivated_thenAccepted] |
| PCACHER-REENABLE-D05 | ADMIN_ROLE holder | true | false | Foreign reported Kernel plus cache paused; compatibility before readiness | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenForeignKernelAndPausedCache_whenActivation_reverts] |
| PCACHER-REENABLE-D06 | ADMIN_ROLE holder | true | true | Compatible cache VERSION getter reverts | Success without a VERSION query | Exact transition; other state preserved | Covered: [test][test_givenVersionGetterReverts_whenActivated_thenIgnored] |
| PCACHER-REENABLE-D08 | ADMIN_ROLE holder | true | true | Kernel getter reverts | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenKernelReadReverts_whenActivation_reverts] |
| PCACHER-REENABLE-D10 | ADMIN_ROLE holder | true | true | Status getter reverts | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenStatusReadReverts_whenActivation_reverts] |
| PCACHER-REENABLE-D09 | ADMIN_ROLE holder | true | true | Noncanonical Kernel ABI words | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenNoncanonicalKernel_whenActivation_reverts], [test][test_givenMalformedKernelLength_whenActivation_reverts] |
| PCACHER-REENABLE-D11 | ADMIN_ROLE holder | true | true | Noncanonical Status ABI words | PolicyDependency_InvalidDependency(cache) | Unchanged | Covered: [test][test_givenNoncanonicalStatus_whenActivation_reverts], [test][test_givenMalformedStatusLength_whenActivation_reverts] |
| PCACHER-REENABLE-D14 | ADMIN_ROLE holder | true | true | Cache active=true; enabled=true | Success | Exact transition; other state preserved | Covered: [test][test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds] |
| PCACHER-REENABLE-D15 | ADMIN_ROLE holder | true | false | Cache active=true; enabled=false | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveTrueEnabledFalse_whenActivation_reverts] |
| PCACHER-REENABLE-D16 | ADMIN_ROLE holder | false | true | Cache active=false; enabled=true | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveFalseEnabledTrue_whenActivation_reverts] |
| PCACHER-REENABLE-D17 | ADMIN_ROLE holder | false | false | Cache active=false; enabled=false | PolicyDependency_NotActive(cache) | Unchanged | Covered: [test][test_givenCacheActiveFalseEnabledFalse_whenActivation_reverts] |
| PCACHER-REENABLE-D13 | ADMIN_ROLE holder | true | false | Paused cache restored before activation; no stale failure cached | Success | Exact transition; other state preserved | Covered: [test][test_givenCacheReadinessRestored_whenActivationSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

## Compatibility before readiness

| ID | Caller | Local active | Local enabled | Dependency active | Dependency enabled getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REENABLE-D18 | ADMIN | true | false | false | Noncanonical bool=2 | PolicyDependency_InvalidDependency(dependency) | Unchanged | Covered: [test][test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts] |

[test_givenBrokenDependency_whenExpiredGrace_reverts]: reEnable.t.sol#L534
[test_givenCacheActiveFalseEnabledFalse_whenActivation_reverts]: reEnable.t.sol#L489
[test_givenCacheActiveFalseEnabledTrue_whenActivation_reverts]: reEnable.t.sol#L474
[test_givenCacheActiveTrueEnabledFalse_whenActivation_reverts]: reEnable.t.sol#L460
[test_givenCacheActiveTrueEnabledTrue_whenActivationSucceeds]: reEnable.t.sol#L452
[test_givenCacheReadinessRestored_whenActivationSucceeds]: reEnable.t.sol#L505
[test_givenEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L88
[test_givenEnabled_whenCallerSeedsReEnable_reverts]: reEnable.t.sol#L567
[test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L146
[test_givenForeignKernelAndPausedCache_whenActivation_reverts]: reEnable.t.sol#L343
[test_givenInactiveAndBrokenDependency_whenActivation_reverts]: reEnable.t.sol#L515
[test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts]: reEnable.t.sol#L582
[test_givenInactiveEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L111
[test_givenInactivePaused_whenReEnabled_reverts]: reEnable.t.sol#L97
[test_givenInactive_whenGraceExpired_reverts]: reEnable.t.sol#L281
[test_givenKernelReadReverts_whenActivation_reverts]: reEnable.t.sol#L364
[test_givenMalformedKernelLength_whenActivation_reverts]: reEnable.t.sol#L409
[test_givenMalformedStatusLength_whenActivation_reverts]: reEnable.t.sol#L438
[test_givenMissingEnablerInterface_whenActivation_reverts]: reEnable.t.sol#L329
[test_givenMissingPriceCacheInterface_whenActivation_reverts]: reEnable.t.sol#L315
[test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L122
[test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L134
[test_givenNoVersionInterface_whenActivated_thenAccepted]: reEnable.t.sol#L606
[test_givenNoncanonicalKernel_whenActivation_reverts]: reEnable.t.sol#L394
[test_givenNoncanonicalStatus_whenActivation_reverts]: reEnable.t.sol#L423
[test_givenPaused_whenAdminReEnables]: reEnable.t.sol#L23
[test_givenPaused_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L59
[test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts]: reEnable.t.sol#L71
[test_givenReactivated_whenReEnabled]: reEnable.t.sol#L294
[test_givenStatusReadReverts_whenActivation_reverts]: reEnable.t.sol#L379
[test_givenVersionGetterReverts_whenActivated_thenIgnored]: reEnable.t.sol#L616
[test_givenZeroTransitionTimestamp_whenReEnabled_reverts]: reEnable.t.sol#L549
[test_whenAtDeadline]: reEnable.t.sol#L211
[test_whenAtMaximumGraceDeadline]: reEnable.t.sol#L219
[test_whenDeadlineIsMaximumTimestamp]: reEnable.t.sol#L227
[test_whenDeadlineOverflows_reverts]: reEnable.t.sol#L247
[test_whenFirstTimestampAfterDeadline_reverts]: reEnable.t.sol#L235
[test_whenImmediately]: reEnable.t.sol#L196
[test_whenIndependentGraceAndTimeExpired_reverts]: reEnable.t.sol#L177
[test_whenIndependentGraceAndTimeWithinWindow]: reEnable.t.sol#L163
[test_whenMaximumTimestampIsExpired_reverts]: reEnable.t.sol#L555
[test_whenMaximumTimestampMakesDeadlineOverflow_reverts]: reEnable.t.sol#L266
[test_whenOneBeforeDeadline]: reEnable.t.sol#L203
[test_whenPermittedCallerSeedsReEnable]: reEnable.t.sol#L47
[test_whenRepeatedCyclesRestartGrace]: reEnable.t.sol#L304

[test_givenPaused_whenPriceAdminReEnables]: reEnable.t.sol#L31
[test_givenPaused_whenBothRolesReEnable]: reEnable.t.sol#L40
