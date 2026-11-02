# BurnerLoansRisk.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansRisk.sol#L161).

## Domains and notation

Permissionless pure framework hook. Risk requests no module write permissions. Active/enabled, active/disabled, inactive/enabled and inactive/disabled states all return the same result. The existing scenario ID is retained from the constructor plan.

| ID | Caller | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-V09 | Fuzz all callers | requestPermissions returns an empty array | No external dependency reads or writes | Covered: [test][test_givenOperational_whenPermissionsRequested], [test][test_givenDisabled_whenPermissionsRequested], [test][test_givenInactive_whenPermissionsRequested], [test][test_givenInactiveAndDisabled_whenPermissionsRequested] |

- [x] Map the four independent local lifecycle states.

[test_givenDisabled_whenPermissionsRequested]: requestPermissions.t.sol#L17

[test_givenInactiveAndDisabled_whenPermissionsRequested]: requestPermissions.t.sol#L31

[test_givenInactive_whenPermissionsRequested]: requestPermissions.t.sol#L24

[test_givenOperational_whenPermissionsRequested]: requestPermissions.t.sol#L10
