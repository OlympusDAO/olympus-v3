# RevenueDistributor.configureDependencies scenario plan

Scope: dependency discovery and refresh. The function is callable by any caller regardless of the policy's Kernel-active or local enabled state.

## Scenarios

| ID | Caller | RD Kernel | RD local | ROLES module | TRSRY module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD-DEPS-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Present, major 1 | Present, major 1 | Returns `[ROLES, TRSRY]` in order | Both cached module addresses refresh; other state and balances unchanged | Covered: [evidence][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys] |
| RD-DEPS-P02 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Present, compatible | Present, compatible; replace either module | Success | Only the selected module address changes | Covered: [evidence][test_whenCompatibleModuleReplaced_refreshesSelectedDependency] |
| RD-DEPS-I01 | Any caller, fuzz | Any | Any | Missing | Any | Policy_ModuleDoesNotExist(ROLES) | Atomic rollback | Covered: [evidence][test_givenMissingRoles_whenDependenciesConfigured_reverts] |
| RD-DEPS-I02 | Any caller, fuzz | Any | Any | Present, compatible | Missing | Policy_ModuleDoesNotExist(TRSRY) | Atomic rollback | Covered: [evidence][test_givenMissingTreasury_whenDependenciesConfigured_reverts] |
| RD-DEPS-I03 | Any caller, fuzz | Any | Any | Present, major not 1 | Present | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [ROLES branch][test_givenWrongModuleMajor_whenDependenciesConfigured_reverts] |
| RD-DEPS-I04 | Any caller, fuzz | Any | Any | Present, major 1 | Present, major not 1 | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [TRSRY branch][test_givenWrongModuleMajor_whenDependenciesConfigured_reverts] |

[test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys]: ./configureDependencies.t.sol#L14
[test_whenCompatibleModuleReplaced_refreshesSelectedDependency]: ./configureDependencies.t.sol#L40
[test_givenMissingRoles_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L62
[test_givenMissingTreasury_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L73
[test_givenWrongModuleMajor_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L86
