# BurnerLoansConfigTimelock.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72). Coverage is recorded in the Test column.

Implementation: 10 scenario functions mapped; 10 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-DISABLE` identifies this contract/function.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; No activation dependency validation is performed by this function; ordinary rows use compatible dependencies. No additional gate is implied. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles.

## Authorization

Fixed for this table: Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data empty | `Success` | isEnabled=false; lastTransitionAt=now; Disabled then Transition(caller,false,data,now) | Covered: [test_givenAdminOrEmergency_whenDisabled_thenExactTransition][test_givenAdminOrEmergency_whenDisabled_thenExactTransition]; [test_givenEachPauseRole_whenBoundarySeedsRun_thenScenarioHolds][test_givenEachPauseRole_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-DISABLE-A03 | Fuzz caller excluding all ADMIN_ROLE and EMERGENCY_ROLE holders | data empty | `NotAuthorised()` | Unchanged | Covered: [test_givenUnauthorizedCaller_whenDisabled_reverts][test_givenUnauthorizedCaller_whenDisabled_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-DISABLE-L01 | Fuzz all callers | true | false | data empty | `NotEnabled()` | Unchanged; state error before caller | Covered: [test_givenDisabledActiveTrue_whenDisabledAgain_thenStateError][test_givenDisabledActiveTrue_whenDisabledAgain_thenStateError] |
| BLCT-DISABLE-L02 | Fuzz all callers | false | false | data empty | `NotEnabled()` | Unchanged; state error before caller | Covered: [test_givenDisabledActiveFalse_whenDisabledAgain_thenStateError][test_givenDisabledActiveFalse_whenDisabledAgain_thenStateError] |
| BLCT-DISABLE-L03 | ADMIN_ROLE holder | true | true | Config inactive | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Covered: [test_givenConfigInactive_whenDisabled_thenSuccess][test_givenConfigInactive_whenDisabled_thenSuccess] |
| BLCT-DISABLE-L04 | ADMIN_ROLE holder | false | true | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Covered: [test_givenOwnPolicyInactive_whenDisabled_thenSuccess][test_givenOwnPolicyInactive_whenDisabled_thenSuccess] |

## Inputs

Fixed for this table: Local enabled: true; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes | `BurnerLoans_InvalidEnablerData()` | Covered: [test_givenAuthorizedCaller_whenNonemptyPauseData_reverts][test_givenAuthorizedCaller_whenNonemptyPauseData_reverts]; [test_givenDisableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenDisableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds] |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Covered: [test_givenDisabled_whenNonemptyPauseData_thenStateError][test_givenDisabled_whenNonemptyPauseData_thenStateError]; [test_givenDisableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenDisableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Covered: [test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst][test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst]; [test_givenDisableI04Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenDisableI04Payloads_whenBoundarySeedsRun_thenScenarioHolds] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-DISABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenUninitialized_whenDisabled_thenStateError][test_givenUninitialized_whenDisabled_thenStateError] |

[test_givenAdminOrEmergency_whenDisabled_thenExactTransition]: disable.t.sol#L16
[test_givenEachPauseRole_whenBoundarySeedsRun_thenScenarioHolds]: disable.t.sol#L134
[test_givenUnauthorizedCaller_whenDisabled_reverts]: disable.t.sol#L29
[test_givenDisabledActiveTrue_whenDisabledAgain_thenStateError]: disable.t.sol#L39
[test_givenDisabledActiveFalse_whenDisabledAgain_thenStateError]: disable.t.sol#L49
[test_givenConfigInactive_whenDisabled_thenSuccess]: disable.t.sol#L61
[test_givenOwnPolicyInactive_whenDisabled_thenSuccess]: disable.t.sol#L71
[test_givenAuthorizedCaller_whenNonemptyPauseData_reverts]: disable.t.sol#L81
[test_givenDisableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds]: disable.t.sol#L145
[test_givenDisabled_whenNonemptyPauseData_thenStateError]: disable.t.sol#L96
[test_givenDisableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds]: disable.t.sol#L174
[test_givenUnauthorizedCaller_whenNonemptyPauseData_thenAuthorizationFirst]: disable.t.sol#L110
[test_givenDisableI04Payloads_whenBoundarySeedsRun_thenScenarioHolds]: disable.t.sol#L190
[test_givenUninitialized_whenDisabled_thenStateError]: disable.t.sol#L124
