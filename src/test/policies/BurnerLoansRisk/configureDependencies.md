# BurnerLoansRisk.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansRisk.sol#L137).

## Domains and notation

Permissionless framework hook used by Kernel activation and module upgrades. Resolve ROLES v1, PRICE v2 and FLOAN v1 in that order; require a representable PRICE decimal scale. Local activity and enablement do not gate this hook. Existing `BLRISK-CONSTRUCTOR` IDs are retained when moving these cases from the constructor plan.

Each fault is isolated; earlier dependencies are valid. A failed call commits no dependency changes. Numeric maxima: MAX8=255. Supported PRICE decimals are 0..77; 10**78 does not fit uint256.

## Module resolution and compatibility

| ID | Caller | Module state | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-D05 | Fuzz all callers | Installed ROLES v1, PRICE v2, FLOAN v1 | configureDependencies returns exactly these three keycodes and resolves their module addresses | No authority grants, tokens or pricing writes | Covered: [test][test_whenModuleBindingsAreValid] |
| BLRISK-CONSTRUCTOR-D06 | Fuzz all callers | ROLES missing | Policy_ModuleDoesNotExist(ROLES) | No committed dependency setup | Covered: [test][test_givenMissingROLES_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D07 | Fuzz all callers | PRICE missing; ROLES valid | Policy_ModuleDoesNotExist(PRICE) | No committed dependency setup | Covered: [test][test_givenMissingPRICE_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D08 | Fuzz all callers | FLOAN missing; earlier modules valid | Policy_ModuleDoesNotExist(FLOAN) | No committed dependency setup | Covered: [test][test_givenMissingFLOAN_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D09 | Fuzz all callers | ROLES major incompatible; others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatibleROLES_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D10 | Fuzz all callers | PRICE major incompatible; others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatiblePRICE_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D11 | Fuzz all callers | FLOAN major incompatible; others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatibleFLOAN_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D13 | Fuzz all callers | Compatible modules; PRICE decimals fuzzed in 78..MAX8; explicit seeds 78,MAX8 | LoanMath_UnsupportedDecimals(decimals) | No committed dependency setup | Covered: [test][test_whenPriceDecimalsAreUnsupported_reverts], [test][test_whenPriceDecimalsAre78_reverts], [test][test_whenPriceDecimalsAreMaximum_reverts] |
| BLRISK-CONSTRUCTOR-D14 | Fuzz all callers | Compatible modules; PRICE decimals fuzzed in 0..77; explicit seeds 0,77 | configureDependencies returns ROLES,PRICE,FLOAN in that order | No authority grants, tokens or pricing writes | Covered: [test][test_whenPriceDecimalsAreSupported], [test][test_whenPriceDecimalsAreZero], [test][test_whenPriceDecimalsAre77] |
| BLRISK-CONSTRUCTOR-D15 | Kernel executor | Previously activated then deactivated Risk; PRICE decimals=78 | LoanMath_UnsupportedDecimals(78) on activation | Risk remains inactive; local enabled flag unchanged | Covered: [test][test_givenUnsupportedPriceDecimals_whenRiskActivated_reverts] |

- [x] Review module resolution and compatibility expectations.
- [x] Map focused tests and deterministic decimal boundaries.

[test_givenIncompatibleFLOAN_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L181

[test_givenIncompatiblePRICE_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L148

[test_givenIncompatibleROLES_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L115

[test_givenMissingFLOAN_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L167

[test_givenMissingPRICE_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L134

[test_givenMissingROLES_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L101

[test_givenUnsupportedPriceDecimals_whenRiskActivated_reverts]: configureDependencies.t.sol#L68

[test_whenModuleBindingsAreValid]: configureDependencies.t.sol#L200

[test_whenPriceDecimalsAre77]: configureDependencies.t.sol#L62

[test_whenPriceDecimalsAre78_reverts]: configureDependencies.t.sol#L25

[test_whenPriceDecimalsAreMaximum_reverts]: configureDependencies.t.sol#L35

[test_whenPriceDecimalsAreSupported]: configureDependencies.t.sol#L45

[test_whenPriceDecimalsAreUnsupported_reverts]: configureDependencies.t.sol#L13

[test_whenPriceDecimalsAreZero]: configureDependencies.t.sol#L56
