# RevenueDistributorTask.configureDependencies scenario plan

Scope: permissionless ROLES dependency discovery and refresh in every policy lifecycle state.

## Scenarios

| ID | Caller | Task Kernel | Task local | ROLES module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-DEPS-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles] |
| RDTASK-DEPS-P02 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement] |
| RDTASK-DEPS-I01 | Any caller, fuzz | Any | Any | Missing | Policy_ModuleDoesNotExist(ROLES) | Atomic rollback | Covered: [test][test_whenRolesMissing_reverts] |
| RDTASK-DEPS-I02 | Any caller, fuzz | Any | Any | Present, major not 1 | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [test][test_whenRolesMajorUnsupported_reverts] |

[test_whenCalledInAnyLifecycleState_refreshesRoles]: ./configureDependencies.t.sol#L13
[test_whenRolesUpgraded_refreshesCompatibleReplacement]: ./configureDependencies.t.sol#L40
[test_whenRolesMissing_reverts]: ./configureDependencies.t.sol#L53
[test_whenRolesMajorUnsupported_reverts]: ./configureDependencies.t.sol#L70
