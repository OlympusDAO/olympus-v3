# BurnerLoansYieldClaimer.configureDependencies coverage plan

Scope: permissionless ROLES dependency discovery and refresh.

The call has no own-policy activity or local-enablement gate. It resolves the current Kernel's
`ROLES` module, requires major version 1, stores that address, and returns `[ROLES]`. Unchanged means
the target, lifecycle state, gas settings, cursor, and prior dependency cache retain their values.

## Scenarios

| ID | Caller | Task Kernel activity | Task local state | ROLES module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-DEPS-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Installed, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles] |
| BLYC-DEPS-P02 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Compatible replacement, major 1 with different minor | Success | Cache changes to replacement; other state unchanged | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement] |
| BLYC-DEPS-I01 | Any caller, fuzz | Any | Any | Missing | `Policy_ModuleDoesNotExist(ROLES)` | Atomic rollback | Covered: [test][test_whenRolesMissing_reverts] |
| BLYC-DEPS-I02 | Any caller, fuzz | Any | Any | Installed, major not 1 | `Policy_WrongModuleVersion(abi.encode([1]))` | Atomic rollback | Covered: [test][test_whenRolesMajorUnsupported_reverts] |

[test_whenCalledInAnyLifecycleState_refreshesRoles]: ./configureDependencies.t.sol#L14
[test_whenRolesUpgraded_refreshesCompatibleReplacement]: ./configureDependencies.t.sol#L42
[test_whenRolesMissing_reverts]: ./configureDependencies.t.sol#L60
[test_whenRolesMajorUnsupported_reverts]: ./configureDependencies.t.sol#L77
