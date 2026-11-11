# BurnerLoansRisk.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansRisk.sol#L142).

## Domains and notation

Permissionless framework hook used by Kernel activation and module upgrades. Resolve ROLES v1, PRICE major 2 or exact version (1,2), and FLOAN v1 in that order; require a representable PRICE decimal scale. Local activity and enablement do not gate this hook. Existing `BLRISK-CONSTRUCTOR` IDs are retained when moving these cases from the constructor plan.

Each fault is isolated; earlier dependencies are valid. A failed call commits no dependency changes. Numeric maxima: MAX8=255. Supported PRICE decimals are 0..77; 10**78 does not fit uint256.

## Module resolution and compatibility

| ID | Caller | Module state | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-D05 | Fuzz all callers | Installed ROLES v1, PRICE v2, FLOAN v1 | configureDependencies returns exactly these three keycodes and resolves their module addresses | No authority grants, tokens or pricing writes | Covered: [test][test_whenModuleBindingsAreValid] |
| BLRISK-CONSTRUCTOR-D06 | Fuzz all callers | ROLES missing | Policy_ModuleDoesNotExist(ROLES) | No committed dependency setup | Covered: [test][test_givenMissingROLES_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D07 | Fuzz all callers | PRICE missing; ROLES valid | Policy_ModuleDoesNotExist(PRICE) | No committed dependency setup | Covered: [test][test_givenMissingPRICE_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D08 | Fuzz all callers | FLOAN missing; earlier modules valid | Policy_ModuleDoesNotExist(FLOAN) | No committed dependency setup | Covered: [test][test_givenMissingFLOAN_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D09 | Fuzz all callers | ROLES major incompatible; others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatibleROLES_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D10 | Fuzz all callers | PRICE version neither major 2 nor exact (1,2); others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatiblePRICE_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D11 | Fuzz all callers | FLOAN major incompatible; others valid | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenIncompatibleFLOAN_whenDependenciesConfigured_reverts] |
| BLRISK-CONSTRUCTOR-D13 | Fuzz all callers | Compatible modules; PRICE decimals fuzzed in 78..MAX8; explicit seeds 78,MAX8 | LoanMath_UnsupportedDecimals(decimals) | No committed dependency setup | Covered: [test][test_whenPriceDecimalsAreUnsupported_reverts], [test][test_whenPriceDecimalsAre78_reverts], [test][test_whenPriceDecimalsAreMaximum_reverts] |
| BLRISK-CONSTRUCTOR-D14 | Fuzz all callers | Compatible modules; PRICE decimals fuzzed in 0..77; explicit seeds 0,77 | configureDependencies returns ROLES,PRICE,FLOAN in that order | No authority grants, tokens or pricing writes | Covered: [test][test_whenPriceDecimalsAreSupported], [test][test_whenPriceDecimalsAreZero], [test][test_whenPriceDecimalsAre77] |
| BLRISK-CONSTRUCTOR-D15 | Kernel executor | Previously activated then deactivated Risk; PRICE decimals=78 | LoanMath_UnsupportedDecimals(78) on activation | Risk remains inactive; local enabled flag unchanged | Covered: [test][test_givenUnsupportedPriceDecimals_whenRiskActivated_reverts] |
| BLRISK-CONSTRUCTOR-D16 | Kernel executor | Real OlympusPricev1_2 replaces PRICE via UpgradeModule while Risk is active/enabled | Upgrade and dependency refresh succeed without VERSION mocking; actual decimals and installed module identity match | No authority grants or token movements | Covered: [test][test_givenPriceV1_2_whenModuleUpgraded] |
| BLRISK-CONSTRUCTOR-D17 | Fuzz all callers | PRICE major 2 with fuzzed minor 0..MAX8 and explicit MAX8 | Dependencies resolve successfully | No authority grants or token movements | Covered: [test][test_givenPriceMajorTwo_whenDependenciesConfigured], [test][test_givenPriceMajorTwoMaximumMinor_whenDependenciesConfigured] |
| BLRISK-CONSTRUCTOR-D18 | Permissionless framework caller | PRICE (1,0), (1,1), (1,3) and (MAX8,MAX8) | Policy_WrongModuleVersion(abi.encode([1,2,1])) | No committed dependency setup | Covered: [test][test_givenPriceV1_0_whenDependenciesConfigured_reverts], [test][test_givenPriceV1_1_whenDependenciesConfigured_reverts], [test][test_givenPriceV1_3_whenDependenciesConfigured_reverts], [test][test_givenPriceMaximumVersion_whenDependenciesConfigured_reverts] |

- [x] Review module resolution and compatibility expectations.
- [x] Map focused tests and deterministic decimal boundaries.

[test_givenIncompatibleFLOAN_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L293

[test_givenIncompatiblePRICE_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L170

[test_givenIncompatibleROLES_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L130

[test_givenMissingFLOAN_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L274

[test_givenMissingPRICE_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L151

[test_givenMissingROLES_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L111

[test_givenUnsupportedPriceDecimals_whenRiskActivated_reverts]: configureDependencies.t.sol#L78

[test_whenModuleBindingsAreValid]: configureDependencies.t.sol#L314

[test_whenPriceDecimalsAre77]: configureDependencies.t.sol#L72

[test_whenPriceDecimalsAre78_reverts]: configureDependencies.t.sol#L31

[test_whenPriceDecimalsAreMaximum_reverts]: configureDependencies.t.sol#L43

[test_whenPriceDecimalsAreSupported]: configureDependencies.t.sol#L55

[test_whenPriceDecimalsAreUnsupported_reverts]: configureDependencies.t.sol#L17

[test_whenPriceDecimalsAreZero]: configureDependencies.t.sol#L66

[test_givenPriceV1_2_whenModuleUpgraded]: configureDependencies.t.sol#L191

[test_givenPriceMajorTwo_whenDependenciesConfigured]: configureDependencies.t.sol#L216

[test_givenPriceMajorTwoMaximumMinor_whenDependenciesConfigured]: configureDependencies.t.sol#L230

[test_givenPriceV1_0_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L240

[test_givenPriceV1_1_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L245

[test_givenPriceV1_3_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L250

[test_givenPriceMaximumVersion_whenDependenciesConfigured_reverts]: configureDependencies.t.sol#L255
