# BurnerLoansSeizerTask.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L122). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-DEPENDENCIES` identifies this contract/function.

Permissionless across every own/Core enabled/activity state. Expected ordered dependencies: ROLES major1.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Configuration transitions

Fixed for this table: Accounting / events: ROLES getter current; no enable/grant changes.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-DEPENDENCIES-P01 | Fuzz all callers | Installed compatible modules, first/repeated call, module replacement | Ordered keycodes and pointers refreshed | Unmapped |

## Dependency failures

Fixed for this table: Accounting / events: Entire call rollback, previous pointers intact.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-DEPENDENCIES-P02 | Fuzz all callers | ROLES keycode has no installed module | Policy_ModuleDoesNotExist(toKeycode("ROLES")); preserve previously cached ROLES and all lifecycle/accounting state | Unmapped |

## Shared assertions

No own-policy activity or ADMIN gate invented. Missing cached ROLES before setup is tested as actual ABI failure in role-dependent calls, not a proposed lifecycle rule.

Co-located API assertions: `ROLES`. These must be asserted independently of the action return value.

## Test organization

[configureDependencies.t.sol](./configureDependencies.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Version and dependency-read branches

Local activity and enablement vary independently; neither is an admission gate. All failures roll back the tentative ROLES assignment. Use selectors/abi.encodeCall for mocks and exact error assertions.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-DEPENDENCIES-I01 | Fuzz all callers | Installed ROLES major in 0..255 except1; seed0,2,255 | Policy_WrongModuleVersion(abi.encode([1])); previous pointer retained | Unmapped |
| BLSEIZ-DEPENDENCIES-P03 | Fuzz all callers | Major1, minor0..255; seed0,1,255; first and repeated resolution | Accept every minor; return exactly [ROLES]; cache installed module | Unmapped |
| BLSEIZ-DEPENDENCIES-T01 | Fuzz all callers | Installed module VERSION() reverts with a fixed custom error | Propagate exact dependency error; previous pointer retained | Unmapped |
| BLSEIZ-DEPENDENCIES-T02 | Fuzz all callers | VERSION returns short data or a noncanonical uint8 | ABI decode revert with empty data; previous pointer retained | Unmapped |
| BLSEIZ-DEPENDENCIES-T03 | Fuzz all callers | Kernel module lookup reverts with a fixed custom error | Propagate exact Kernel error before any pointer change | Unmapped |
