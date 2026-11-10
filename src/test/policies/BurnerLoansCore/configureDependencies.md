# BurnerLoansCore.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansCore.sol#L147). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: FLOAN,ROLES major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-DEPENDENCIES-I01 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); BurnerLoans_InvalidModuleVersion | Covered: [test][test_givenFLOANMissing_whenConfigured_reverts], [test][test_givenFLOANMajorUnsupported_whenConfigured_reverts], [test][test_givenROLESMissing_whenConfigured_reverts], [test][test_givenROLESMajorUnsupported_whenConfigured_reverts] |

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Covered: [test][test_whenDependenciesRefreshed], [test][test_givenModuleUpgrade_whenConfigured] |

## Successful execution

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-DEPENDENCIES-P02 | Authorized callback | Core guard already entered | ReentrancyGuardReentrantCall before module refresh | Covered: [test][test_givenBusyCore_whenConfigured_reverts] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`, `floan`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_givenBusyCore_whenConfigured_reverts]: configureDependencies.t.sol#L107
[test_givenFLOANMajorUnsupported_whenConfigured_reverts]: configureDependencies.t.sol#L47
[test_givenFLOANMissing_whenConfigured_reverts]: configureDependencies.t.sol#L31
[test_givenModuleUpgrade_whenConfigured]: configureDependencies.t.sol#L97
[test_givenROLESMajorUnsupported_whenConfigured_reverts]: configureDependencies.t.sol#L80
[test_givenROLESMissing_whenConfigured_reverts]: configureDependencies.t.sol#L64
[test_whenDependenciesRefreshed]: configureDependencies.t.sol#L17
