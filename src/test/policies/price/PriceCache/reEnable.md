# PriceCache.reEnable coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol); inherited
[EnablerV2](../../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../../bases/ReEnablerGracePeriod.sol).
Scope: `PCACHE-REENABLE`. Existing scenario IDs remain stable.

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

PRICE and ROLES are Kernel modules. No Policy-ready check is invented for PRICE. The
fixture preserves three cached pairs, non-contract metadata/epochs and all bindings.
PRICE runtime failure does not prevent local lifecycle transitions.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-A01 | Fuzz ADMIN-only, PRICE_ADMIN-only and both roles | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenPaused_whenPriceAdminReEnables], [test][test_givenPaused_whenBothRolesReEnable], [test][test_whenPermittedCallerSeedsReEnable] |
| PCACHE-REENABLE-A02 | Fuzz callers excluding ADMIN and PRICE_ADMIN | true | false | initialized; within grace | NotAuthorised() | Unchanged | Covered: [test][test_givenPaused_whenUnauthorizedCallerReEnables_reverts], [test][test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-L01 | Fuzz ADMIN-only, PRICE_ADMIN-only and both roles | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenPaused_whenPriceAdminReEnables], [test][test_givenPaused_whenBothRolesReEnable] |
| PCACHE-REENABLE-L02 | Fuzz all callers | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenEnabled_whenCallerSeedsReEnable_reverts] |
| PCACHE-REENABLE-L03 | ADMIN_ROLE holder | false | false | initialized; within grace | PriceCache_PolicyInactive() | Unchanged | Covered: [test][test_givenInactivePaused_whenReEnabled_reverts] |
| PCACHE-REENABLE-L04 | Fuzz all callers | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAnyCallerReEnables_reverts] |
| PCACHE-REENABLE-L05 | Fuzz all callers | true | false | Fresh active/configured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts] |
| PCACHE-REENABLE-L06 | Fuzz all callers | false | false | Fresh inactive/unconfigured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-I01 | Fuzz unauthorized callers | false | false | Expired grace and inactive subject | Authorization error before grace or own activity | Unchanged | Covered: [test][test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts] |
| PCACHE-REENABLE-I02 | PRICE_ADMIN-only holder | false | false | Own inactivity and expired grace compete | GracePeriod_Expired(D), before own activity | Unchanged | Covered: [test][test_givenInactive_whenGraceExpired_reverts] |

## Grace boundaries

Subject active and initially enabled for pause setup; caller is otherwise permitted.

| ID | Caller | Grace G | Pause timestamp L | Evaluation timestamp | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-N01 | ADMIN | Fuzz 1..MAX32 | Fuzz 1..MAX48-G | Fuzz L..D | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenIndependentGraceAndTimeWithinWindow] |
| PCACHE-REENABLE-N02 | PRICE_ADMIN-only | Fuzz 1..MAX32 | Fuzz 1..MAX48-G-1 | Fuzz D+1..MAX48; seed MAX48 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenIndependentGraceAndTimeExpired_reverts], [test][test_whenMaximumTimestampIsExpired_reverts] |
| PCACHE-REENABLE-N03 | PRICE_ADMIN-only | Seeds 1,7,MAX32 | 100; MAX48-1 | L,D-1,D; MAX48 | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenImmediately], [test][test_whenOneBeforeDeadline], [test][test_whenAtDeadline], [test][test_whenAtMaximumGraceDeadline], [test][test_whenDeadlineIsMaximumTimestamp] |
| PCACHE-REENABLE-N04 | PRICE_ADMIN-only | 1 | 100 | 102=D+1 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenFirstTimestampAfterDeadline_reverts] |
| PCACHE-REENABLE-N05 | PRICE_ADMIN-only | Fuzz 1..MAX32 | Fuzz MAX48-G+1..MAX48 | L; widened D overflows uint48 | SafeCastOverflowedUintDowncast(48,L+G) | Unchanged | Covered: [test][test_whenDeadlineOverflows_reverts], [test][test_whenMaximumTimestampMakesDeadlineOverflow_reverts] |
| PCACHE-REENABLE-N06 | ADMIN | Initial nonzero | 0 | 0 | NeverEnabled(); zero is the shared history sentinel | Unchanged | Covered: [test][test_givenZeroTransitionTimestamp_whenReEnabled_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-P01 | PRICE_ADMIN-only holder | true | false | Paused policy deactivated and reactivated within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenReEnabled] |
| PCACHE-REENABLE-P02 | PRICE_ADMIN-only holder | true | false | Two pauses, distinct timestamps; each uses its latest deadline | Success | Exact transition; preserve other state | Covered: [test][test_whenRepeatedCyclesRestartGrace] |
| PCACHE-REENABLE-P03 | Fuzz all callers | true | true | IEnabler, IEnablerV2, IReEnabler, IGracePeriod, IPriceCache | All supported; initial grace=7 days | No mutation | Covered: [test][test_whenLifecycleInterfacesQueried] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| PCACHE-REENABLE-D01 | ADMIN_ROLE holder | PRICE runtime calls revert; module binding remains intact | Success | Exact transition; other state preserved | Covered: [test][test_givenPriceReadsRevert_whenTransitionSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenPaused_whenAdminReEnables]: reEnable.t.sol#L21
[test_whenPermittedCallerSeedsReEnable]: reEnable.t.sol#L45
[test_givenPaused_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L57
[test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts]: reEnable.t.sol#L69
[test_givenEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L86
[test_givenEnabled_whenCallerSeedsReEnable_reverts]: reEnable.t.sol#L369
[test_givenInactivePaused_whenReEnabled_reverts]: reEnable.t.sol#L95
[test_givenInactiveEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L108
[test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L119
[test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L131
[test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L143
[test_givenInactive_whenGraceExpired_reverts]: reEnable.t.sol#L282
[test_whenIndependentGraceAndTimeWithinWindow]: reEnable.t.sol#L160
[test_whenIndependentGraceAndTimeExpired_reverts]: reEnable.t.sol#L176
[test_whenMaximumTimestampIsExpired_reverts]: reEnable.t.sol#L336
[test_whenImmediately]: reEnable.t.sol#L197
[test_whenOneBeforeDeadline]: reEnable.t.sol#L204
[test_whenAtDeadline]: reEnable.t.sol#L212
[test_whenAtMaximumGraceDeadline]: reEnable.t.sol#L220
[test_whenDeadlineIsMaximumTimestamp]: reEnable.t.sol#L228
[test_whenFirstTimestampAfterDeadline_reverts]: reEnable.t.sol#L236
[test_whenDeadlineOverflows_reverts]: reEnable.t.sol#L248
[test_whenMaximumTimestampMakesDeadlineOverflow_reverts]: reEnable.t.sol#L267
[test_givenZeroTransitionTimestamp_whenReEnabled_reverts]: reEnable.t.sol#L326
[test_givenReactivated_whenReEnabled]: reEnable.t.sol#L295
[test_whenRepeatedCyclesRestartGrace]: reEnable.t.sol#L305
[test_whenLifecycleInterfacesQueried]: reEnable.t.sol#L348
[test_givenPriceReadsRevert_whenTransitionSucceeds]: reEnable.t.sol#L316

[test_givenPaused_whenPriceAdminReEnables]: reEnable.t.sol#L29
[test_givenPaused_whenBothRolesReEnable]: reEnable.t.sol#L38
