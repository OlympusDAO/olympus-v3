# BurnerLoansRisk.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansRisk.sol#L721). Scenario scope: `BLRISK-ERC165`. Existing `BLRISK-CONSTRUCTOR` IDs moved from the constructor plan retain their original discovery behavior.

Version/interface discovery is permissionless in every independent local active/enabled state, without calling dependencies. VERSION returns named major=1,minor=0. Risk advertises standalone IConfigOperator. It exposes the immutable Core identity through standalone IBurnerLoansCoreBound; discovery makes no Core service calls.

## Interface and version discovery

| ID | Caller | Interface | Return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-V01 | Fuzz all callers | IBurnerLoansRisk | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V02 | Fuzz all callers | IVersioned | true; VERSION()=(1,0) | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V03 | Fuzz all callers | IEnabler | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V04 | Fuzz all callers | IEnablerV2 | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V05 | Fuzz all callers | IReEnabler | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V06 | Fuzz all callers | IGracePeriod | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V07 | Fuzz all callers | IERC165 | true | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V10 | Fuzz all callers | IConfigOperator | true; standalone interface advertised by concrete Risk | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |
| BLRISK-CONSTRUCTOR-V08 | Fuzz all callers | 0xffffffff; separately fuzz other bytes4 excluding supported IDs and 0xffffffff | false | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried], [test][test_whenInterfaceIsUnknown] |
| BLRISK-ERC165-P01 | Fuzz all callers | IBurnerLoansCoreBound | false | Covered: [test][test_givenOperational_whenInterfacesQueried], [test][test_givenDisabled_whenInterfacesQueried], [test][test_givenInactive_whenInterfacesQueried], [test][test_givenInactiveAndDisabled_whenInterfacesQueried], [test][test_givenReEnabled_whenInterfacesQueried] |

- [x] Implement focused interface/version tests.
- [x] Map each row to passing tests.

[test_givenDisabled_whenInterfacesQueried]: supportsInterface.t.sol#L52

[test_givenInactiveAndDisabled_whenInterfacesQueried]: supportsInterface.t.sol#L62

[test_givenInactive_whenInterfacesQueried]: supportsInterface.t.sol#L57

[test_givenOperational_whenInterfacesQueried]: supportsInterface.t.sol#L47

[test_givenReEnabled_whenInterfacesQueried]: supportsInterface.t.sol#L69

[test_whenInterfaceIsUnknown]: supportsInterface.t.sol#L74
