# BurnerLoansPayout.supportsInterface coverage plan

Scenario scope: `BLCU-ERC165` identifies this contract/function.

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansPayout.sol#L287). Coverage is recorded in the Test column. Apply [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md).

Interface and version discovery are permissionless and independent of local activity/enablement. Constructor default-state getters remain in constructor.md. The duplicate constructor interface group is covered by the individual interface cases below.

The planned standalone IBurnerLoansCoreBound generalizes the existing core-only IBurnerLoansCoreBound name; its ERC165 ID is unchanged. Advertise the shared binding from the concrete contract without making service interfaces inherit it. No new base contract is required.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-ERC165-P01 | Fuzz all callers | type(IBurnerLoansPayout).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P02 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | No state, token, event or dependency changes | Partial: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet]; identical core() selector-ID support proved under the former interface name; concrete shared-interface declaration remains to be updated |
| BLCU-ERC165-P03 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P04 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P05 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P06 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, IVersioned, IEnabler, IEnablerV2, IConfigOperator, IReEnabler, IGracePeriod, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |

- [x] Review expectations before production test implementation.
- [x] Adapt existing Framework/recovery tests and map passing proofs.

## Shared mixin interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-ERC165-P07 | Fuzz all callers | type(IVersioned).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P08 | Fuzz all callers | type(IEnabler).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P09 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P10 | Fuzz all callers | type(IConfigOperator).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P11 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |
| BLCU-ERC165-P12 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state/dependency changes | Covered: [test_whenInterfacesRead_thenExactAdvertisedSet][test_whenInterfacesRead_thenExactAdvertisedSet] |

## Version

The version-read scenario retains its ID after moving from the constructor plan.

| ID | Caller | Read | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CONSTRUCTOR-V01 | Fuzz all callers | VERSION() | Named major=1,minor=0 | No state changes | Covered: [test_whenVersionRead_thenConstant][test_whenVersionRead_thenConstant] |

[test_whenInterfacesRead_thenExactAdvertisedSet]: ./supportsInterface.t.sol#L23
[test_whenVersionRead_thenConstant]: ./VERSION.t.sol#L9
