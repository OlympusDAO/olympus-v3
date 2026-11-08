# BurnerLoansInventoryConfigTimelock.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L95).

## Scope and fixtures

Permissionless framework hook. Returns no module-write requests; it grants no roles or token approvals. Local and Inventory lifecycle do not gate it.

For each query, vary local activity and enablement independently and guarantee all four pairs. Stub Inventory reads to revert to prove these queries do not consume its services.

## Framework behavior

No module-write permissions are requested.

| ID | Caller | Setup | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-PERMS-P01 | Fuzz all callers | Any local/target lifecycle | Return empty Permissions[] | No token approvals or queue changes | Covered: [test][test_whenPermissionsRead_thenEmpty]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_whenPermissionsRead_thenEmpty]: ./requestPermissions.t.sol#L16
[test_givenEachLifecyclePair_whenRead_thenIndependent]: ./requestPermissions.t.sol#L44
