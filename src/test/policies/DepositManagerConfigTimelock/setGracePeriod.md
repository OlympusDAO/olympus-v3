# DepositManagerConfigTimelock.setGracePeriod coverage plan

The concrete setter requires own Kernel activity before inherited local enablement, ADMIN authorization and nonzero-period validation. Same valid periods retain the inherited single-event behavior and do not alter lifecycle history.

Scope: `DMCT-GRACE`. This is the shared ReEnablerGracePeriod setter. ADMIN may configure
seconds as uint32, valid range 1..MAX32. It deliberately follows the inherited enabled-state
and authorization checks; cached ROLES permits configuration while Kernel-inactive.
Equal valid values emit GracePeriodSet once. The setter preserves enablement, transition
timestamp, configuration, custody, cache/task state and queued obligations; tests prove that
only the grace-period storage slot is written. No tokens move.

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DMCT-GRACE-P01 | Fuzz ADMIN holders | true | true | Fuzz 1..MAX32; seed 1,MAX32 | Store exact value; one exact GracePeriodSet event | Covered: [test][test_whenAdminSetsGrace], [test][test_whenGraceBoundarySeeds] |
| DMCT-GRACE-P02 | ADMIN | true | true | Same stored valid value, fuzz 1..MAX32 | Success; still emit GracePeriodSet | Covered: [test][test_whenGraceUnchanged] |
| DMCT-GRACE-A01 | Fuzz callers excluding every ADMIN | true | true | 1 | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCallerSetsGrace_reverts] |
| DMCT-GRACE-I01 | ADMIN | true | true | 0 | GracePeriod_ZeroPeriod() | Covered: [test][test_whenGraceIsZero_reverts] |
| DMCT-GRACE-L01 | Fuzz all callers | true | false | Fuzz uint32 including zero/MAX32 | NotEnabled() before authorization/zero validation | Covered: [test][test_givenDisabled_whenAnyCallerSetsGrace_reverts] |
| DMCT-GRACE-L02 | ADMIN | false | true | MAX32 | DepositManagerConfigTimelock_PolicyInactive(TL); queue, custody and lifecycle unchanged | Covered: [test][test_givenInactive_whenAdminSetsGrace_reverts] |

## Competing faults

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DMCT-GRACE-L03 | Fuzz all callers | false | false | Fuzz uint32 | DepositManagerConfigTimelock_PolicyInactive(TL); queue, custody and lifecycle unchanged | Covered: [test][test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts] |
| DMCT-GRACE-L04 | Fuzz all callers | false | false, never configured | Fuzz uint32 | DepositManagerConfigTimelock_PolicyInactive(TL); queue, custody and lifecycle unchanged | Covered: [test][test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts] |
| DMCT-GRACE-I02 | Fuzz callers excluding every ADMIN | true | true | 0 | ROLES_RequireRole(ADMIN_ROLE) before zero validation | Covered: [test][test_whenUnauthorizedCallerSetsZero_reverts] |

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-GRACE-L05 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; fuzz full uint32 period | DepositManagerConfigTimelock_PolicyInactive(TL) | Period, enabled flag, transition timestamp and preserved state unchanged | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts] |

[test_whenAdminSetsGrace]: ./setGracePeriod.t.sol#L21
[test_whenGraceBoundarySeeds]: ./setGracePeriod.t.sol#L29
[test_whenGraceUnchanged]: ./setGracePeriod.t.sol#L35
[test_whenUnauthorizedCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L42
[test_whenGraceIsZero_reverts]: ./setGracePeriod.t.sol#L52
[test_givenDisabled_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L61
[test_givenInactive_whenAdminSetsGrace_reverts]: ./setGracePeriod.t.sol#L73
[test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L85
[test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L100
[test_whenUnauthorizedCallerSetsZero_reverts]: ./setGracePeriod.t.sol#L116
[test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L126
