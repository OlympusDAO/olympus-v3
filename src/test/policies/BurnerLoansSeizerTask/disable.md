# BurnerLoansSeizerTask.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-DISABLE` identifies this contract/function.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; No activation dependency validation is performed by this function; ordinary rows use compatible dependencies. No additional gate is implied. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data empty | `Success` | isEnabled=false; lastTransitionAt=now; Disabled then Transition(caller,false,data,now) | Unmapped |
| BLSEIZ-DISABLE-A03 | Fuzz caller excluding all ADMIN_ROLE and EMERGENCY_ROLE holders | data empty | `NotAuthorised()` | Unchanged | Unmapped |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-DISABLE-L01 | Fuzz all callers | true | false | true | true | data empty | `NotEnabled()` | Unchanged; state error before caller | Unmapped |
| BLSEIZ-DISABLE-L02 | Fuzz all callers | false | false | true | true | data empty | `NotEnabled()` | Unchanged; state error before caller | Unmapped |
| BLSEIZ-DISABLE-L03 | ADMIN_ROLE holder | true | true | false | true | Core inactive | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Unmapped |
| BLSEIZ-DISABLE-L04 | ADMIN_ROLE holder | false | true | false | true | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Unmapped |
| BLSEIZ-DISABLE-L05 | ADMIN_ROLE holder | true | true | true | true | Seize inactive | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Unmapped |
| BLSEIZ-DISABLE-L06 | ADMIN_ROLE holder | false | true | true | true | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Only local pause/timestamp/events change; no dependency validation on disable | Unmapped |
| BLSEIZ-DISABLE-L07 | ADMIN_ROLE holder | true | true | true | true | other dependencies ready | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |
| BLSEIZ-DISABLE-L08 | ADMIN_ROLE holder | false | true | true | true | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |
| BLSEIZ-DISABLE-L09 | ADMIN_ROLE holder | true | true | true | false | other dependencies ready | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |
| BLSEIZ-DISABLE-L10 | ADMIN_ROLE holder | false | true | true | false | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |
| BLSEIZ-DISABLE-L11 | ADMIN_ROLE holder | true | true | false | false | other dependencies ready | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |
| BLSEIZ-DISABLE-L12 | ADMIN_ROLE holder | false | true | false | false | Kernel-activated and enabled, then Kernel-deactivated; cached ROLES retained; data=0x | `Success` | Local transition and exact events; canonical positions and balances preserved | Unmapped |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes | `BurnerLoans_InvalidEnablerData()` | Unmapped |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Unmapped |
| BLSEIZ-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Unmapped |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-DISABLE-L13 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Unmapped; fresh deployment, no dependency configuration |

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

Retired duplicate caller IDs: BLSEIZ-DISABLE-A02, BLSEIZ-DISABLE-I02. Retained families include both exclusive classes and overlap seeds; test mappings stay Partial until their full combined domain is proved.
