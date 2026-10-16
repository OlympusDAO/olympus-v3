# RevenueDistributorConfigTimelock.configureDependencies scenario plan

Scope: permissionless ROLES dependency discovery and refresh in every policy lifecycle state.

## Scenarios

| ID | Caller | RDT Kernel | RDT local | ROLES module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-DEPS-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [evidence][testFuzz_whenCalledInAnyLifecycleState_refreshesRoles] |
| RDCT-DEPS-P02 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [evidence][testFuzz_whenRolesUpgraded_refreshesCompatibleReplacement] |
| RDCT-DEPS-I01 | Any caller, fuzz | Any | Any | Missing | Policy_ModuleDoesNotExist(ROLES) | Atomic rollback | Covered: [evidence][testFuzz_whenRolesMissing_reverts] |
| RDCT-DEPS-I02 | Any caller, fuzz | Any | Any | Present, major not 1 | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [evidence][testFuzz_whenRolesMajorUnsupported_reverts] |

[testFuzz_whenCalledInAnyLifecycleState_refreshesRoles]: ./configureDependencies.t.sol
[testFuzz_whenRolesUpgraded_refreshesCompatibleReplacement]: ./configureDependencies.t.sol
[testFuzz_whenRolesMissing_reverts]: ./configureDependencies.t.sol
[testFuzz_whenRolesMajorUnsupported_reverts]: ./configureDependencies.t.sol
