# BurnerLoansDebt.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansDebt.sol#L172). Implemented and mapped to the focused Foundry suite.

## Domains and notation

Scenario scope: `BLDEBT-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

The planned standalone IBurnerLoansCoreBound generalizes the existing core-only IBurnerLoansCoreBound name; its ERC165 ID is unchanged. Advertise the shared binding from the concrete contract without making service interfaces inherit it. No new base contract is required.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-ERC165-P01 | Fuzz all callers | type(IBurnerLoansDebt).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfaceQueried_thenMergedDebtIsAdvertised](extend.t.sol#L511), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P02 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | No state, token, event or dependency changes | Partial: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23); identical core() selector-ID support proved under the former interface name; concrete shared-interface declaration remains to be updated |
| BLDEBT-ERC165-P03 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P04 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P05 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P06 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P07 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P08 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P09 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P10 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |
| BLDEBT-ERC165-P11 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenReadAcrossAllLifecycleStates_thenStable](supportsInterface.t.sol#L58), [test_whenInterfacesQueried_thenOnlyAdvertisedSet](supportsInterface.t.sol#L23) |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.
