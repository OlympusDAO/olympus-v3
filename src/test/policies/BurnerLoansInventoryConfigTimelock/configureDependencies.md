# BurnerLoansInventoryConfigTimelock.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L84).

## Scope and fixtures

Permissionless framework hook, usable before activation and after migration. Resolves ROLES through this policy's current Kernel; Inventory and Core readiness are irrelevant. A failure rolls back the cached module assignment and emits no committed logs.

## Framework behavior

Framework hook resolves ROLES without ordinary action admission.

| ID | Caller | Setup | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-DEPS-P01 | Fuzz all callers | Installed ROLES v1 | Return [ROLES] | Cache module; no queue/funds changes | Covered: [test][test_whenDependenciesConfigured_thenExactRolesCache]; [test][test_givenKernelMigration_whenConfigured_thenFreshRolesResolved] |
| BLINCT-DEPS-I01 | Fuzz all callers | ROLES absent | Policy_ModuleDoesNotExist(ROLES) | No partial cache | Covered: [test][test_givenRolesAbsent_whenConfigured_reverts] |
| BLINCT-DEPS-I02 | Fuzz all callers | Unsupported ROLES major | BurnerLoans_InvalidModuleVersion() | No partial cache | Covered: [test][test_givenUnsupportedRolesVersion_whenConfigured_reverts] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_whenDependenciesConfigured_thenExactRolesCache]: ./configureDependencies.t.sol#L20
[test_givenKernelMigration_whenConfigured_thenFreshRolesResolved]: ./configureDependencies.t.sol#L88
[test_givenRolesAbsent_whenConfigured_reverts]: ./configureDependencies.t.sol#L46
[test_givenUnsupportedRolesVersion_whenConfigured_reverts]: ./configureDependencies.t.sol#L64
