# PriceCache.enable coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol); inherited
[EnablerV2](../../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../../bases/ReEnablerGracePeriod.sol).
Scope: `PCACHE-ENABLE`. Existing scenario IDs remain stable.

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

PRICE and ROLES are Kernel modules. No Policy-ready check is invented for PRICE. The
fixture preserves three cached pairs, non-contract metadata/epochs and all bindings.
PRICE runtime failure does not prevent local lifecycle transitions.

## Authorization

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ENABLE-A01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables], [test][test_whenAdminAndOverlapSeedsEnable] |
| PCACHE-ENABLE-A02 | Fuzz callers excluding every ADMIN; retain zero and secondary roles | true | false | empty payload | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerEnables_reverts], [test][test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ENABLE-L01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables] |
| PCACHE-ENABLE-L02 | ADMIN_ROLE holder | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAdminEnables_reverts] |
| PCACHE-ENABLE-L03 | ADMIN_ROLE holder | false | false |  | PriceCache_PolicyInactive() | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminEnables_reverts] |
| PCACHE-ENABLE-L04 | ADMIN_ROLE holder | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAdminEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ENABLE-I01 | Fuzz ADMIN_ROLE holder | true | false | Payload length 1..256, independently fuzz caller | PriceCache_InvalidData() | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts], [test][test_givenDisabled_whenPayloadBoundarySeeds_reverts] |
| PCACHE-ENABLE-I02 | Fuzz unauthorized callers | true | false | nonempty payload | ROLES_RequireRole(ADMIN_ROLE), before payload | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHE-ENABLE-I03 | ADMIN_ROLE holder | true | true | nonempty payload | NotDisabled(), before payload | Unchanged | Covered: [test][test_givenEnabled_whenAdminUsesNonemptyPayload_reverts] |
| PCACHE-ENABLE-I04 | Fuzz unauthorized callers | true | true | nonempty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHE-ENABLE-I05 | Fuzz unauthorized callers | true | true | empty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts] |
| PCACHE-ENABLE-I06 | ADMIN_ROLE holder | false | false | nonempty payload | PriceCache_InvalidData(), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenNonemptyPayload_reverts] |
| PCACHE-ENABLE-I07 | Fuzz unauthorized callers | false | false | empty payload | ROLES_RequireRole(ADMIN_ROLE), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated then reactivated | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenAdminEnables] |
| PCACHE-ENABLE-P02 | ADMIN_ROLE holder | true | false | Fresh configured active policy; no transition history | Success | Exact transition; preserve other state | Covered: [test][test_givenNeverEnabled_whenAdminEnables] |
| PCACHE-ENABLE-P03 | ADMIN_ROLE holder | true | false | Paused after grace expires; enable remains the governance recovery route | Success | Exact transition; preserve other state | Covered: [test][test_givenExpiredGrace_whenAdminEnables] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| PCACHE-ENABLE-D01 | ADMIN_ROLE holder | PRICE runtime calls revert; module binding remains intact | Success | Exact transition; other state preserved | Covered: [test][test_givenPriceReadsRevert_whenTransitionSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenDisabled_whenAdminEnables]: enable.t.sol#L19
[test_whenAdminAndOverlapSeedsEnable]: enable.t.sol#L26
[test_givenDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L36
[test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts]: enable.t.sol#L48
[test_givenEnabled_whenAdminEnables_reverts]: enable.t.sol#L70
[test_givenInactiveDisabled_whenAdminEnables_reverts]: enable.t.sol#L79
[test_givenInactiveEnabled_whenAdminEnables_reverts]: enable.t.sol#L92
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L101
[test_givenDisabled_whenPayloadBoundarySeeds_reverts]: enable.t.sol#L113
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L129
[test_givenEnabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L142
[test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L153
[test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts]: enable.t.sol#L166
[test_givenInactiveDisabled_whenNonemptyPayload_reverts]: enable.t.sol#L178
[test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L189
[test_givenReactivated_whenAdminEnables]: enable.t.sol#L201
[test_givenNeverEnabled_whenAdminEnables]: enable.t.sol#L211
[test_givenExpiredGrace_whenAdminEnables]: enable.t.sol#L217
[test_givenPriceReadsRevert_whenTransitionSucceeds]: enable.t.sol#L227
