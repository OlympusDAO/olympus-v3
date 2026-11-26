# BurnerLoansConfig.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansConfig.sol#L117). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: FLOAN createMarket,setMarketOriginationsEnabled,setMarketPrincipalCap,setMarketRiskConfig,setMarketBaseFee,setMarketConfigData.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test][test_whenPermissionsRequested], [test][test_givenFreshDeployment_whenPermissionsRequested], [test][test_givenKernelMigration_whenPermissionsRequested] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenPermissionsRequested]: ./requestPermissions.t.sol#L16
[test_givenFreshDeployment_whenPermissionsRequested]: ./requestPermissions.t.sol#L40
[test_givenKernelMigration_whenPermissionsRequested]: ./requestPermissions.t.sol#L46
