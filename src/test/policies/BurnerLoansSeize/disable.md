# BurnerLoansSeize.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope: `BLLIQ-DISABLE` identifies this contract/function.

The shared action base rejects unused nonempty lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The shared action base enforces this payload restriction. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data empty | `Success` | isEnabled=false; lastTransitionAt=now; Disabled then Transition(caller,false,data,now) | Covered: [test_givenEnabled_whenPermittedCallerDisables_thenExactTransition][test_givenEnabled_whenPermittedCallerDisables_thenExactTransition], [test_givenEachPermittedRole_whenDisabled_thenExactTransition][test_givenEachPermittedRole_whenDisabled_thenExactTransition] |
| BLLIQ-DISABLE-A03 | Fuzz caller excluding all ADMIN_ROLE and EMERGENCY_ROLE holders | data empty | `NotAuthorised()` | Unchanged | Covered: [test_givenEnabled_whenUnauthorizedDisables_reverts][test_givenEnabled_whenUnauthorizedDisables_reverts] |
| BLLIQ-DISABLE-A04 | ADMIN_ROLE holder | Action lacks BL_LIQUIDATION_POLICY_ROLE | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Covered: [test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds][test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-L01 | Fuzz all callers | true | false | true | true | data=0x; other dependencies fixed ready | `NotEnabled()` | Unchanged; state error before caller | Covered: [test_givenDisabled_whenAnyCallerDisables_reverts][test_givenDisabled_whenAnyCallerDisables_reverts] |
| BLLIQ-DISABLE-L02 | ADMIN_ROLE holder | false | true | true | true | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | Success | Local pause/timestamp/events only; no own membership or dependency checks | Covered: [test_givenEnabled_whenPermittedCallerDisables_thenExactTransition][test_givenEnabled_whenPermittedCallerDisables_thenExactTransition], [test_givenEachPermittedRole_whenDisabled_thenExactTransition][test_givenEachPermittedRole_whenDisabled_thenExactTransition] |
| BLLIQ-DISABLE-L03 | ADMIN_ROLE holder | true | true | false | true | data=0x; other dependencies fixed ready | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Covered: [test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored][test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored] |
| BLLIQ-DISABLE-L04 | ADMIN_ROLE holder | true | true | true | false | data=0x; other dependencies fixed ready | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Covered: [test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored][test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored] |
| BLLIQ-DISABLE-L05 | ADMIN_ROLE holder | true | true | false | false | data=0x; other dependencies fixed ready | `Success` | Local transition and exact events; canonical positions and balances preserved | Covered: [test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored][test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored] |

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true; Accounting / events: Only local pause/timestamp/events change; no dependency validation on disable.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-D01 | ADMIN_ROLE holder | Core reports another Kernel | `Success` | Covered: [test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead][test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead], [test_givenCoreReportsAnotherKernel_whenDisabled_thenDependencyIgnored][test_givenCoreReportsAnotherKernel_whenDisabled_thenDependencyIgnored] |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes | `BurnerLoans_InvalidEnablerData()` | Covered: [test_whenNonemptyDisableData_reverts][test_whenNonemptyDisableData_reverts], [test_givenEmergencyOrOverlappingRoles_whenPayloadProvided_reverts][test_givenEmergencyOrOverlappingRoles_whenPayloadProvided_reverts], [test_whenPayloadLengthNonzero_reverts][test_whenPayloadLengthNonzero_reverts], [test_whenPayloadBoundarySeedsProvided_reverts][test_whenPayloadBoundarySeedsProvided_reverts] |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Covered: [test_givenDisabled_whenNonemptyDisableData_thenStateWins][test_givenDisabled_whenNonemptyDisableData_thenStateWins] |
| BLLIQ-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Covered: [test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins][test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-DISABLE-L06 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverActivated_whenDisabled_thenInitializationPrecedence][test_givenNeverActivated_whenDisabled_thenInitializationPrecedence] |

## Kernel-inactive pause

Disable does not check own Kernel membership. Previously activated, then deactivated policies retain cached ROLES; this permits ADMIN/EMERGENCY authorization while inactive. Already-disabled state still rejects before authorization. Core/dependency activity and enablement do not prevent a local pause.

Retired duplicate caller IDs: BLLIQ-DISABLE-A02, BLLIQ-DISABLE-I02. Retained families include both exclusive classes and overlap seeds; test mappings stay Partial until their full combined domain is proved.

[test_givenAnyCoreState_whenDisabled_thenDependenciesIgnored]: disable.t.sol#L127
[test_givenCoreKernelViewBroken_whenDisabled_thenNoDependencyRead]: disable.t.sol#L98
[test_givenCoreReportsAnotherKernel_whenDisabled_thenDependencyIgnored]: disable.t.sol#L195
[test_givenDisabled_whenAnyCallerDisables_reverts]: disable.t.sol#L62
[test_givenDisabled_whenNonemptyDisableData_thenStateWins]: disable.t.sol#L107
[test_givenEachPermittedRole_whenDisabled_thenExactTransition]: disable.t.sol#L154
[test_givenEmergencyOrOverlappingRoles_whenPayloadProvided_reverts]: disable.t.sol#L179
[test_givenEnabled_whenPermittedCallerDisables_thenExactTransition]: disable.t.sol#L24
[test_givenEnabled_whenUnauthorizedDisables_reverts]: disable.t.sol#L50
[test_givenEnabled_whenUnauthorizedNonemptyDisable_thenAuthWins]: disable.t.sol#L116
[test_givenNeverActivated_whenDisabled_thenInitializationPrecedence]: disable.t.sol#L142
[test_givenSettlementRoleRevoked_whenDisabled_thenSucceeds]: disable.t.sol#L90
[test_whenNonemptyDisableData_reverts]: disable.t.sol#L74
[test_whenPayloadBoundarySeedsProvided_reverts]: disable.t.sol#L208
[test_whenPayloadLengthNonzero_reverts]: disable.t.sol#L185
