# RevenueDistributor.disable scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: inherited disable action and co-located isEnabled/lastTransitionAt assertions.

Default: the acting policy is Kernel-active. The Kernel-inactive case snapshots after deactivation, which leaves the previously cached ROLES module available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Normalized scenario scope: `RD-DISABLE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `IRevenueDistributor.RevenueDistributor_InvalidData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders with guaranteed seeds. Unauthorized fuzzing excludes every holder of either role. The inherited action does not check the policy's Kernel-active state. A freshly deployed, never-activated policy is already disabled, so `disable` reverts with `NotEnabled()` before attempting authorization through its unset ROLES dependency.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=false and lastTransitionAt to the uint48 timestamp; emits Disabled plus Transition(caller,false,data,timestamp). Preserve existing configuration/debt/custody and queued actions. Successful disable uses empty data; nonempty data must revert.

## Authorization

| ID | Caller | Inputs / competing fault | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-DISABLE-P02 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Enabled; empty disable data; own policy active | disable succeeds | Disable and timestamp/events; no payout or queue cancellation | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-A03 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Enabled; exclude all Admin and Emergency identities; call disable | NotAuthorised() | Unchanged | Covered: [test][test_givenEnabled_whenCallerLacksPauseRoles_reverts], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-L08 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Enabled policy is deactivated after dependency configuration | disable succeeds | Disable; cached dependencies and configuration remain unchanged | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |

## Lifecycle

ROLES initialized; retained caller roles after any Kernel deactivation; unrelated state and balances unchanged. All rows use data=0x except the dedicated payload cases.

| ID | Caller | Local active | Local enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | true | true | Success; disable does not require own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-L03 | Fuzz all callers | true | false | NotEnabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-L04 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | false | true | Success; disable does not require own Kernel membership | Only local enabled/timestamp changes; exact lifecycle events; configuration, payouts and balances preserved | Covered: [test][test_givenEnabled_whenAuthorizedCallerPauses], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-L06 | Fuzz all callers | false | false | NotEnabled() before authorization | Unchanged; no committed logs | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |

## Payload rejection and error precedence

Local enabled=true; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlapping role holders; seed each | Fuzz bytes of length 1..256; seed 0x00, 0x01, 32-byte ABI zero, 256 bytes | `IRevenueDistributor.RevenueDistributor_InvalidData()` | Unchanged; no committed logs | Covered: [test][test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-I03 | Fuzz all callers | Nonempty bytes; local enabled=false | `NotEnabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenDisabled_whenAnyCallerPauses_reverts], [test][test_givenPauseBoundarySeeds] |
| RD-DISABLE-I04 | Fuzz callers excluding every ADMIN_ROLE and EMERGENCY_ROLE holder | Nonempty bytes; local enabled=true | `NotAuthorised()` | Unchanged; authorization rejects before data | Covered: [test][test_givenEnabled_whenCallerLacksPauseRoles_reverts], [test][test_givenPauseBoundarySeeds] |

## Additional existing test evidence

- [test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization][test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization] — existing regression evidence; review generators and assertions before mapping the expanded cases.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD-DISABLE-L07 | Fuzz all callers | false | false | 0 | 0 | `NotEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts] |

## Current focused implementation evidence

The product hooks now enforce empty lifecycle payloads, inactive-disable availability and active enable/reEnable (where supported). [Function-specific lifecycle tests](disable.t.sol) exercise ADMIN transitions and nonempty fuzz inputs against real fixtures. This is partial coverage: emergency/secondary-role transitions, all dependency drifts, exact events and overflow drivers remain independently mapped. Local enable/reEnable rejection tests now follow the activity requirement; remaining role, accounting and boundary gaps are recorded in the mappings.

Retired duplicate caller IDs: RD-DISABLE-P03, RD-DISABLE-L09, RD-DISABLE-L02, RD-DISABLE-L05, RD-DISABLE-I02. Retained caller families include explicit exclusive-role and overlapping-role seeds.

Dependency classification: ROLES and TRSRY are Kernel modules. The config operator is an authority identity. Settlement delivers ERC-20 tokens directly; activation does not recursively inspect optional recipient or vault lifecycle. Candidate selection and route validation own their compatibility checks.

[test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts]: ./disable.t.sol#L146

[test_givenEnabled_whenAuthorizedCallerPauses]: ./disable.t.sol#L248

[test_givenPauseBoundarySeeds]: ./disable.t.sol#L279

[test_givenEnabled_whenCallerLacksPauseRoles_reverts]: ./disable.t.sol#L186

[test_givenDisabled_whenAnyCallerPauses_reverts]: ./disable.t.sol#L156

[test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts]: ./disable.t.sol#L216

[test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization]: ./disable.t.sol#L39
