# RevenueDistributorConfigTimelock.enable scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: inherited enable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Scenario scope: `RDCT-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Admin only; fuzz unauthorized callers excluding every Admin identity. RD.kernel must equal RDT.kernel; mismatch gives PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel). RD must also be active in this timelock’s Kernel and locally enabled.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,data,timestamp). Preserve existing configuration/debt/custody. Successful enable uses empty data; nonempty data must revert.

## Authorization

Fixed for this table: Effects and events: Unchanged.

| ID | Caller | Inputs / competing fault | Expected result | Test |
| --- | --- | --- | --- | --- |
| RDCT-ENABLE-A01 | Fuzz callers excluding every ADMIN_ROLE holder | Disabled; enable hook otherwise valid; exclude all admins | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_givenDisabled_whenCallerLacksAdmin_reverts], [test][test_givenEnableBoundarySeeds] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-L01 | ADMIN_ROLE holder | true | false | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenPreviouslyEnabled_whenAuthorizedAdminEnables], [test][test_givenEnableBoundarySeeds] |
| RDCT-ENABLE-L02 | Fuzz all callers | true | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |
| RDCT-ENABLE-L03 | ADMIN_ROLE holder | false | false | RevenueDistributorConfigTimelock_PolicyNotActive(this policy) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactivePolicy_whenEmptyEnable_reverts] |
| RDCT-ENABLE-L04 | Fuzz all callers | false | true | NotDisabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |

## Dependency compatibility

The named distributor identity cases below own this check; selection as configOperator is a queue/execution prerequisite, not an activation gate.

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-I01 | ADMIN_ROLE holder | Fuzz bytes of length 1..256; seed 0x00, 0x01, 32-byte ABI zero, 256 bytes | `IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData()` | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts], [test][test_givenEnableBoundarySeeds] |
| RDCT-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenEnabled_whenAnyCallerEnables_reverts], [test][test_givenEnableBoundarySeeds] |
| RDCT-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test][test_givenDisabled_whenCallerLacksAdmin_reverts], [test][test_givenEnableBoundarySeeds] |

## First activation

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-P01 | ADMIN_ROLE holder | true | false | 0 | Success | Enabled; timestamp recorded; no funds or configuration changed | Covered: [test][test_givenNeverEnabled_whenAuthorizedAdminEnables], [test][test_givenEnableBoundarySeeds] |

## Dependency identity and lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. Bound RevenueDistributor reports the same Kernel; its activity and enablement are required operational activation gates. All rows use data=0x except the dedicated payload cases. Local enabled=false, own Kernel active=true; reEnable within grace if applicable.

| ID | Caller | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-D01 | ADMIN_ROLE holder | true | true | Same Kernel | Success | Only local lifecycle transition; RD state and queue preserved | Covered: [test][test_givenPreviouslyEnabled_whenAuthorizedAdminEnables], [test][test_givenEnableBoundarySeeds] |
| RDCT-ENABLE-D02 | ADMIN_ROLE holder | true | false | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenActivation_reverts], [test][test_givenDistributorStateSeeds_whenActivation_reverts] |
| RDCT-ENABLE-D03 | ADMIN_ROLE holder | false | true | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenActivation_reverts], [test][test_givenDistributorStateSeeds_whenActivation_reverts] |
| RDCT-ENABLE-D04 | ADMIN_ROLE holder | false | false | Same Kernel | PolicyDependency_NotActive(RD) | Unchanged; no transition or committed logs; restore target readiness and retry | Covered: [test][test_givenUnavailableDistributor_whenActivation_reverts], [test][test_givenDistributorStateSeeds_whenActivation_reverts] |
| RDCT-ENABLE-D05 | ADMIN_ROLE holder | true | true | Different Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | Unchanged; no logs | Covered: [test][test_givenDistributorKernelDrift_whenActivation_reverts] |

## Additional existing test evidence

- [test_whenNeverEnabled_adminCanEnable][test_whenNeverEnabled_adminCanEnable] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenAdminEnablesDisabledPolicy_recordsTransition][test_whenAdminEnablesDisabledPolicy_recordsTransition] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenAlreadyEnabled_revertsBeforeAuthorization][test_whenAlreadyEnabled_revertsBeforeAuthorization] — existing regression evidence; review generators and assertions before mapping the expanded cases.
- [test_whenDistributorKernelMismatches_reverts][test_whenDistributorKernelMismatches_reverts] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts] |

## Current focused implementation evidence

The product hooks now enforce empty lifecycle payloads, inactive-disable availability and active enable/reEnable (where supported). [Function-specific lifecycle tests](enable.t.sol) exercise ADMIN transitions and nonempty fuzz inputs against real fixtures. This is partial coverage: emergency/secondary-role transitions, all dependency drifts, exact events and overflow drivers remain independently mapped. Existing inactive-enable success tests are historical regression inputs, not proof of the new expectation.

Dependency classification: RD is a direct operational Policy service. Construction validates compatibility without requiring readiness. Activation requires a canonical Kernel/status response, reported Kernel equal to this consumer's Kernel, authoritative membership in that Kernel and local enablement. Malformed metadata gives `RevenueDistributorConfigTimelock_InvalidDistributor(RD)`; a readable foreign Kernel gives `PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel)` before readiness; a compatible paused/inactive target gives `PolicyDependency_NotActive(RD)`. Enable and reEnable use the same predicate.

[test_givenInactivePolicy_whenEmptyEnable_reverts]: ./enable.t.sol#L149
[test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts]: ./enable.t.sol#L174

## Kernel drift and restoration

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Kernel binding | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-ENABLE-D06 | Admin | true | false | Fuzz false/true | true | Different reported Kernel after construction | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) before readiness | No transition | Covered: [test][test_givenDistributorKernelDrift_whenActivation_reverts] |
| RDCT-ENABLE-P02 | Admin | true | false | Restored false to true | Restored false to true | Same Kernel | Failed activation then successful retry | Pending accounting preserved | Covered: [test][test_givenRestoredDistributor_whenActivation_succeeds] |

[test_givenDistributorKernelDrift_whenActivation_reverts]: ./enable.t.sol#L185
[test_givenRestoredDistributor_whenActivation_succeeds]: ./enable.t.sol#L247
[test_givenUnavailableDistributor_whenActivation_reverts]: ./enable.t.sol#L205
[test_givenDistributorStateSeeds_whenActivation_reverts]: ./enable.t.sol#L237

[test_givenDisabled_whenCallerLacksAdmin_reverts]: ./enable.t.sol#L287

[test_givenEnableBoundarySeeds]: ./enable.t.sol#L407

[test_givenPreviouslyEnabled_whenAuthorizedAdminEnables]: ./enable.t.sol#L348

[test_givenNeverEnabled_whenAuthorizedAdminEnables]: ./enable.t.sol#L376

[test_givenEnabled_whenAnyCallerEnables_reverts]: ./enable.t.sol#L259

[test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts]: ./enable.t.sol#L317

[test_whenAdminEnablesDisabledPolicy_recordsTransition]: ./enable.t.sol#L24

[test_whenDistributorKernelMismatches_reverts]: ./enable.t.sol#L71

[test_whenNeverEnabled_adminCanEnable]: ./enable.t.sol#L91

[test_whenAlreadyEnabled_revertsBeforeAuthorization]: ./enable.t.sol#L44
