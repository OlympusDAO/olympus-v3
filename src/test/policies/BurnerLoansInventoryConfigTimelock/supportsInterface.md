# BurnerLoansInventoryConfigTimelock.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L435).

## Scope and fixtures

Permissionless interface query. No Inventory or Core reads, caller roles or local-state admission. The concrete implementation and its inherited bases determine the advertised IDs.

For each query, vary local activity and enablement independently and guarantee all four pairs. Stub Inventory reads to revert to prove these queries do not consume its services.

## Interface IDs

All queries are independent of lifecycle and perform no target reads. Derive inherited IDs from actual base implementations.

| ID | Caller | ID | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-ERC165-P01 | Fuzz all callers | IBurnerLoansInventoryConfigTimelock | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P02 | Fuzz all callers | IVersioned | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P03 | Fuzz all callers | IERC165 | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P04 | Fuzz all callers | IEnabler | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P05 | Fuzz all callers | IEnablerV2 | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P06 | Fuzz all callers | IReEnabler | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P07 | Fuzz all callers | IGracePeriod | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P08 | Fuzz all callers | ITimelockBatchQueue | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-P09 | Fuzz all callers | IConfigTimelockBatchQueue | true | No mutation/dependency reads | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-I01 | Fuzz all callers | 0xffffffff | false | No mutation | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |
| BLINCT-ERC165-I02 | Fuzz all callers | Fuzz IDs outside the advertised set | false | No mutation | Covered: [test][test_whenInterfacesRead_thenOnlyAdvertisedSet]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_whenInterfacesRead_thenOnlyAdvertisedSet]: ./supportsInterface.t.sol#L26
[test_givenEachLifecyclePair_whenRead_thenIndependent]: ./supportsInterface.t.sol#L72
