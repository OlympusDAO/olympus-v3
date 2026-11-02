# DepositManager.enable coverage plan

Source: [DepositManager](../../../policies/deposits/DepositManager.sol); inherited
[EnablerV2](../../../bases/EnablerV2.sol) and
[ReEnablerGracePeriod](../../../bases/ReEnablerGracePeriod.sol).
Scope: `DM-ENABLE`. Existing scenario IDs remain stable.

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
| DM-ENABLE-A01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables], [test][test_whenAdminAndOverlapSeedsEnable] |
| DM-ENABLE-A02 | Fuzz callers excluding every ADMIN; retain zero and secondary roles | true | false | empty payload | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerEnables_reverts], [test][test_givenDisabled_whenUnauthorizedCallerSeedsEnable_reverts] |

## Local lifecycle and history

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-ENABLE-L01 | Fuzz every ADMIN_ROLE holder | true | false | empty payload | Success | Exact transition; preserve other state | Covered: [test][test_givenDisabled_whenAdminEnables] |
| DM-ENABLE-L02 | ADMIN_ROLE holder | true | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenAdminEnables_reverts] |
| DM-ENABLE-L03 | ADMIN_ROLE holder | false | false |  | DepositManager_PolicyInactive() | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAdminEnables_reverts] |
| DM-ENABLE-L04 | ADMIN_ROLE holder | false | true |  | NotDisabled() | Unchanged | Covered: [test][test_givenInactiveEnabled_whenAdminEnables_reverts] |

## Payloads and competing guards

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-ENABLE-I01 | Fuzz ADMIN_ROLE holder | true | false | Payload length 1..256, independently fuzz caller | DepositManager_InvalidData() | Unchanged | Covered: [test][test_givenDisabled_whenAdminUsesNonemptyPayload_reverts], [test][test_givenDisabled_whenPayloadBoundarySeeds_reverts] |
| DM-ENABLE-I02 | Fuzz unauthorized callers | true | false | nonempty payload | ROLES_RequireRole(ADMIN_ROLE), before payload | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DM-ENABLE-I03 | ADMIN_ROLE holder | true | true | nonempty payload | NotDisabled(), before payload | Unchanged | Covered: [test][test_givenEnabled_whenAdminUsesNonemptyPayload_reverts] |
| DM-ENABLE-I04 | Fuzz unauthorized callers | true | true | nonempty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts] |
| DM-ENABLE-I05 | Fuzz unauthorized callers | true | true | empty payload | NotDisabled(), before authorization | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts] |
| DM-ENABLE-I06 | ADMIN_ROLE holder | false | false | nonempty payload | DepositManager_InvalidData(), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenNonemptyPayload_reverts] |
| DM-ENABLE-I07 | Fuzz unauthorized callers | false | false | empty payload | ROLES_RequireRole(ADMIN_ROLE), before own activity | Unchanged | Covered: [test][test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts] |

## Restoration and interfaces

| ID | Caller | Local active | Local enabled | Payload or history | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-ENABLE-P01 | ADMIN_ROLE holder | true | false | Paused policy deactivated then reactivated | Success | Exact transition; preserve other state | Covered: [test][test_givenReactivated_whenAdminEnables] |
| DM-ENABLE-P02 | ADMIN_ROLE holder | true | false | Fresh configured active policy; no transition history | Success | Exact transition; preserve other state | Covered: [test][test_givenNeverEnabled_whenAdminEnables] |
| DM-ENABLE-P03 | ADMIN_ROLE holder | true | false | Paused after grace expires; enable remains the governance recovery route | Success | Exact transition; preserve other state | Covered: [test][test_givenExpiredGrace_whenAdminEnables] |

## Dependency admission

Subject active=true and enabled=false; earlier caller/history/grace guards pass.

| ID | Caller | Service condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DM-ENABLE-D01 | ADMIN_ROLE holder | Vault delivery rejects; transitions neither redeem nor move custody | Success | Exact transition; other state preserved | Covered: [test][test_givenVaultDeliveryReverts_whenTransitionSucceeds] |

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
[test_givenDisabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L137
[test_givenEnabled_whenAdminUsesNonemptyPayload_reverts]: enable.t.sol#L150
[test_givenEnabled_whenUnauthorizedCallerUsesNonemptyPayload_reverts]: enable.t.sol#L161
[test_givenEnabled_whenUnauthorizedCallerUsesEmptyPayload_reverts]: enable.t.sol#L174
[test_givenInactiveDisabled_whenNonemptyPayload_reverts]: enable.t.sol#L186
[test_givenInactiveDisabled_whenUnauthorizedCallerEnables_reverts]: enable.t.sol#L197
[test_givenReactivated_whenAdminEnables]: enable.t.sol#L209
[test_givenNeverEnabled_whenAdminEnables]: enable.t.sol#L219
[test_givenExpiredGrace_whenAdminEnables]: enable.t.sol#L225
[test_givenVaultDeliveryReverts_whenTransitionSucceeds]: enable.t.sol#L235
