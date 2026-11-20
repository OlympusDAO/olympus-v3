# BurnerLoansInventoryConfigTimelock.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L428).

## Scope and fixtures

Pure version query. TL denotes this timelock. No caller role, local-state, Inventory or Core readiness check applies.

For each query, vary local activity and enablement independently and guarantee all four pairs. Stub Inventory reads to revert to prove these queries do not consume its services.

## Framework behavior

Pure interface version query.

| ID | Caller | Setup | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-VERSION-P01 | Fuzz all callers | Any local/target lifecycle | Return (1,0) | No reads/writes | Covered: [test][test_whenVersionRead_thenConstant]; [test][test_givenEachLifecyclePair_whenRead_thenIndependent] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_whenVersionRead_thenConstant]: ./VERSION.t.sol#L13
[test_givenEachLifecyclePair_whenRead_thenIndependent]: ./VERSION.t.sol#L42
