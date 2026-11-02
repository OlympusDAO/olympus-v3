# PriceCache.setGracePeriod coverage plan

Scope: `PCACHE-GRACE`. This is the shared ReEnablerGracePeriod setter. ADMIN may configure
seconds as uint32, valid range 1..MAX32. The product wrapper checks own Kernel activity before inherited local enablement,
caller authorization and numeric validation.
Equal valid values emit GracePeriodSet once. The setter preserves enablement, transition
timestamp, configuration, custody, cache/task state and queued obligations; tests prove that
only the grace-period storage slot is written. No tokens move.

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GRACE-P01 | Fuzz ADMIN holders | true | true | Fuzz 1..MAX32; seed 1,MAX32 | Store exact value; one exact GracePeriodSet event | Covered: [test][test_whenAdminSetsGrace], [test][test_whenGraceBoundarySeeds] |
| PCACHE-GRACE-P02 | ADMIN | true | true | Same stored valid value, fuzz 1..MAX32 | Success; still emit GracePeriodSet | Covered: [test][test_whenGraceUnchanged] |
| PCACHE-GRACE-A01 | Fuzz callers excluding every ADMIN | true | true | 1 | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCallerSetsGrace_reverts] |
| PCACHE-GRACE-I01 | ADMIN | true | true | 0 | GracePeriod_ZeroPeriod() | Covered: [test][test_whenGraceIsZero_reverts] |
| PCACHE-GRACE-L01 | Fuzz all callers | true | false | Fuzz uint32 including zero/MAX32 | NotEnabled() before authorization/zero validation | Covered: [test][test_givenDisabled_whenAnyCallerSetsGrace_reverts] |
| PCACHE-GRACE-L02 | ADMIN | false | true | MAX32 | PriceCache_PolicyNotActive() before local state, caller or input checks | Covered: [test][test_givenInactive_whenAdminSetsGrace] |

## Competing faults

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GRACE-L03 | Fuzz all callers | false | false | Fuzz uint32 | PriceCache_PolicyNotActive() before local enablement and authorization | Covered: [test][test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts] |
| PCACHE-GRACE-L04 | Fuzz all callers | false | false, never configured | Fuzz uint32 | PriceCache_PolicyNotActive() without reaching ROLES | Covered: [test][test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts] |
| PCACHE-GRACE-I02 | Fuzz callers excluding every ADMIN | true | true | 0 | ROLES_RequireRole(ADMIN_ROLE) before zero validation | Covered: [test][test_whenUnauthorizedCallerSetsZero_reverts] |

[test_whenAdminSetsGrace]: setGracePeriod.t.sol#L19
[test_whenGraceBoundarySeeds]: setGracePeriod.t.sol#L27
[test_whenGraceUnchanged]: setGracePeriod.t.sol#L33
[test_whenUnauthorizedCallerSetsGrace_reverts]: setGracePeriod.t.sol#L40
[test_whenGraceIsZero_reverts]: setGracePeriod.t.sol#L50
[test_givenDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L59
[test_givenInactive_whenAdminSetsGrace]: setGracePeriod.t.sol#L71
[test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L80
[test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L92
[test_whenUnauthorizedCallerSetsZero_reverts]: setGracePeriod.t.sol#L105
