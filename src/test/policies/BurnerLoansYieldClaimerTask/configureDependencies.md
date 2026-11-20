# BurnerLoansYieldClaimerTask.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L113). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: ROLES major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles], [test][test_whenRolesUpgraded_refreshesCompatibleReplacement], [test][test_givenNeverActivated_whenDependenciesConfigured] |

## Successful execution

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-DEPENDENCIES-P02 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); Policy_WrongModuleVersion(abi.encode([1])) | Covered: [test][test_whenRolesMissing_reverts], [test][test_whenRolesMajorUnsupported_reverts] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenNeverActivated_whenDependenciesConfigured]: configureDependencies.t.sol#L113
[test_whenCalledInAnyLifecycleState_refreshesRoles]: configureDependencies.t.sol#L14
[test_whenRolesMajorUnsupported_reverts]: configureDependencies.t.sol#L77
[test_whenRolesMissing_reverts]: configureDependencies.t.sol#L60
[test_whenRolesUpgraded_refreshesCompatibleReplacement]: configureDependencies.t.sol#L42
