# DepositManager.setGracePeriod coverage plan

Scope: `DM-GRACE`. This is the shared ReEnablerGracePeriod setter. ADMIN may configure
seconds as uint32, valid range 1..MAX32. The product wrapper checks own Kernel activity before inherited local enablement,
caller authorization and numeric validation.
Equal valid values emit GracePeriodSet once. The setter preserves enablement, transition
timestamp, configuration, custody, cache/task state and queued obligations; tests prove that
only the grace-period storage slot is written. No tokens move.

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-GRACE-P01 | Fuzz ADMIN holders | true | true | Fuzz 1..MAX32; seed 1,MAX32 | Store exact value; one exact GracePeriodSet event | Covered: [test][test_whenAdminSetsGrace], [test][test_whenGraceBoundarySeeds] |
| DM-GRACE-P02 | ADMIN | true | true | Same stored valid value, fuzz 1..MAX32 | Success; still emit GracePeriodSet | Covered: [test][test_whenGraceBoundarySeeds], [test][test_whenGraceUnchanged] |
| DM-GRACE-A01 | Fuzz callers excluding every ADMIN | true | true | 1 | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCallerSetsGrace_reverts], [test][test_whenUnauthorizedCallerSeedsSetGrace_reverts] |
| DM-GRACE-I01 | ADMIN | true | true | 0 | GracePeriod_ZeroPeriod() | Covered: [test][test_whenGraceIsZero_reverts] |
| DM-GRACE-L01 | Fuzz all callers | true | false | Fuzz uint32 including zero/MAX32 | NotEnabled() before authorization/zero validation | Covered: [test][test_givenDisabled_whenAnyCallerSetsGrace_reverts], [test][test_givenDisabled_whenGraceBoundarySeeds_reverts] |
| DM-GRACE-L02 | ADMIN | false | true | MAX32 | DepositManager_PolicyInactive() before local state, caller or input checks | Covered: [test][test_givenInactive_whenAdminSetsGrace] |

## Competing faults

| ID | Caller | Local active | Local enabled | Input | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| DM-GRACE-L03 | Fuzz all callers | false | false | Fuzz uint32 | DepositManager_PolicyInactive() before local enablement and authorization | Covered: [test][test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts], [test][test_givenInactiveDisabled_whenGraceBoundarySeeds_reverts] |
| DM-GRACE-L04 | Fuzz all callers | false | false, never configured | Fuzz uint32 | DepositManager_PolicyInactive() without reaching ROLES | Covered: [test][test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts], [test][test_givenNeverConfigured_whenGraceBoundarySeeds_reverts] |
| DM-GRACE-I02 | Fuzz callers excluding every ADMIN | true | true | 0 | ROLES_RequireRole(ADMIN_ROLE) before zero validation | Covered: [test][test_whenUnauthorizedCallerSetsZero_reverts], [test][test_whenUnauthorizedCallerSeedsSetGrace_reverts] |

[test_whenAdminSetsGrace]: setGracePeriod.t.sol#L18
[test_whenGraceBoundarySeeds]: setGracePeriod.t.sol#L26
[test_whenGraceUnchanged]: setGracePeriod.t.sol#L34
[test_whenUnauthorizedCallerSetsGrace_reverts]: setGracePeriod.t.sol#L41
[test_whenUnauthorizedCallerSeedsSetGrace_reverts]: setGracePeriod.t.sol#L116
[test_whenGraceIsZero_reverts]: setGracePeriod.t.sol#L51
[test_givenDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L60
[test_givenDisabled_whenGraceBoundarySeeds_reverts]: setGracePeriod.t.sol#L128
[test_givenInactive_whenAdminSetsGrace]: setGracePeriod.t.sol#L72
[test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L81
[test_givenInactiveDisabled_whenGraceBoundarySeeds_reverts]: setGracePeriod.t.sol#L133
[test_givenNeverConfigured_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L93
[test_givenNeverConfigured_whenGraceBoundarySeeds_reverts]: setGracePeriod.t.sol#L142
[test_whenUnauthorizedCallerSetsZero_reverts]: setGracePeriod.t.sol#L106
