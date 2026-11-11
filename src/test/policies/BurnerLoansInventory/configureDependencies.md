# BurnerLoansInventory.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansInventory.sol#L120). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: MINTR,ROLES,TRSRY major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Invalid inputs

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-DEPENDENCIES-I01 | Fuzz all callers | Required module absent; unsupported major where checked | Policy_ModuleDoesNotExist(keycode); BurnerLoansInventory_InvalidModuleVersion | Covered: [test_givenMissingModule_whenAnyCallerConfigures_reverts][test_givenMissingModule_whenAnyCallerConfigures_reverts]; [test_givenUnsupportedMajor_whenAnyCallerConfigures_reverts][test_givenUnsupportedMajor_whenAnyCallerConfigures_reverts]; [test_whenDependencyBoundarySeeds][test_whenDependencyBoundarySeeds] |

## Configuration transitions

| ID | Caller | Prior configuration / update | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | ROLES getter current; no enable/grant changes | Covered: [test_givenLifecycle_whenAnyCallerConfigures][test_givenLifecycle_whenAnyCallerConfigures]; [test_givenNeverConfigured_whenAnyCallerConfigures][test_givenNeverConfigured_whenAnyCallerConfigures]; [test_givenReplacementModule_whenAnyCallerConfigures][test_givenReplacementModule_whenAnyCallerConfigures]; [test_givenMintrUpgrade_reconcilesReplacementApproval][test_givenMintrUpgrade_reconcilesReplacementApproval] |
| BLINV-DEPENDENCIES-P02 | Fuzz all callers | Initial/replacement MINTR wrongOHM | InvalidOhm(expected,actual) | No approval/pointer partialchanges | Covered: [test_givenWrongOhm_whenAnyCallerConfigures_reverts][test_givenWrongOhm_whenAnyCallerConfigures_reverts]; [test_givenInitialMintrWithDifferentOhm_reverts][test_givenInitialMintrWithDifferentOhm_reverts]; [test_givenReplacementMintrWithDifferentOhm_revertsWithoutStateChange][test_givenReplacementMintrWithDifferentOhm_revertsWithoutStateChange] |

## Successful execution

Fixed for this table: Accounting / events: Currentdesired allowance reconciled; caught restorationfailure records deficit.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-DEPENDENCIES-P03 | Fuzz all callers | MINTR upgrade with activeprincipal/providers/default deficits; old/new burnallowances | Revoke old burnallowance, newMAX256; restore bounded approval on replacement | Covered: [test_givenReplacementModule_whenAnyCallerConfigures][test_givenReplacementModule_whenAnyCallerConfigures]; [test_givenMintrUpgradeAfterDefault_reconcilesReplacementApproval][test_givenMintrUpgradeAfterDefault_reconcilesReplacementApproval]; [test_givenReplacementApprovalRestorationFails_whenUpgraded_succeeds][test_givenReplacementApprovalRestorationFails_whenUpgraded_succeeds]; [test_givenBurnAllowanceUpdateFails_whenUpgraded_reverts][test_givenBurnAllowanceUpdateFails_whenUpgraded_reverts] |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule. Inventory approves tokens and MINTR, so dependency callbacks/reverts need explicit rollback assertions; it is not a pure read.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenBurnAllowanceUpdateFails_whenUpgraded_reverts]: configureDependencies.t.sol#L285
[test_givenInitialMintrWithDifferentOhm_reverts]: configureDependencies.t.sol#L86
[test_givenLifecycle_whenAnyCallerConfigures]: configureDependencies.t.sol#L171
[test_givenMintrUpgradeAfterDefault_reconcilesReplacementApproval]: configureDependencies.t.sol#L61
[test_givenMintrUpgrade_reconcilesReplacementApproval]: configureDependencies.t.sol#L39
[test_givenMissingModule_whenAnyCallerConfigures_reverts]: configureDependencies.t.sol#L190
[test_givenNeverConfigured_whenAnyCallerConfigures]: configureDependencies.t.sol#L326
[test_givenReplacementApprovalRestorationFails_whenUpgraded_succeeds]: configureDependencies.t.sol#L245
[test_givenReplacementMintrWithDifferentOhm_revertsWithoutStateChange]: configureDependencies.t.sol#L114
[test_givenReplacementModule_whenAnyCallerConfigures]: configureDependencies.t.sol#L342
[test_givenUnsupportedMajor_whenAnyCallerConfigures_reverts]: configureDependencies.t.sol#L210
[test_givenWrongOhm_whenAnyCallerConfigures_reverts]: configureDependencies.t.sol#L229
[test_whenDependencyBoundarySeeds]: configureDependencies.t.sol#L316
