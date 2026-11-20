# BurnerLoansCollateral.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansCollateral.sol#L165). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

The planned standalone IBurnerLoansCoreBound generalizes the existing core-only IBurnerLoansCoreBound name; its ERC165 ID is unchanged. Advertise the shared binding from the concrete contract without making service interfaces inherit it. No new base contract is required.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-ERC165-P01 | Fuzz all callers | type(IBurnerLoansCollateral).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable][test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable], [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P02 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenCoreBindingInterfaceQueried_thenExactAbiIdSupported][test_whenCoreBindingInterfaceQueried_thenExactAbiIdSupported], [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable]; exact core() ABI ID proved independently of the production interface name |
| BLCOL-ERC165-P03 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P04 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P05 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P06 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P07 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P08 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P09 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P10 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |
| BLCOL-ERC165-P11 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesQueried_thenOnlyAdvertisedSet][test_whenInterfacesQueried_thenOnlyAdvertisedSet], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |

## Shared assertions

Use the exact ABI IDs listed above. The shared-binding test derives the ID from core() while the production declaration retains its former name. Imported interfaces do not add advertised support.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable]: changeKernel.t.sol#L59
[test_whenCoreBindingInterfaceQueried_thenExactAbiIdSupported]: supportsInterface.t.sol#L22
[test_whenInterfacesQueried_thenOnlyAdvertisedSet]: supportsInterface.t.sol#L44
[test_whenReadAcrossAllLifecycleStates_thenStable]: supportsInterface.t.sol#L79
