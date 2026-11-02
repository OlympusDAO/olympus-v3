# BurnerLoansLens.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansLens.sol#L287).

Scenario IDs retain their original `BLLENS-CONSTRUCTOR-V` identifiers after moving these cases from the constructor plan. Lens is a plain helper without local lifecycle gates. All callers may query interface support.

## Interface discovery

Core views may revert after successful construction; interface discovery must not read Core or other dependencies.

| ID | Caller | interfaceId | Expected return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-CONSTRUCTOR-V01 | Fuzz all callers | type(IBurnerLoansLens).interfaceId | true | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenLensInterfaceQueried][test_givenCoreUnavailable_whenLensInterfaceQueried] |
| BLLENS-CONSTRUCTOR-V06 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenCoreBindingQueried][test_givenCoreUnavailable_whenCoreBindingQueried] |
| BLLENS-CONSTRUCTOR-V02 | Fuzz all callers | type(IERC165).interfaceId | true | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenERC165Queried][test_givenCoreUnavailable_whenERC165Queried] |
| BLLENS-CONSTRUCTOR-V03 | Fuzz all callers | 0xffffffff | false | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenInvalidInterfaceQueried][test_givenCoreUnavailable_whenInvalidInterfaceQueried] |
| BLLENS-CONSTRUCTOR-V05 | Fuzz all callers | type(IVersioned).interfaceId | true; VERSION() returns major=1,minor=0 | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenVersionedInterfaceQueried][test_givenCoreUnavailable_whenVersionedInterfaceQueried] |
| BLLENS-CONSTRUCTOR-V04 | Fuzz all callers | Fuzz bytes4 excluding all supported IDs and 0xffffffff; seed 0x00000000 | false | No dependency reads, writes or logs | Covered: [test_givenCoreUnavailable_whenUnsupportedInterfaceQueried][test_givenCoreUnavailable_whenUnsupportedInterfaceQueried]; [test_givenCoreUnavailable_whenZeroInterfaceQueried][test_givenCoreUnavailable_whenZeroInterfaceQueried] |

- [x] Review these expectations.
- [x] Implement focused tests and update Test mappings.

[test_givenCoreUnavailable_whenERC165Queried]: ./supportsInterface.t.sol#L45
[test_givenCoreUnavailable_whenInvalidInterfaceQueried]: ./supportsInterface.t.sol#L53
[test_givenCoreUnavailable_whenLensInterfaceQueried]: ./supportsInterface.t.sol#L23
[test_givenCoreUnavailable_whenUnsupportedInterfaceQueried]: ./supportsInterface.t.sol#L82
[test_givenCoreUnavailable_whenVersionedInterfaceQueried]: ./supportsInterface.t.sol#L64
[test_givenCoreUnavailable_whenZeroInterfaceQueried]: ./supportsInterface.t.sol#L97

[test_givenCoreUnavailable_whenCoreBindingQueried]: ./supportsInterface.t.sol#L34
