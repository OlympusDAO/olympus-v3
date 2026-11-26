# PriceCache.disable coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol); inherited
[EnablerV2](../../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../../bases/ReEnablerGracePeriod.sol).
Scope: `PCACHE-DISABLE`. Existing scenario IDs remain stable.

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
| PCACHE-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled], [test][test_givenEmergencyOnly_whenDisabled], [test][test_givenAdminAndEmergency_whenDisabled], [test][test_whenPermittedCallerSeedsDisable] |
| PCACHE-DISABLE-A03 | Fuzz callers excluding every ADMIN and EMERGENCY | true | true | empty payload | NotAuthorised() | Unchanged | Covered: [test][test_whenUnauthorizedCallerDisables_reverts], [test][test_whenUnauthorizedCallerSeedsDisable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled] |
| PCACHE-DISABLE-L02 | ADMIN_ROLE holder | true | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenDisabled_whenAdminDisables_reverts] |
| PCACHE-DISABLE-L03 | ADMIN_ROLE holder | false | true |  | Success | Exact transition; preserve other state | Covered: [test][test_givenInactive_whenAdminDisables] |
| PCACHE-DISABLE-L04 | ADMIN_ROLE holder | false | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminDisables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | true | true | Payload length 1..256, seed each role with 0x00,0x01,ABI zero,256 bytes | PriceCache_InvalidData() | Unchanged | Covered: [test][test_givenAdminOnly_whenNonemptyPayload_reverts], [test][test_givenEmergencyOnly_whenNonemptyPayload_reverts], [test][test_givenAdminAndEmergency_whenNonemptyPayload_reverts], [test][test_whenCallerAndPayloadBoundarySeeds_reverts] |
| PCACHE-DISABLE-I03 | Fuzz unauthorized callers | true | true | nonempty payload | NotAuthorised(), before payload | Unchanged | Covered: [test][test_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHE-DISABLE-I04 | ADMIN_ROLE holder | true | false | nonempty payload | NotEnabled(), before payload | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts] |
| PCACHE-DISABLE-I05 | Fuzz unauthorized callers | true | false | nonempty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| PCACHE-DISABLE-I06 | Fuzz all callers | true | false | empty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts] |
| PCACHE-DISABLE-I07 | ADMIN_ROLE holder | false | true | nonempty payload | PriceCache_InvalidData() | Unchanged | Covered: [test][test_givenInactive_whenNonemptyPayload_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DISABLE-P01 | EMERGENCY-only | true | true | Pause after successful reEnable | Success | Exact transition; preserve other state | Covered: [test][test_givenReEnabled_whenDisabled] |
| PCACHE-DISABLE-P02 | EMERGENCY-only | true | true | Pause after Kernel deactivation/reactivation | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenDisabled] |

## Dependency admission

Subject active=true and enabled=true; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| PCACHE-DISABLE-D01 | ADMIN_ROLE holder | PRICE runtime calls revert; module binding remains intact | Success | Exact transition; other state preserved | Covered: [test][test_givenPriceReadsRevert_whenTransitionSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenAdminOnly_whenDisabled]: disable.t.sol#L17
[test_givenEmergencyOnly_whenDisabled]: disable.t.sol#L24
[test_givenAdminAndEmergency_whenDisabled]: disable.t.sol#L31
[test_whenPermittedCallerSeedsDisable]: disable.t.sol#L38
[test_whenUnauthorizedCallerDisables_reverts]: disable.t.sol#L50
[test_whenUnauthorizedCallerSeedsDisable_reverts]: disable.t.sol#L60
[test_givenDisabled_whenAdminDisables_reverts]: disable.t.sol#L74
[test_givenInactive_whenAdminDisables]: disable.t.sol#L83
[test_givenInactiveDisabled_whenAdminDisables_reverts]: disable.t.sol#L88
[test_givenAdminOnly_whenNonemptyPayload_reverts]: disable.t.sol#L101
[test_givenEmergencyOnly_whenNonemptyPayload_reverts]: disable.t.sol#L113
[test_givenAdminAndEmergency_whenNonemptyPayload_reverts]: disable.t.sol#L125
[test_whenCallerAndPayloadBoundarySeeds_reverts]: disable.t.sol#L137
[test_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L158
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: disable.t.sol#L171
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L182
[test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts]: disable.t.sol#L195
[test_givenInactive_whenNonemptyPayload_reverts]: disable.t.sol#L206
[test_givenReEnabled_whenDisabled]: disable.t.sol#L217
[test_givenReactivated_whenDisabled]: disable.t.sol#L223
[test_givenPriceReadsRevert_whenTransitionSucceeds]: disable.t.sol#L230
