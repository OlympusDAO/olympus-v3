# DepositManager.reEnable coverage plan

Source: [DepositManager](../../../policies/deposits/DepositManager.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DM-REENABLE`. Existing scenario IDs remain stable.

## Domains and assertions

ADMIN may enable. ADMIN or EMERGENCY may disable. reEnable permits ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap.
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

ROLES/TRSRY are Kernel modules. ReceiptTokenManager and the vault are ordinary contracts,
with no invented Kernel activity or Enabler requirements. Lifecycle hooks do not deliver
tokens. A real 2e18 deposit seeds receipts and vault custody; raw configuration/accounting
slots, relevant balances, shares and depositor allowance must remain unchanged.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-REENABLE-A01 | Fuzz ADMIN and all additional permitted role classes | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenSecondaryOnly_whenReEnabled], [test][test_givenAdminAndSecondary_whenReEnabled], [test][test_whenPermittedCallerSeedsReEnable] |
| DM-REENABLE-A02 | Fuzz callers excluding every permitted role | true | false | initialized; within grace | NotAuthorised() | Unchanged | Covered: [test][test_givenPaused_whenUnauthorizedCallerReEnables_reverts], [test][test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-REENABLE-L01 | Fuzz ADMIN and all additional permitted role classes | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenSecondaryOnly_whenReEnabled], [test][test_givenAdminAndSecondary_whenReEnabled], [test][test_whenPermittedCallerSeedsReEnable] |
| DM-REENABLE-L02 | Fuzz all callers | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenEnabled_whenCallerSeedsReEnable_reverts] |
| DM-REENABLE-L03 | ADMIN_ROLE holder | false | false | initialized; within grace | DepositManager_PolicyInactive() | Unchanged | Covered: [test][test_givenInactivePaused_whenReEnabled_reverts] |
| DM-REENABLE-L04 | Fuzz all callers | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAnyCallerReEnables_reverts] |
| DM-REENABLE-L05 | Fuzz all callers | true | false | Fresh active/configured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts] |
| DM-REENABLE-L06 | Fuzz all callers | false | false | Fresh inactive/unconfigured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-REENABLE-I01 | Fuzz unauthorized callers | false | false | Expired grace and inactive subject | Authorization error before grace or own activity | Unchanged | Covered: [test][test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts] |
| DM-REENABLE-I02 | ADMIN_ROLE holder | false | false | Own inactivity and expired grace compete | GracePeriod_Expired(D), before own activity | Unchanged | Covered: [test][test_givenInactive_whenGraceExpired_reverts] |

## Grace boundaries

Subject active and initially enabled for pause setup; caller is otherwise permitted.

| ID | Caller | Grace G | Pause timestamp L | Evaluation timestamp | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-REENABLE-N01 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz 1..MAX48-G | Fuzz L..D | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenIndependentGraceAndTimeWithinWindow] |
| DM-REENABLE-N02 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz 1..MAX48-G-1 | Fuzz D+1..MAX48; seed MAX48 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenIndependentGraceAndTimeExpired_reverts], [test][test_whenMaximumTimestampIsExpired_reverts] |
| DM-REENABLE-N03 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Seeds 1,7,MAX32 | 100; MAX48-1 | L,D-1,D; MAX48 | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenImmediately], [test][test_whenOneBeforeDeadline], [test][test_whenAtDeadline], [test][test_whenAtMaximumGraceDeadline], [test][test_whenDeadlineIsMaximumTimestamp] |
| DM-REENABLE-N04 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | 1 | 100 | 102=D+1 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenFirstTimestampAfterDeadline_reverts] |
| DM-REENABLE-N05 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz MAX48-G+1..MAX48 | L; widened D overflows uint48 | SafeCastOverflowedUintDowncast(48,L+G) | Unchanged | Covered: [test][test_whenDeadlineOverflows_reverts], [test][test_whenMaximumTimestampMakesDeadlineOverflow_reverts] |
| DM-REENABLE-N06 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Initial nonzero | 0 | 0 | NeverEnabled(); zero is the shared history sentinel | Unchanged | Covered: [test][test_givenZeroTransitionTimestamp_whenReEnabled_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-REENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated and reactivated within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenReEnabled] |
| DM-REENABLE-P02 | ADMIN_ROLE holder | true | false | Two pauses, distinct timestamps; each uses its latest deadline | Success | Exact transition; preserve other state | Covered: [test][test_whenRepeatedCyclesRestartGrace] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DM-REENABLE-D01 | ADMIN_ROLE holder | Vault delivery rejects; transitions neither redeem nor move custody | Success | Exact transition; other state preserved | Covered: [test][test_givenVaultDeliveryReverts_whenTransitionSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenPaused_whenAdminReEnables]: reEnable.t.sol#L21
[test_givenSecondaryOnly_whenReEnabled]: reEnable.t.sol#L29
[test_givenAdminAndSecondary_whenReEnabled]: reEnable.t.sol#L36
[test_whenPermittedCallerSeedsReEnable]: reEnable.t.sol#L44
[test_givenPaused_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L54
[test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts]: reEnable.t.sol#L66
[test_givenEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L83
[test_givenEnabled_whenCallerSeedsReEnable_reverts]: reEnable.t.sol#L389
[test_givenInactivePaused_whenReEnabled_reverts]: reEnable.t.sol#L92
[test_givenInactiveEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L105
[test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L116
[test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L128
[test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L140
[test_givenInactive_whenGraceExpired_reverts]: reEnable.t.sol#L315
[test_whenIndependentGraceAndTimeWithinWindow]: reEnable.t.sol#L157
[test_whenIndependentGraceAndTimeExpired_reverts]: reEnable.t.sol#L174
[test_whenMaximumTimestampIsExpired_reverts]: reEnable.t.sol#L373
[test_whenImmediately]: reEnable.t.sol#L196
[test_whenOneBeforeDeadline]: reEnable.t.sol#L207
[test_whenAtDeadline]: reEnable.t.sol#L219
[test_whenAtMaximumGraceDeadline]: reEnable.t.sol#L231
[test_whenDeadlineIsMaximumTimestamp]: reEnable.t.sol#L243
[test_whenFirstTimestampAfterDeadline_reverts]: reEnable.t.sol#L255
[test_whenDeadlineOverflows_reverts]: reEnable.t.sol#L271
[test_whenMaximumTimestampMakesDeadlineOverflow_reverts]: reEnable.t.sol#L296
[test_givenZeroTransitionTimestamp_whenReEnabled_reverts]: reEnable.t.sol#L359
[test_givenReactivated_whenReEnabled]: reEnable.t.sol#L328
[test_whenRepeatedCyclesRestartGrace]: reEnable.t.sol#L338
[test_givenVaultDeliveryReverts_whenTransitionSucceeds]: reEnable.t.sol#L349
