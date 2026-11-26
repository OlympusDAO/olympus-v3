# BurnerLoansInventory.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansInventory.sol#L503). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-ERC165-P01 | Fuzz all callers | type(IBurnerLoansInventory).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P02 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P03 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P04 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P05 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P06 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P07 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P11 | Fuzz all callers | type(IConfigOperator).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P12 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | No state, token, event or dependency changes; concrete contract implements the shared core() binding interface | Unmapped |
| BLINV-ERC165-P08 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P09 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |
| BLINV-ERC165-P10 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenUnknownInterfaceQueried][test_whenUnknownInterfaceQueried] |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [x] Review these expectations.
- [ ] Add shared Core-binding interface coverage.
- [ ] Complete the new interface coverage mapping.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenLifecycle_whenReadByAnyCaller]: supportsInterface.t.sol#L43
[test_whenReadLifecycleSeeds]: supportsInterface.t.sol#L80
[test_whenUnknownInterfaceQueried]: supportsInterface.t.sol#L62
