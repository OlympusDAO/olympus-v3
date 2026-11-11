# DepositManagerConfigTimelock.disable coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DMCT-DISABLE`. Existing scenario IDs remain stable.

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
Activation checks own membership, canonical matching target Kernel/status, then target
membership/enablement. Failed or malformed Kernel/status reads give PolicyDependency_InvalidDependency(DM); a readable foreign Kernel
gives PolicyDependency_KernelMismatch(DM,expectedKernel,reportedKernel); compatible inactive/disabled targets give PolicyDependency_NotActive(DM).
The target configOperator is an authority identity, not an activation prerequisite.
Fixtures preserve a queued cap action including its destination/pre-state/key slots, plus
real deposit receipt, custody and accounting state.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled], [test][test_givenEmergencyOnly_whenDisabled], [test][test_givenAdminAndEmergency_whenDisabled], [test][test_whenPermittedCallerSeedsDisable] |
| DMCT-DISABLE-A03 | Fuzz callers excluding every ADMIN and EMERGENCY | true | true | empty payload | NotAuthorised() | Unchanged | Covered: [test][test_whenUnauthorizedCallerDisables_reverts], [test][test_whenUnauthorizedCallerSeedsDisable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled] |
| DMCT-DISABLE-L02 | ADMIN_ROLE holder | true | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenDisabled_whenAdminDisables_reverts] |
| DMCT-DISABLE-L03 | ADMIN_ROLE holder | false | true |  | Success | Exact transition; preserve other state | Covered: [test][test_givenInactive_whenAdminDisables] |
| DMCT-DISABLE-L04 | ADMIN_ROLE holder | false | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminDisables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | true | true | Payload length 1..256, seed each role with 0x00,0x01,ABI zero,256 bytes | DepositManagerConfigTimelock_InvalidData() | Unchanged | Covered: [test][test_givenAdminOnly_whenNonemptyPayload_reverts], [test][test_givenEmergencyOnly_whenNonemptyPayload_reverts], [test][test_givenAdminAndEmergency_whenNonemptyPayload_reverts], [test][test_whenCallerAndPayloadBoundarySeeds_reverts] |
| DMCT-DISABLE-I03 | Fuzz unauthorized callers | true | true | nonempty payload | NotAuthorised(), before payload | Unchanged | Covered: [test][test_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DMCT-DISABLE-I04 | ADMIN_ROLE holder | true | false | nonempty payload | NotEnabled(), before payload | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts] |
| DMCT-DISABLE-I05 | Fuzz unauthorized callers | true | false | nonempty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DMCT-DISABLE-I06 | Fuzz all callers | true | false | empty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts] |
| DMCT-DISABLE-I07 | ADMIN_ROLE holder | false | true | nonempty payload | DepositManagerConfigTimelock_InvalidData() | Unchanged | Covered: [test][test_givenInactive_whenNonemptyPayload_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-DISABLE-P01 | EMERGENCY-only | true | true | Pause after successful reEnable | Success | Exact transition; preserve other state | Covered: [test][test_givenReEnabled_whenDisabled] |
| DMCT-DISABLE-P02 | EMERGENCY-only | true | true | Pause after Kernel deactivation/reactivation | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenDisabled] |

## Dependency admission

Subject active=true and enabled=true; earlier caller/history/grace guards pass.

| ID | Caller | Dependency active | Dependency enabled | Compatibility or recovery condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-DISABLE-D01 | ADMIN_ROLE holder | true | true | Required dependency kernel/status getters revert; pause remains available | Success | Exact transition; other state preserved | Covered: [test][test_givenDependencyReadsRevert_whenDisabled] |
| DMCT-DISABLE-D02 | ADMIN_ROLE holder | true | true | Dependency active=true; enabled=true; no dependency-readiness gate | Success | Exact transition; other state preserved | Covered: [test][test_givenDependencyActiveTrueEnabledTrue_whenDisabled] |
| DMCT-DISABLE-D03 | ADMIN_ROLE holder | true | false | Dependency active=true; enabled=false; no dependency-readiness gate | Success | Exact transition; other state preserved | Covered: [test][test_givenDependencyActiveTrueEnabledFalse_whenDisabled] |
| DMCT-DISABLE-D04 | ADMIN_ROLE holder | false | true | Dependency active=false; enabled=true; no dependency-readiness gate | Success | Exact transition; other state preserved | Covered: [test][test_givenDependencyActiveFalseEnabledTrue_whenDisabled] |
| DMCT-DISABLE-D05 | ADMIN_ROLE holder | false | false | Dependency active=false; enabled=false; no dependency-readiness gate | Success | Exact transition; other state preserved | Covered: [test][test_givenDependencyActiveFalseEnabledFalse_whenDisabled] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenAdminOnly_whenDisabled]: disable.t.sol#L18
[test_givenEmergencyOnly_whenDisabled]: disable.t.sol#L25
[test_givenAdminAndEmergency_whenDisabled]: disable.t.sol#L32
[test_whenPermittedCallerSeedsDisable]: disable.t.sol#L39
[test_whenUnauthorizedCallerDisables_reverts]: disable.t.sol#L51
[test_whenUnauthorizedCallerSeedsDisable_reverts]: disable.t.sol#L61
[test_givenDisabled_whenAdminDisables_reverts]: disable.t.sol#L80
[test_givenInactive_whenAdminDisables]: disable.t.sol#L89
[test_givenInactiveDisabled_whenAdminDisables_reverts]: disable.t.sol#L94
[test_givenAdminOnly_whenNonemptyPayload_reverts]: disable.t.sol#L107
[test_givenEmergencyOnly_whenNonemptyPayload_reverts]: disable.t.sol#L121
[test_givenAdminAndEmergency_whenNonemptyPayload_reverts]: disable.t.sol#L135
[test_whenCallerAndPayloadBoundarySeeds_reverts]: disable.t.sol#L149
[test_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L240
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: disable.t.sol#L253
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L264
[test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts]: disable.t.sol#L277
[test_givenInactive_whenNonemptyPayload_reverts]: disable.t.sol#L288
[test_givenReEnabled_whenDisabled]: disable.t.sol#L301
[test_givenReactivated_whenDisabled]: disable.t.sol#L307
[test_givenDependencyReadsRevert_whenDisabled]: disable.t.sol#L314
[test_givenDependencyActiveTrueEnabledTrue_whenDisabled]: disable.t.sol#L329
[test_givenDependencyActiveTrueEnabledFalse_whenDisabled]: disable.t.sol#L334
[test_givenDependencyActiveFalseEnabledTrue_whenDisabled]: disable.t.sol#L341
[test_givenDependencyActiveFalseEnabledFalse_whenDisabled]: disable.t.sol#L348
