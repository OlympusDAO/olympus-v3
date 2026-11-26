# BurnerLoansConfig.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansConfig.sol#L96). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: FLOAN,ROLES major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-DEPENDENCIES-I01 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); BurnerLoans_InvalidModuleVersion | Covered: [test][test_givenFLOANMissing_whenDependenciesConfigured_reverts], [test][test_givenFLOANMajorUnsupported_whenDependenciesConfigured_reverts], [test][test_givenROLESMissing_whenDependenciesConfigured_reverts], [test][test_givenROLESMajorUnsupported_whenDependenciesConfigured_reverts] |

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test][test_whenDependenciesConfigured], [test][test_givenCompatibleReplacement_whenDependenciesConfigured], [test][test_givenCompatibleRolesReplacement_whenConfigured] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenDependenciesConfigured]: ./configureDependencies.t.sol#L20
[test_givenFLOANMissing_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L32
[test_givenFLOANMajorUnsupported_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L46
[test_givenROLESMissing_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L62
[test_givenROLESMajorUnsupported_whenDependenciesConfigured_reverts]: ./configureDependencies.t.sol#L76
[test_givenCompatibleReplacement_whenDependenciesConfigured]: ./configureDependencies.t.sol#L92
[test_givenCompatibleRolesReplacement_whenConfigured]: ./configureDependencies.t.sol#L111
