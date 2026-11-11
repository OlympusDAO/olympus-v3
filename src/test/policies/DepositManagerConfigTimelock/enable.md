# DepositManagerConfigTimelock.enable coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DMCT-ENABLE`. Existing scenario IDs remain stable.

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
| DMCT-ENABLE-A01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables], [test][test_whenAdminAndOverlapSeedsEnable] |
| DMCT-ENABLE-A02 | Fuzz callers excluding every ADMIN; retain zero and secondary roles | true | false | empty payload | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerEnables_reverts], [test][test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-ENABLE-L01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables] |
| DMCT-ENABLE-L02 | ADMIN_ROLE holder | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAdminEnables_reverts] |
| DMCT-ENABLE-L03 | ADMIN_ROLE holder | false | false |  | DepositManagerConfigTimelock_PolicyInactive(subject) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminEnables_reverts] |
| DMCT-ENABLE-L04 | ADMIN_ROLE holder | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAdminEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-ENABLE-I01 | Fuzz ADMIN_ROLE holder | true | false | Payload length 1..256, independently fuzz caller | DepositManagerConfigTimelock_InvalidData() | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts], [test][test_givenDisabled_whenPayloadBoundarySeeds_reverts] |
| DMCT-ENABLE-I02 | Fuzz unauthorized callers | true | false | nonempty payload | ROLES_RequireRole(ADMIN_ROLE), before payload | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DMCT-ENABLE-I03 | ADMIN_ROLE holder | true | true | nonempty payload | NotDisabled(), before payload | Unchanged | Covered: [test][test_givenEnabled_whenAdminUsesNonemptyPayload_reverts] |
| DMCT-ENABLE-I04 | Fuzz unauthorized callers | true | true | nonempty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DMCT-ENABLE-I05 | Fuzz unauthorized callers | true | true | empty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts] |
| DMCT-ENABLE-I06 | ADMIN_ROLE holder | false | false | nonempty payload | DepositManagerConfigTimelock_InvalidData(), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenNonemptyPayload_reverts] |
| DMCT-ENABLE-I07 | Fuzz unauthorized callers | false | false | empty payload | ROLES_RequireRole(ADMIN_ROLE), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts] |
| DMCT-ENABLE-I08 | ADMIN_ROLE holder | false | false | Own inactivity and broken dependency compete | Own-policy inactivity before dependency probes | Unchanged | Covered: [test][test_givenInactiveAndBrokenDependency_whenActivation_reverts] |
| DMCT-ENABLE-I09 | ADMIN_ROLE holder | true | false | Nonempty payload plus broken dependency | DepositManagerConfigTimelock_InvalidData(), before dependency probes | Unchanged | Covered: [test][test_givenBrokenDependency_whenNonemptyPayload_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-ENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated then reactivated | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenAdminEnables] |
| DMCT-ENABLE-P02 | ADMIN_ROLE holder | true | false | Fresh configured active policy; no transition history | Success | Exact transition; preserve other state | Covered: [test][test_givenNeverEnabled_whenAdminEnables] |
| DMCT-ENABLE-P03 | ADMIN_ROLE holder | true | false | Paused after grace expires; enable remains the governance recovery route | Success | Exact transition; preserve other state | Covered: [test][test_givenExpiredGrace_whenAdminEnables] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Dependency active | Dependency enabled | Compatibility or recovery condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-ENABLE-L05 | ADMIN_ROLE holder | true | true | DepositManager active=true; enabled=true | Success | Exact transition; other state preserved | Covered: [test][test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds] |
| DMCT-ENABLE-L06 | ADMIN_ROLE holder | true | false | DepositManager active=true; enabled=false | Success; active paused target is accepted | Exact lifecycle transition; target and queue preserved | Covered: [test][test_givenManagerActiveTrueEnabledFalse_whenActivationSucceeds] |
| DMCT-ENABLE-L07 | ADMIN_ROLE holder | false | true | DepositManager active=false; enabled=true | PolicyDependency_NotActive(DM) | Unchanged | Covered: [test][test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts] |
| DMCT-ENABLE-L08 | ADMIN_ROLE holder | false | false | DepositManager active=false; enabled=false | PolicyDependency_NotActive(DM) | Unchanged | Covered: [test][test_givenManagerActiveFalseEnabledFalse_whenActivation_reverts], [test][test_givenDepositManagerIsInactive_enableReverts] |
| DMCT-ENABLE-D01 | ADMIN_ROLE holder | true | false | Foreign reported Kernel plus paused manager; compatibility before readiness | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenForeignKernelAndPausedManager_whenActivation_reverts] |
| DMCT-ENABLE-D02 | ADMIN_ROLE holder | true | true | Kernel getter reverts | PolicyDependency_InvalidDependency(DM) | Unchanged | Covered: [test][test_givenKernelReadReverts_whenActivation_reverts] |
| DMCT-ENABLE-D04 | ADMIN_ROLE holder | true | true | Status getter reverts | Success; isEnabled metadata is not consumed | Exact lifecycle transition; other state preserved | Covered: [test][test_givenStatusReadReverts_whenActivationSucceeds] |
| DMCT-ENABLE-D03 | ADMIN_ROLE holder | true | true | Noncanonical Kernel ABI word | PolicyDependency_InvalidDependency(DM) | Unchanged | Covered: [test][test_givenNoncanonicalKernel_whenActivation_reverts], [test][test_givenMalformedKernelLength_whenActivation_reverts] |
| DMCT-ENABLE-D05 | ADMIN_ROLE holder | true | true | Noncanonical Status ABI word | Success; isEnabled metadata is not consumed | Exact lifecycle transition; other state preserved | Covered: [test][test_givenNoncanonicalStatus_whenActivationSucceeds], [test][test_givenMalformedStatusLength_whenActivationSucceeds] |
| DMCT-ENABLE-D06 | ADMIN_ROLE holder | true | true | Manager selects a different configOperator | ConfigOperator_Unauthorized(this timelock) | Unchanged | Covered: [test][test_givenDifferentConfigOperator_whenActivation_reverts] |
| DMCT-ENABLE-D07 | ADMIN_ROLE holder | true | false | Paused manager restored before activation; no stale failure cached | Success | Exact transition; other state preserved | Covered: [test][test_givenManagerReadinessRestored_whenActivationSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

## Compatibility before readiness

| ID | Caller | Local active | Local enabled | Dependency active | Dependency enabled getter | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-ENABLE-D13 | ADMIN | true | false | false | Noncanonical bool=2 | PolicyDependency_NotActive(dependency) | Unchanged | Covered: [test][test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts] |

## Activation interface and operator metadata

Own policy is active and locally disabled; caller is permitted, payload is empty, and reEnable history/grace pass when applicable. The target reports the intended Kernel and is active. These checks do not depend on target local enablement. Earlier lifecycle, authorization, payload and grace checks retain their order.

| ID | Target metadata | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-ENABLE-D14 | Each consumed interface missing; deterministic seed for every interface | DepositManagerConfigTimelock_InvalidDepositManager(DM) | No lifecycle transition | Covered: [test][test_givenMissingConsumedInterface_whenActivation_reverts], [seeds][test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts] |
| DMCT-ENABLE-D15 | Operator getter reverts, returns noncanonical address, or returns a non-word length | DepositManagerConfigTimelock_InvalidDepositManager(DM) | No lifecycle transition | Covered: [revert][test_givenOperatorReadReverts_whenActivation_reverts], [canonical word][test_givenNoncanonicalOperator_whenActivation_reverts], [length fuzz][test_givenMalformedOperatorLength_whenActivation_reverts] |
| DMCT-ENABLE-D16 | Canonical zero or different operator; fuzz every address except this timelock | ConfigOperator_Unauthorized(this timelock) | No lifecycle transition | Covered: [fuzz][test_givenUnselectedOperator_whenActivation_reverts], [zero][test_givenZeroOperator_whenActivation_reverts] |

[test_givenDisabled_whenAdminEnables]: enable.t.sol#L27
[test_whenAdminAndOverlapSeedsEnable]: enable.t.sol#L34
[test_givenDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L44
[test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts]: enable.t.sol#L56
[test_givenEnabled_whenAdminEnables_reverts]: enable.t.sol#L78
[test_givenInactiveDisabled_whenAdminEnables_reverts]: enable.t.sol#L87
[test_givenInactiveEnabled_whenAdminEnables_reverts]: enable.t.sol#L103
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L112
[test_givenDisabled_whenPayloadBoundarySeeds_reverts]: enable.t.sol#L126
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L158
[test_givenEnabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L171
[test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L182
[test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts]: enable.t.sol#L195
[test_givenInactiveDisabled_whenNonemptyPayload_reverts]: enable.t.sol#L207
[test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L220
[test_givenInactiveAndBrokenDependency_whenActivation_reverts]: enable.t.sol#L444
[test_givenBrokenDependency_whenNonemptyPayload_reverts]: enable.t.sol#L465
[test_givenReactivated_whenAdminEnables]: enable.t.sol#L232
[test_givenNeverEnabled_whenAdminEnables]: enable.t.sol#L242
[test_givenExpiredGrace_whenAdminEnables]: enable.t.sol#L248
[test_givenManagerActiveTrueEnabledTrue_whenActivationSucceeds]: enable.t.sol#L258
[test_givenManagerActiveTrueEnabledFalse_whenActivationSucceeds]: enable.t.sol#L266
[test_givenManagerActiveFalseEnabledTrue_whenActivation_reverts]: enable.t.sol#L276
[test_givenManagerActiveFalseEnabledFalse_whenActivation_reverts]: enable.t.sol#L293
[test_givenDepositManagerIsInactive_enableReverts]: enable.t.sol#L484
[test_givenForeignKernelAndPausedManager_whenActivation_reverts]: enable.t.sol#L312
[test_givenKernelReadReverts_whenActivation_reverts]: enable.t.sol#L336
[test_givenStatusReadReverts_whenActivationSucceeds]: enable.t.sol#L353
[test_givenNoncanonicalKernel_whenActivation_reverts]: enable.t.sol#L363
[test_givenMalformedKernelLength_whenActivation_reverts]: enable.t.sol#L380
[test_givenNoncanonicalStatus_whenActivationSucceeds]: enable.t.sol#L396
[test_givenMalformedStatusLength_whenActivationSucceeds]: enable.t.sol#L406
[test_givenDifferentConfigOperator_whenActivation_reverts]: enable.t.sol#L415
[test_givenManagerReadinessRestored_whenActivationSucceeds]: enable.t.sol#L432
[test_givenInactiveDependencyWithMalformedStatus_whenActivation_reverts]: enable.t.sol#L507
[test_givenMissingConsumedInterface_whenActivation_reverts]: ./enable.t.sol#L529
[test_givenMissingConsumedInterfaceSeeds_whenActivation_reverts]: ./enable.t.sol#L565
[test_givenOperatorReadReverts_whenActivation_reverts]: ./enable.t.sol#L580
[test_givenNoncanonicalOperator_whenActivation_reverts]: ./enable.t.sol#L617
[test_givenMalformedOperatorLength_whenActivation_reverts]: ./enable.t.sol#L600
[test_givenUnselectedOperator_whenActivation_reverts]: ./enable.t.sol#L637
[test_givenZeroOperator_whenActivation_reverts]: ./enable.t.sol#L656
