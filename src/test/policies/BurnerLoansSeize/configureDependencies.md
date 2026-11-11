# BurnerLoansSeize.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L128). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope: `BLLIQ-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: ROLES; no version validation in BaseBurnerLoansAction.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test_whenDependenciesConfigured_thenRolesIsResolved][test_whenDependenciesConfigured_thenRolesIsResolved], [test_givenFreshAction_whenConfigured_thenInitialCacheResolved][test_givenFreshAction_whenConfigured_thenInitialCacheResolved], [test_givenReplacementRoles_whenConfigured_thenCacheRefreshed][test_givenReplacementRoles_whenConfigured_thenCacheRefreshed] |

## Successful execution

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-DEPENDENCIES-P02 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); No version rejection implemented | Covered: [test_givenRolesMissing_whenConfigured_reverts][test_givenRolesMissing_whenConfigured_reverts] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenFreshAction_whenConfigured_thenInitialCacheResolved]: configureDependencies.t.sol#L57
[test_givenReplacementRoles_whenConfigured_thenCacheRefreshed]: configureDependencies.t.sol#L71
[test_givenRolesMissing_whenConfigured_reverts]: configureDependencies.t.sol#L39
[test_whenDependenciesConfigured_thenRolesIsResolved]: configureDependencies.t.sol#L16
