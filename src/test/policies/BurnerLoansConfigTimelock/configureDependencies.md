# BurnerLoansConfigTimelock.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L122). Coverage is recorded in the Test column.

Implementation: 2 scenario functions mapped; 2 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: ROLES major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-DEPENDENCIES-I01 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); BurnerLoansConfigTimelock_InvalidModuleVersion | Covered: [test_givenMissingOrUnsupportedRoles_whenDependenciesConfigured_reverts][test_givenMissingOrUnsupportedRoles_whenDependenciesConfigured_reverts] |

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test_givenCompatibleRoles_whenDependenciesRefreshed_thenExactKeyAndPointer][test_givenCompatibleRoles_whenDependenciesRefreshed_thenExactKeyAndPointer] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenMissingOrUnsupportedRoles_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L14
[test_givenCompatibleRoles_whenDependenciesRefreshed_thenExactKeyAndPointer]: configureDependencies.t.sol#L49
