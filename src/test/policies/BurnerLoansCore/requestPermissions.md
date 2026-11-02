# BurnerLoansCore.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansCore.sol#L159). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: FLOAN addCollateral,removeCollateral,increaseDebt,createPosition,decreaseDebt,extendMaturity,defaultPosition,setMarketManager.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test][test_whenPermissionsRequested], [test][test_givenFreshAndMigratedCore_whenPermissionsRequested] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_givenFreshAndMigratedCore_whenPermissionsRequested]: requestPermissions.t.sol#L38
[test_whenPermissionsRequested]: requestPermissions.t.sol#L16
