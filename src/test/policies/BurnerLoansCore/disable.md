# BurnerLoansCore.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-DISABLE` identifies this contract/function.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; No activation dependency validation is performed by this function; ordinary rows use compatible dependencies. No additional gate is implied. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles.

## Authorization

Fixed for this table: Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data empty | `Success` | isEnabled=false; lastTransitionAt=now; Disabled then Transition(caller,false,data,now) | Covered: [test][test_whenDisablingRoleClassesSeeded], [test][test_givenAuthorized_whenDisabled] |
| BLCORE-DISABLE-A03 | Fuzz caller excluding all ADMIN_ROLE and EMERGENCY_ROLE holders | data empty | `NotAuthorised()` | Unchanged | Covered: [test][test_givenUnauthorized_whenDisabled_reverts] |

## Lifecycle

Previously activated policy with cached ROLES; data=0x; Core guard idle. Inactivity is deliberately allowed for disable, including after dependency failure.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-DISABLE-L01 | Fuzz ADMIN_ROLE or EMERGENCY_ROLE holder | true | true | Success | Disable/timestamp/events only; no dependency checks | Covered: [test][test_whenDisablingRoleClassesSeeded], [test][test_givenAuthorized_whenDisabled] |
| BLCORE-DISABLE-L02 | Fuzz ADMIN_ROLE or EMERGENCY_ROLE holder | false | true | Success | Disable/timestamp/events only; no dependency checks | Covered: [test][test_whenDisablingRoleClassesSeeded], [test][test_givenAuthorized_whenDisabled] |
| BLCORE-DISABLE-L03 | Fuzz all callers | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenAlreadyDisabled_whenDisabled_reverts] |
| BLCORE-DISABLE-L04 | Fuzz all callers | false | false | NotEnabled() | Unchanged | Covered: [test][test_givenAlreadyDisabled_whenDisabled_reverts] |

## Inputs

Fixed for this table: Local enabled: true; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes | `BurnerLoans_InvalidEnablerData()` | Covered: [test][test_givenPayload_whenDisabled_reverts] |

## Callbacks and reentrancy

Fixed for this table: Local enabled: true.

| ID | Caller | Callback / nested call | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-DISABLE-C01 | ADMIN_ROLE holder | Core settlement guard entered | `ReentrancyGuardReentrantCall()` | Unchanged; no lifecycle callback may interrupt settlement | Covered: [test][test_givenBusyCore_whenAdminDisables_reverts] |
| BLCORE-DISABLE-C02 | EMERGENCY_ROLE holder without ADMIN_ROLE | Core settlement guard entered | `ReentrancyGuardReentrantCall()` | Unchanged | Covered: [test][test_givenBusyCore_whenEmergencyDisables_reverts] |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenAlreadyDisabled_whenDisabled_reverts] |
| BLCORE-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Covered: [test][test_givenUnauthorized_whenDisabled_reverts] |
| BLCORE-DISABLE-I05 | ADMIN_ROLE holder | Nonempty bytes; valid transition state; Core guard entered | `ReentrancyGuardReentrantCall()` | Unchanged; existing settlement guard rejects before data | Covered: [test][test_givenBusyCore_whenPayloadDisables_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-DISABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverConfigured_whenDisabled_reverts] |

[test_givenAlreadyDisabled_whenDisabled_reverts]: disable.t.sol#L64
[test_givenAuthorized_whenDisabled]: disable.t.sol#L34
[test_givenBusyCore_whenAdminDisables_reverts]: disable.t.sol#L95
[test_givenBusyCore_whenEmergencyDisables_reverts]: disable.t.sol#L110
[test_givenBusyCore_whenPayloadDisables_reverts]: disable.t.sol#L127
[test_givenNeverConfigured_whenDisabled_reverts]: disable.t.sol#L84
[test_givenPayload_whenDisabled_reverts]: disable.t.sol#L76
[test_givenUnauthorized_whenDisabled_reverts]: disable.t.sol#L55
[test_whenDisablingRoleClassesSeeded]: disable.t.sol#L23
