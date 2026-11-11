# DepositManagerConfigTimelock.reEnable coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DMCT-REENABLE`. Existing scenario IDs remain stable.

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

ROLES is a Kernel module; DepositManager is the direct operational Policy dependency.
Activation requires own membership, the consumed target interfaces, a canonical matching target Kernel, target membership and selection of this timelock as configOperator. Target local enablement is irrelevant: activation never reads isEnabled. Failed or malformed Kernel reads give PolicyDependency_InvalidDependency(DM); a readable foreign Kernel gives PolicyDependency_KernelMismatch(DM,expectedKernel,reportedKernel). Compatible inactive targets give PolicyDependency_NotActive(DM); missing interfaces or malformed operator metadata give DepositManagerConfigTimelock_InvalidDepositManager(DM).
Fixtures preserve a queued cap action including its destination/pre-state/key slots, plus
real deposit receipt, custody and accounting state.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-A01 | Fuzz ADMIN and all additional permitted role classes | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables], [test][test_givenSecondaryOnly_whenReEnabled], [test][test_givenAdminAndSecondary_whenReEnabled], [test][test_whenPermittedCallerSeedsReEnable] |
| DMCT-REENABLE-A02 | Fuzz callers excluding every permitted role | true | false | initialized; within grace | NotAuthorised() | Unchanged | Covered: [test][test_givenPaused_whenUnauthorizedCallerReEnables_reverts], [test][test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-L01 | Fuzz ADMIN and all additional permitted role classes | true | false | initialized; within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenPaused_whenAdminReEnables] |
| DMCT-REENABLE-L02 | Fuzz all callers | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAnyCallerReEnables_reverts], [test][test_givenEnabled_whenCallerSeedsReEnable_reverts] |
| DMCT-REENABLE-L03 | ADMIN_ROLE holder | false | false | initialized; within grace | DepositManagerConfigTimelock_PolicyInactive(subject) | Unchanged | Covered: [test][test_givenInactivePaused_whenReEnabled_reverts] |
| DMCT-REENABLE-L04 | Fuzz all callers | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAnyCallerReEnables_reverts] |
| DMCT-REENABLE-L05 | Fuzz all callers | true | false | Fresh active/configured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts] |
| DMCT-REENABLE-L06 | Fuzz all callers | false | false | Fresh inactive/unconfigured policy; lastTransitionAt=0 | NeverEnabled(), before authorization | Unchanged | Covered: [test][test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-I01 | Fuzz unauthorized callers | false | false | Expired grace and inactive subject | Authorization error before grace or own activity | Unchanged | Covered: [test][test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts] |
| DMCT-REENABLE-I02 | ADMIN_ROLE holder | false | false | Own inactivity and expired grace compete | GracePeriod_Expired(D), before own activity | Unchanged | Covered: [test][test_givenInactive_whenGraceExpired_reverts] |
| DMCT-REENABLE-I08 | ADMIN_ROLE holder | false | false | Own inactivity and broken dependency compete | Own-policy inactivity before dependency probes | Unchanged | Covered: [test][test_givenInactiveAndBrokenDependency_whenActivation_reverts] |
| DMCT-REENABLE-I03 | ADMIN_ROLE holder | true | false | Expired grace and broken dependency compete | GracePeriod_Expired(D), before dependency probes | Unchanged | Covered: [test][test_givenBrokenDependency_whenExpiredGrace_reverts] |

## Grace boundaries

Subject active and initially enabled for pause setup; caller is otherwise permitted.

| ID | Caller | Grace G | Pause timestamp L | Evaluation timestamp | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-N01 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz 1..MAX48-G | Fuzz L..D | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenIndependentGraceAndTimeWithinWindow], [test][test_givenSecondary_whenIndependentGraceAndTimeWithinWindow] |
| DMCT-REENABLE-N02 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz 1..MAX48-G-1 | Fuzz D+1..MAX48; seed MAX48 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenIndependentGraceAndTimeExpired_reverts], [test][test_whenMaximumTimestampIsExpired_reverts] |
| DMCT-REENABLE-N03 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Seeds 1,7,MAX32 | 100; MAX48-1 | L,D-1,D; MAX48 | Success; inclusive deadline | Exact transition; preserve other state | Covered: [test][test_whenImmediately], [test][test_whenOneBeforeDeadline], [test][test_whenAtDeadline], [test][test_whenAtMaximumGraceDeadline], [test][test_whenDeadlineIsMaximumTimestamp] |
| DMCT-REENABLE-N04 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | 1 | 100 | 102=D+1 | GracePeriod_Expired(D) | Unchanged | Covered: [test][test_whenFirstTimestampAfterDeadline_reverts] |
| DMCT-REENABLE-N05 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Fuzz 1..MAX32 | Fuzz MAX48-G+1..MAX48 | L; widened D overflows uint48 | SafeCastOverflowedUintDowncast(48,L+G) | Unchanged | Covered: [test][test_whenDeadlineOverflows_reverts], [test][test_whenMaximumTimestampMakesDeadlineOverflow_reverts] |
| DMCT-REENABLE-N06 | ADMIN or DEPOSIT_MANAGER_ADMIN, including their overlap | Initial nonzero | 0 | 0 | NeverEnabled(); zero is the shared history sentinel | Unchanged | Covered: [test][test_givenZeroTransitionTimestamp_whenReEnabled_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated and reactivated within grace | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenReEnabled] |
| DMCT-REENABLE-P02 | ADMIN_ROLE holder | true | false | Two pauses, distinct timestamps; each uses its latest deadline | Success | Exact transition; preserve other state | Covered: [test][test_whenRepeatedCyclesRestartGrace] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Dependency active | Dependency enabled | Compatibility or recovery condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-D08 | ADMIN_ROLE holder | true | true | DepositManager active=true; enabled=true | Success | Exact transition; other state preserved | Covered: [test][test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds] |
| DMCT-REENABLE-D09 | ADMIN_ROLE holder | true | false | DepositManager active=true; enabled=false | Success; active paused target is accepted | Exact lifecycle transition; target and queue preserved | Covered: [test][test_givenManagerActiveTrueEnabledFalse_whenActivationSucceeds] |
| DMCT-REENABLE-D10 | ADMIN_ROLE holder | false | true | DepositManager active=false; enabled=true | PolicyDependency_NotActive(DM) | Unchanged | Covered: [test][test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts] |
| DMCT-REENABLE-D11 | ADMIN_ROLE holder | false | false | DepositManager active=false; enabled=false | PolicyDependency_NotActive(DM) | Unchanged | Covered: [test][test_givenManagerActiveFalseEnabledFalse_whenActivation_reverts] |
| DMCT-REENABLE-D01 | ADMIN_ROLE holder | true | false | Foreign reported Kernel plus paused manager; compatibility before readiness | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenForeignKernelAndPausedManager_whenActivation_reverts] |
| DMCT-REENABLE-D02 | ADMIN_ROLE holder | true | true | Kernel getter reverts | PolicyDependency_InvalidDependency(DM) | Unchanged | Covered: [test][test_givenKernelReadReverts_whenActivation_reverts] |
| DMCT-REENABLE-D04 | ADMIN_ROLE holder | true | true | Status getter reverts | Success; isEnabled metadata is not consumed | Exact lifecycle transition; other state preserved | Covered: [test][test_givenStatusReadReverts_whenActivationSucceeds] |
| DMCT-REENABLE-D03 | ADMIN_ROLE holder | true | true | Noncanonical Kernel ABI word | PolicyDependency_InvalidDependency(DM) | Unchanged | Covered: [test][test_givenNoncanonicalKernel_whenActivation_reverts], [test][test_givenMalformedKernelLength_whenActivation_reverts] |
| DMCT-REENABLE-D05 | ADMIN_ROLE holder | true | true | Noncanonical Status ABI word | Success; isEnabled metadata is not consumed | Exact lifecycle transition; other state preserved | Covered: [test][test_givenNoncanonicalStatus_whenActivationSucceeds], [test][test_givenMalformedStatusLength_whenActivationSucceeds] |
| DMCT-REENABLE-D06 | ADMIN_ROLE holder | true | true | Manager selects a different configOperator | ConfigOperator_Unauthorized(this timelock) | Unchanged | Covered: [test][test_givenDifferentConfigOperator_whenActivation_reverts] |
| DMCT-REENABLE-D07 | ADMIN_ROLE holder | true | false | Paused manager restored before activation; no stale failure cached | Success | Exact transition; other state preserved | Covered: [test][test_givenManagerReadinessRestored_whenActivationSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

## Secondary-role dependency regression

| ID | Caller | Local active | Local enabled | Manager active | Manager enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-D12 | DEPOSIT_MANAGER_ADMIN | true | false | false | true | PolicyDependency_NotActive(manager) | Unchanged | Covered: [test][test_givenDepositManagerBecomesInactive_reEnableReverts] |

## Compatibility before readiness

| ID | Caller | Local active | Local enabled | Dependency active | Dependency enabled getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-REENABLE-D13 | ADMIN | true | false | false | Noncanonical bool=2 | PolicyDependency_NotActive(dependency) | Unchanged | Covered: [test][test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts] |

## Activation interface and operator metadata

Own policy is active and locally disabled; caller is permitted, payload is empty, and reEnable history/grace pass when applicable. The target reports the intended Kernel and is active. These checks do not depend on target local enablement. Earlier lifecycle, authorization, payload and grace checks retain their order.

| ID | Target metadata | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-REENABLE-D14 | Each consumed interface missing; deterministic seed for every interface | DepositManagerConfigTimelock_InvalidDepositManager(DM) | No lifecycle transition | Covered: [test][test_givenMissingConsumedInterface_whenActivation_reverts], [seeds][test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts] |
| DMCT-REENABLE-D15 | Operator getter reverts, returns noncanonical address, or returns a non-word length | DepositManagerConfigTimelock_InvalidDepositManager(DM) | No lifecycle transition | Covered: [revert][test_givenOperatorReadReverts_whenActivation_reverts], [canonical word][test_givenNoncanonicalOperator_whenActivation_reverts], [length fuzz][test_givenMalformedOperatorLength_whenActivation_reverts] |
| DMCT-REENABLE-D16 | Canonical zero or different operator; fuzz every address except this timelock | ConfigOperator_Unauthorized(this timelock) | No lifecycle transition | Covered: [fuzz][test_givenUnselectedOperator_whenActivation_reverts], [zero][test_givenZeroOperator_whenActivation_reverts] |

[test_givenPaused_whenAdminReEnables]: reEnable.t.sol#L27
[test_givenSecondaryOnly_whenReEnabled]: reEnable.t.sol#L35
[test_givenAdminAndSecondary_whenReEnabled]: reEnable.t.sol#L42
[test_whenPermittedCallerSeedsReEnable]: reEnable.t.sol#L50
[test_givenPaused_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L57
[test_givenPaused_whenUnauthorizedCallerSeedsReEnable_reverts]: reEnable.t.sol#L69
[test_givenEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L86
[test_givenEnabled_whenCallerSeedsReEnable_reverts]: reEnable.t.sol#L582
[test_givenInactivePaused_whenReEnabled_reverts]: reEnable.t.sol#L95
[test_givenInactiveEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L111
[test_givenNeverEnabledConfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L122
[test_givenNeverEnabledUnconfigured_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L134
[test_givenExpiredInactive_whenUnauthorizedCallerReEnables_reverts]: reEnable.t.sol#L146
[test_givenInactive_whenGraceExpired_reverts]: reEnable.t.sol#L302
[test_givenInactiveAndBrokenDependency_whenActivation_reverts]: reEnable.t.sol#L522
[test_givenBrokenDependency_whenExpiredGrace_reverts]: reEnable.t.sol#L543
[test_whenIndependentGraceAndTimeWithinWindow]: reEnable.t.sol#L163
[test_givenSecondary_whenIndependentGraceAndTimeWithinWindow]: reEnable.t.sol#L179
[test_whenIndependentGraceAndTimeExpired_reverts]: reEnable.t.sol#L195
[test_whenMaximumTimestampIsExpired_reverts]: reEnable.t.sol#L570
[test_whenImmediately]: reEnable.t.sol#L216
[test_whenOneBeforeDeadline]: reEnable.t.sol#L224
[test_whenAtDeadline]: reEnable.t.sol#L232
[test_whenAtMaximumGraceDeadline]: reEnable.t.sol#L240
[test_whenDeadlineIsMaximumTimestamp]: reEnable.t.sol#L248
[test_whenFirstTimestampAfterDeadline_reverts]: reEnable.t.sol#L256
[test_whenDeadlineOverflows_reverts]: reEnable.t.sol#L268
[test_whenMaximumTimestampMakesDeadlineOverflow_reverts]: reEnable.t.sol#L287
[test_givenZeroTransitionTimestamp_whenReEnabled_reverts]: reEnable.t.sol#L560
[test_givenReactivated_whenReEnabled]: reEnable.t.sol#L315
[test_whenRepeatedCyclesRestartGrace]: reEnable.t.sol#L325
[test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds]: reEnable.t.sol#L336
[test_givenManagerActiveTrueEnabledFalse_whenActivationSucceeds]: reEnable.t.sol#L344
[test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts]: reEnable.t.sol#L354
[test_givenManagerActiveFalseEnabledFalse_whenActivation_reverts]: reEnable.t.sol#L371
[test_givenForeignKernelAndPausedManager_whenActivation_reverts]: reEnable.t.sol#L390
[test_givenKernelReadReverts_whenActivation_reverts]: reEnable.t.sol#L414
[test_givenStatusReadReverts_whenActivationSucceeds]: reEnable.t.sol#L431
[test_givenNoncanonicalKernel_whenActivation_reverts]: reEnable.t.sol#L441
[test_givenMalformedKernelLength_whenActivation_reverts]: reEnable.t.sol#L458
[test_givenNoncanonicalStatus_whenActivationSucceeds]: reEnable.t.sol#L474
[test_givenMalformedStatusLength_whenActivationSucceeds]: reEnable.t.sol#L484
[test_givenDifferentConfigOperator_whenActivation_reverts]: reEnable.t.sol#L493
[test_givenManagerReadinessRestored_whenActivationSucceeds]: reEnable.t.sol#L510
[test_givenDepositManagerBecomesInactive_reEnableReverts]: reEnable.t.sol#L606
[test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts]: reEnable.t.sol#L624
[test_givenMissingConsumedInterface_whenActivation_reverts]: ./reEnable.t.sol#L646
[test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts]: ./reEnable.t.sol#L682
[test_givenOperatorReadReverts_whenActivation_reverts]: ./reEnable.t.sol#L697
[test_givenNoncanonicalOperator_whenActivation_reverts]: ./reEnable.t.sol#L734
[test_givenMalformedOperatorLength_whenActivation_reverts]: ./reEnable.t.sol#L717
[test_givenUnselectedOperator_whenActivation_reverts]: ./reEnable.t.sol#L754
[test_givenZeroOperator_whenActivation_reverts]: ./reEnable.t.sol#L773
