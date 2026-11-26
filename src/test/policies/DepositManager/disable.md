# DepositManager.disable coverage plan

Source: [DepositManager](../../../policies/deposits/DepositManager.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DM-DISABLE`. Existing scenario IDs remain stable.

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
| DM-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled], [test][test_givenEmergencyOnly_whenDisabled], [test][test_givenAdminAndEmergency_whenDisabled], [test][test_whenPermittedCallerSeedsDisable] |
| DM-DISABLE-A03 | Fuzz callers excluding every ADMIN and EMERGENCY | true | true | empty payload | NotAuthorised() | Unchanged | Covered: [test][test_whenUnauthorizedCallerDisables_reverts], [test][test_whenUnauthorizedCallerSeedsDisable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | true | true | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenAdminOnly_whenDisabled], [test][test_givenEmergencyOnly_whenDisabled], [test][test_givenAdminAndEmergency_whenDisabled], [test][test_whenPermittedCallerSeedsDisable] |
| DM-DISABLE-L02 | ADMIN_ROLE holder | true | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenDisabled_whenAdminDisables_reverts] |
| DM-DISABLE-L03 | ADMIN_ROLE holder | false | true |  | Success | Exact transition; preserve other state | Covered: [test][test_givenInactive_whenAdminDisables] |
| DM-DISABLE-L04 | ADMIN_ROLE holder | false | false |  | NotEnabled() | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminDisables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | true | true | Payload length 1..256, seed each role with 0x00,0x01,ABI zero,256 bytes | DepositManager_InvalidData() | Unchanged | Covered: [test][test_givenAdminOnly_whenNonemptyPayload_reverts], [test][test_givenEmergencyOnly_whenNonemptyPayload_reverts], [test][test_givenAdminAndEmergency_whenNonemptyPayload_reverts], [test][test_whenCallerAndPayloadBoundarySeeds_reverts] |
| DM-DISABLE-I03 | Fuzz unauthorized callers | true | true | nonempty payload | NotAuthorised(), before payload | Unchanged | Covered: [test][test_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DM-DISABLE-I04 | ADMIN_ROLE holder | true | false | nonempty payload | NotEnabled(), before payload | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts] |
| DM-DISABLE-I05 | Fuzz unauthorized callers | true | false | nonempty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DM-DISABLE-I06 | Fuzz all callers | true | false | empty payload | NotEnabled(), before authorization | Unchanged | Covered: [test][test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts] |
| DM-DISABLE-I07 | ADMIN_ROLE holder | false | true | nonempty payload | DepositManager_InvalidData() | Unchanged | Covered: [test][test_givenInactive_whenNonemptyPayload_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-DISABLE-P01 | EMERGENCY-only | true | true | Pause after successful reEnable | Success | Exact transition; preserve other state | Covered: [test][test_givenReEnabled_whenDisabled] |
| DM-DISABLE-P02 | EMERGENCY-only | true | true | Pause after Kernel deactivation/reactivation | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenDisabled] |

## Dependency admission

Subject active=true and enabled=true; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DM-DISABLE-D01 | ADMIN_ROLE holder | Vault delivery rejects; transitions neither redeem nor move custody | Success | Exact transition; other state preserved | Covered: [test][test_givenVaultDeliveryReverts_whenTransitionSucceeds] |

- [x] Verify focused execution and reciprocal named mappings.

[test_givenAdminOnly_whenDisabled]: disable.t.sol#L17
[test_givenEmergencyOnly_whenDisabled]: disable.t.sol#L24
[test_givenAdminAndEmergency_whenDisabled]: disable.t.sol#L31
[test_whenPermittedCallerSeedsDisable]: disable.t.sol#L38
[test_whenUnauthorizedCallerDisables_reverts]: disable.t.sol#L50
[test_whenUnauthorizedCallerSeedsDisable_reverts]: disable.t.sol#L60
[test_givenDisabled_whenAdminDisables_reverts]: disable.t.sol#L79
[test_givenInactive_whenAdminDisables]: disable.t.sol#L88
[test_givenInactiveDisabled_whenAdminDisables_reverts]: disable.t.sol#L93
[test_givenAdminOnly_whenNonemptyPayload_reverts]: disable.t.sol#L106
[test_givenEmergencyOnly_whenNonemptyPayload_reverts]: disable.t.sol#L118
[test_givenAdminAndEmergency_whenNonemptyPayload_reverts]: disable.t.sol#L130
[test_whenCallerAndPayloadBoundarySeeds_reverts]: disable.t.sol#L142
[test_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L209
[test_givenDisabled_whenAdminUsesNonemptyPayload_reverts]: disable.t.sol#L222
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: disable.t.sol#L233
[test_givenDisabled_whenAnyCallerUsesEmptyPayload_reverts]: disable.t.sol#L246
[test_givenInactive_whenNonemptyPayload_reverts]: disable.t.sol#L257
[test_givenReEnabled_whenDisabled]: disable.t.sol#L268
[test_givenReactivated_whenDisabled]: disable.t.sol#L274
[test_givenVaultDeliveryReverts_whenTransitionSucceeds]: disable.t.sol#L281
