# RevenueDistributorTask.disable scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: inherited disable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Normalized scenario scope: `RDTASK-DISABLE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Required behavior: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with proposed `IRevenueDistributorTask.RevenueDistributorTask_InvalidData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders with guaranteed seeds. Unauthorized fuzzing excludes every holder of either role.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=false and lastTransitionAt to the uint48 timestamp; emits Disabled plus Transition(caller,false,data,timestamp). Preserve existing configuration/debt/custody and queued actions. Successful disable uses empty data; nonempty data must revert.

## Authorization

| ID | Caller | Inputs / competing fault | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-DISABLE-P02 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Enabled; empty disable data; own policy active | disable succeeds | Disable and timestamp/events; no payout or queue cancellation | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-A03 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Enabled; exclude all Admin and Emergency identities; call disable | NotAuthorised() | Unchanged | Covered: [test][test_givenEnabled_whenCallerLacksPauseRoles_reverts], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-L08 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Enabled task is deactivated after dependency configuration; empty disable data | disable succeeds | Disable and timestamp/events; cached dependencies, gas settings, cursor and balances remain unchanged | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | true | true | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-L03 | Fuzz all callers | true | false | NotEnabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-L04 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | false | true | Success; concrete activation requires own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-L06 | Fuzz all callers | false | false | NotEnabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Fuzz bytes of length 1..256; seed 0x00, 0x01, 32-byte ABI zero, 256 bytes | `IRevenueDistributorTask.RevenueDistributorTask_InvalidData()` | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |
| RDTASK-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Covered: [test][test_givenEnabled_whenCallerLacksPauseRoles_reverts], [test][test_givenPauseBoundarySeeds] |

## Additional existing test evidence

- [test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization][test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-DISABLE-L07 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts] |

Retired duplicate caller IDs: RDTASK-DISABLE-P03, RDTASK-DISABLE-L09, RDTASK-DISABLE-L02, RDTASK-DISABLE-L05, RDTASK-DISABLE-I02. Retained caller families include explicit exclusive-role and overlapping-role seeds.

## Dependency independence

| ID | Caller | Local active | Local enabled | Distributor metadata | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-DISABLE-D01 | Emergency | Fuzz false/true | true | Wrong Kernel; status getter reverts | Success with empty payload; no target probes | Preserve all payout accounting | Covered: [test][test_givenBrokenDistributor_whenEmergencyPauses_succeeds] |

[test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts]: ./disable.t.sol#L130

[test_givenBrokenDistributor_whenEmergencyPauses_succeeds]: ./disable.t.sol#L144

[test_givenEnabled_whenAuthorizedCallerPauses]: ./disable.t.sol#L242

[test_givenPauseBoundarySeeds]: ./disable.t.sol#L273

[test_givenEnabled_whenCallerLacksPauseRoles_reverts]: ./disable.t.sol#L188

[test_givenDisabled_whenAnyCallerPauses_reverts]: ./disable.t.sol#L162

[test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts]: ./disable.t.sol#L214

[test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization]: ./disable.t.sol#L48
