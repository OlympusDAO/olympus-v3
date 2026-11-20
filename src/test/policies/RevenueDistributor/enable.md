# RevenueDistributor.enable scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: inherited enable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Scenario scope: `RD-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `IRevenueDistributor.RevenueDistributor_InvalidData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Admin only; fuzz unauthorized callers excluding every Admin identity. No target-policy compatibility hook applies.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,data,timestamp). Preserve existing configuration/debt/custody. Successful enable uses empty data; nonempty data must revert.

## Authorization

Fixed for this table: Effects and events: Unchanged.

| ID | Caller | Inputs / competing fault | Expected result | Test |
| --- | --- | --- | --- | --- |
| RD-ENABLE-A01 | Fuzz callers excluding every ADMIN_ROLE holder | Disabled; enable hook otherwise valid; exclude all admins | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_givenDisabled_whenCallerLacksAdmin_reverts], [test][test_givenEnableBoundarySeeds] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-ENABLE-L01 | ADMIN_ROLE holder | true | false | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenPreviouslyEnabled_whenAuthorizedAdminEnables], [test][test_givenEnableBoundarySeeds] |
| RD-ENABLE-L02 | Fuzz all callers | true | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |
| RD-ENABLE-L03 | ADMIN_ROLE holder | false | false | RevenueDistributor_PolicyNotActive(RD) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactivePolicy_whenEmptyEnable_reverts] |
| RD-ENABLE-L04 | Fuzz all callers | false | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-ENABLE-I01 | ADMIN_ROLE holder | Fuzz bytes of length 1..256; seed 0x00, 0x01, 32-byte ABI zero, 256 bytes | `IRevenueDistributor.RevenueDistributor_InvalidData()` | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts], [test][test_givenEnableBoundarySeeds] |
| RD-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |
| RD-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test][test_givenDisabled_whenCallerLacksAdmin_reverts], [test][test_givenEnableBoundarySeeds] |

## First activation

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RD-ENABLE-P01 | ADMIN_ROLE holder | true | false | 0 | Success | Enabled; timestamp recorded; no funds or configuration changed | Covered: [test][test_givenNeverEnabled_whenAuthorizedAdminEnables], [test][test_givenEnableBoundarySeeds] |

## Additional existing test evidence

- [test_givenDisabled_whenAdminEnables_preservesConfiguration][test_givenDisabled_whenAdminEnables_preservesConfiguration] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization][test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_givenPolicyInactiveAndDisabled_whenAdminEnables_reverts][test_givenPolicyInactiveAndDisabled_whenAdminEnables_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD-ENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts] |

## Current focused implementation evidence

The product hooks now enforce empty lifecycle payloads, inactive-disable availability and active enable/reEnable (where supported). [Function-specific lifecycle tests](enable.t.sol) exercise ADMIN transitions and nonempty fuzz inputs against real fixtures. This is partial coverage: emergency/secondary-role transitions, all dependency drifts, exact events and overflow drivers remain independently mapped. Local enable/reEnable rejection tests now follow the activity requirement; remaining role, accounting and boundary gaps are recorded in the mappings.

Dependency classification: ROLES and TRSRY are Kernel modules. The config operator is an authority identity. Settlement delivers ERC-20 tokens directly; activation does not recursively inspect optional recipient or vault lifecycle. Candidate selection and route validation own their compatibility checks.

[test_givenInactivePolicy_whenEmptyEnable_reverts]: ./enable.t.sol#L140
[test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts]: ./enable.t.sol#L160

[test_givenDisabled_whenCallerLacksAdmin_reverts]: ./enable.t.sol#L199

[test_givenEnableBoundarySeeds]: ./enable.t.sol#L321

[test_givenPreviouslyEnabled_whenAuthorizedAdminEnables]: ./enable.t.sol#L260

[test_givenNeverEnabled_whenAuthorizedAdminEnables]: ./enable.t.sol#L289

[test_givenEnabled_whenAnyCallerEnables_reverts]: ./enable.t.sol#L171

[test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts]: ./enable.t.sol#L230

[test_givenDisabled_whenAdminEnables_preservesConfiguration]: ./enable.t.sol#L22

[test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization]: ./enable.t.sol#L43

[test_givenPolicyInactiveAndDisabled_whenAdminEnables_reverts]: ./enable.t.sol#L61
