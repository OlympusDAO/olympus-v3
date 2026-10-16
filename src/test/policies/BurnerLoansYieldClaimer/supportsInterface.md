# BurnerLoansYieldClaimer.supportsInterface coverage plan

Scope: ERC-165 support across the claimer's direct and inherited interfaces.

The result is independent of caller, lifecycle state, Kernel activity, and configuration.

## Scenarios

| ID | Interface identifier | Expected result | Test |
| --- | --- | --- | --- |
| BLYC-ERC165-P01 | Each of `IERC165`, `IEnabler`, `IEnablerV2`, `IReEnabler`, `IGracePeriod`, `IPeriodicTask`, `IVersioned`, and `IBurnerLoansYieldClaimer` | `true` | Covered: [test][test_givenSupportedInterfaces_returnsTrue] |
| BLYC-ERC165-P02 | ERC-165 invalid sentinel `0xffffffff` | `false` | Covered: [test][test_givenUnsupportedInterface_returnsFalse] |
| BLYC-ERC165-P03 | Arbitrary unrelated identifier other than the sentinel and supported set | `false` | Covered: [test][test_givenUnrelatedInterface_returnsFalse] |

[test_givenSupportedInterfaces_returnsTrue]: ./supportsInterface.t.sol#L20
[test_givenUnsupportedInterface_returnsFalse]: ./supportsInterface.t.sol#L35
[test_givenUnrelatedInterface_returnsFalse]: ./supportsInterface.t.sol#L40
