# BurnerLoansRisk.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansRisk.sol#L92).

## Domains and notation

Scenario scope: `BLRISK-CONSTRUCTOR`. Deploy Risk as a Kernel Policy using explicit Kernel, OHM, backing oracle, optional price cache, uint48 maxAge and a nonzero immutable Core identity. The identity does not introduce a Core service or lifecycle dependency. Risk can be deployed before the bound address has code. Core checks Risk's reported Kernel and immutable Core binding when selecting it through `setRisk`. Risk starts locally disabled; activation resolves ROLES, PRICE and FLOAN before enablement.

All failed deployments commit no contract or logs. No constructor call refreshes prices or reads FLOAN markets. maxAge=0 is accepted. A nonzero cache must support IPriceCache, IEnabler and IVersioned and report the supplied Kernel; its active/enabled flags do not gate construction because PRICE is the fallback.

## Dependency compatibility and invalid inputs

All unvaried dependencies are valid. Each fault is isolated. The backing oracle must advertise IVersioned. The cache must advertise IPriceCache, IEnabler and IVersioned and report the supplied Kernel; no numeric cache version is queried. Failed or malformed OHM decimal reads use InvalidOhm.

| ID | Caller | Dependency | Fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-I09 | Fuzz deployer | OHM | Zero | BurnerLoansRisk_InvalidOhm(0) | No deployment or logs | Covered: [test][test_whenZeroOhm_reverts] |
| BLRISK-CONSTRUCTOR-I10 | Fuzz deployer | OHM | Nonzero EOA | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs | Covered: [test][test_whenEoaOhm_reverts] |
| BLRISK-CONSTRUCTOR-I11 | Fuzz deployer | OHM | Fuzz decimals 37..MAX8; seed 37,MAX8 | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs | Covered: [test][test_whenOhmPrecisionIsUnsupported_reverts], [test][test_whenOhmPrecisionBoundaries_reverts] |
| BLRISK-CONSTRUCTOR-P02 | Fuzz deployer | OHM | decimals() reverts | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs | Covered: [test][test_whenOhmDecimalsRevert_reverts] |
| BLRISK-CONSTRUCTOR-I12 | Fuzz deployer | OHM | decimals() returns fewer than 32 bytes; fuzz lengths 0..31; seed 0,1,31 | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs | Covered: [test][test_whenOhmDecimalsResponseIsShort_reverts], [test][test_whenOhmDecimalsResponseBoundaries_reverts] |
| BLRISK-CONSTRUCTOR-I13 | Fuzz deployer | OHM | decimals() returns a noncanonical uint8 word; fuzz 256..MAX256; seed 256,MAX256 | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs | Covered: [test][test_whenOhmDecimalsResponseIsNoncanonical_reverts], [test][test_whenOhmDecimalsWordBoundaries_reverts] |
| BLRISK-CONSTRUCTOR-I03 | Fuzz deployer | Backing oracle | Zero | BurnerLoans_InvalidBackingOracle(0) | No deployment or logs | Covered: [test][test_whenZeroOracle_reverts] |
| BLRISK-CONSTRUCTOR-I04 | Fuzz deployer | Backing oracle | Nonzero EOA | BurnerLoans_InvalidBackingOracle(oracle) | No deployment or logs | Covered: [test][test_whenEoaOracle_reverts] |
| BLRISK-CONSTRUCTOR-I05 | Fuzz deployer | Backing oracle | Deployed, does not support IOlympusBackingOracle | BurnerLoans_InvalidBackingOracle(oracle) | No deployment or logs | Covered: [test][test_whenMissingOracleInterface_reverts] |
| BLRISK-CONSTRUCTOR-D01 | Fuzz deployer | Backing oracle | ERC165 call reverts | BurnerLoans_InvalidBackingOracle(oracle) | No deployment or logs | Covered: [test][test_whenRevertingOracleERC165_reverts] |
| BLRISK-CONSTRUCTOR-D04 | Fuzz deployer | Backing oracle | ERC165 returns malformed data | BurnerLoans_InvalidBackingOracle(oracle) | No deployment or logs | Covered: [test][test_whenMalformedOracleERC165_reverts] |
| BLRISK-CONSTRUCTOR-D12 | Fuzz deployer | Backing oracle | Nonzero deployed oracle supports IOlympusBackingOracle but not IVersioned | BurnerLoans_InvalidBackingOracle(oracle) | No deployment or logs | Covered: [test][test_whenUnversionedOracle_reverts] |
| BLRISK-CONSTRUCTOR-I07 | Fuzz deployer | Price cache | Nonzero deployed cache lacks IPriceCache | BurnerLoans_InvalidPriceCache(cache) | No deployment or logs | Covered: [test][test_whenMissingCacheInterface_reverts] |
| BLRISK-CONSTRUCTOR-D02 | Fuzz deployer | Price cache | Nonzero deployed cache supports IPriceCache but lacks IEnabler | BurnerLoans_InvalidPriceCache(cache) | No deployment or logs | Covered: [test][test_whenMissingCacheEnabler_reverts] |
| BLRISK-CONSTRUCTOR-D03 | Fuzz deployer | Price cache | Nonzero, required interfaces valid, reports another Kernel | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | No deployment or logs | Covered: [test][test_whenCacheKernelDiffers_reverts] |
| BLRISK-CONSTRUCTOR-I14 | Fuzz deployer | Core identity | Zero | BurnerLoans_ZeroAddress() | No deployment or logs | Covered: [test][test_whenCoreBindingIsZero_reverts] |
| BLRISK-CONSTRUCTOR-I15 | Fuzz deployer | OHM | Oversized decimals response; fuzz lengths 33..MAX16; seed 33,64,MAX16 | BurnerLoansRisk_InvalidOhm(OHM) | No deployment or logs; return-data copy bounded to 33 bytes | Covered: [test][test_whenOhmDecimalsResponseIsOversized_reverts], [test][test_whenOhmDecimalsOversizedResponseBoundaries_reverts] |

## Successful deployment and numeric bounds

Assert core(), ohm(), kernel(), configOperator()==0, isEnabled()==false, lastTransitionAt()==0 and exact oracle/cache/age bindings. The nonzero Core identity is preserved without requiring Core code or readiness. No roles, approvals, funds or snapshot updates are created.

Every successful deployment emits `BackingOracleSet`, `PriceCacheSet` and `PriceCacheMaxAgeSet`, including zero cache and zero age values. Both identity getters, `core()` and `ohm()`, return addresses.

| ID | Caller | Cache | maxAge | OHM decimals | Expected result | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-P05 | Fuzz deployer | Valid nonzero same-Kernel cache | 1 | 9 | Success; exact OHM, Kernel, oracle, cache and age bindings | Covered: [test][test_whenNoCoreIsDeployed] |
| BLRISK-CONSTRUCTOR-I06 | Fuzz deployer | Zero | 1 | 9 | Success; direct PRICE mode | Covered: [test][test_whenNoCache] |
| BLRISK-CONSTRUCTOR-I08 | Fuzz deployer | Valid nonzero cache | 0 | 9 | Success; zero cache age stored | Covered: [test][test_whenZeroAge] |
| BLRISK-CONSTRUCTOR-N01 | Fuzz deployer | Valid nonzero cache | Fuzz 1..MAX48; seed 1,MAX48 | 9 | Success; exact age stored | Covered: [test][test_whenCacheAgeIsPositive], [test][test_whenCacheAgeEndpoints] |
| BLRISK-CONSTRUCTOR-N02 | Fuzz deployer | Zero | 0 | Fuzz 0..36; seed 0,1,9,36 | Success; exact OHM precision used by later calculations | Covered: [test][test_whenOhmDecimalsAreSupported], [test][test_whenOhmPrecisionEndpoints] |
| BLRISK-CONSTRUCTOR-P07 | Fuzz deployer | Fuzz zero/nonzero | Fuzz 0..MAX48; seed 0,MAX48 | 9 | Exact binding events and stored values, including default-valued bindings | Covered: [test][test_whenDeployed_thenPricingBindingsEmitEvents], [test][test_whenInitialPricingBindingsUseBoundaryValues_thenEventsEmit] |

## Cache interface compatibility

The numeric cache-version requirement P03 is retired. Cache admission follows the consumed interfaces and Kernel binding.

| ID | Caller | Cache compatibility | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-P06 | Fuzz deployer | Required IPriceCache/IEnabler/IVersioned interfaces and matching Kernel; VERSION() reverts | Success; exact constructor bindings; no version read | Covered: [test][test_givenVersionGetterReverts_whenDeployed] |

## Core independence

Core installation requires the immutable system identity. P04 proves that deployment does not query that identity or require an operational Core; calculations continue to use OHM and canonical FLOAN markets directly. Retired service-readiness scenarios D16, D17 and L05 remain retired.

| ID | Caller | Deployment context | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-P04 | Fuzz deployer | No Core deployed | Success; exact constructor state and nonzero identity without Core calls | Covered: [test][test_whenNoCoreIsDeployed] |

## Optional cache lifecycle independence

| ID | Caller | Cache active | Cache enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CONSTRUCTOR-L01 | Fuzz deployer | true | false | Success | Binding only; no operational cache call | Covered: [test][test_givenCache10_whenDeployed] |
| BLRISK-CONSTRUCTOR-L02 | Fuzz deployer | false | true | Success | Binding only; no operational cache call | Covered: [test][test_givenCache01_whenDeployed] |
| BLRISK-CONSTRUCTOR-L03 | Fuzz deployer | false | false | Success | Binding only; no operational cache call | Covered: [test][test_givenCache00_whenDeployed] |
| BLRISK-CONSTRUCTOR-L04 | Fuzz deployer | true | true | Success | Binding only; no operational cache call | Covered: [test][test_givenCache11_whenDeployed] |

Module installation and compatibility scenarios live in [configureDependencies](configureDependencies.md). Empty module-write permissions are covered in [requestPermissions](requestPermissions.md).

Interface/version discovery scenarios live in [supportsInterface](supportsInterface.md).

- [x] Review these expectations.
- [x] Complete focused tests and mappings.

[test_givenCache00_whenDeployed]: constructor.t.sol#L477
[test_givenCache01_whenDeployed]: constructor.t.sol#L461
[test_givenCache10_whenDeployed]: constructor.t.sol#L445
[test_givenCache11_whenDeployed]: constructor.t.sol#L493
[test_givenVersionGetterReverts_whenDeployed]: constructor.t.sol#L293
[test_whenCacheAgeEndpoints]: constructor.t.sol#L387
[test_whenCacheAgeIsPositive]: constructor.t.sol#L376
[test_whenCacheKernelDiffers_reverts]: constructor.t.sol#L275
[test_whenEoaOhm_reverts]: constructor.t.sol#L121
[test_whenEoaOracle_reverts]: constructor.t.sol#L181
[test_whenMalformedOracleERC165_reverts]: constructor.t.sol#L219
[test_whenMissingCacheEnabler_reverts]: constructor.t.sol#L263
[test_whenMissingCacheInterface_reverts]: constructor.t.sol#L251
[test_whenMissingOracleInterface_reverts]: constructor.t.sol#L192
[test_whenNoCache]: constructor.t.sol#L356
[test_whenNoCoreIsDeployed]: constructor.t.sol#L345
[test_whenOhmDecimalsAreSupported]: constructor.t.sol#L432
[test_whenOhmDecimalsResponseBoundaries_reverts]: constructor.t.sol#L324
[test_whenOhmDecimalsResponseIsNoncanonical_reverts]: constructor.t.sol#L331
[test_whenOhmDecimalsResponseIsShort_reverts]: constructor.t.sol#L319
[test_whenOhmDecimalsRevert_reverts]: constructor.t.sol#L154
[test_whenOhmDecimalsWordBoundaries_reverts]: constructor.t.sol#L339
[test_whenOhmPrecisionBoundaries_reverts]: constructor.t.sol#L148
[test_whenOhmPrecisionEndpoints]: constructor.t.sol#L437
[test_whenOhmPrecisionIsUnsupported_reverts]: constructor.t.sol#L143
[test_whenRevertingOracleERC165_reverts]: constructor.t.sol#L203
[test_whenUnversionedOracle_reverts]: constructor.t.sol#L235
[test_whenZeroAge]: constructor.t.sol#L366
[test_whenZeroOhm_reverts]: constructor.t.sol#L113
[test_whenZeroOracle_reverts]: constructor.t.sol#L170
[test_whenCoreBindingIsZero_reverts]: constructor.t.sol#L99

[test_whenDeployed_thenPricingBindingsEmitEvents]: constructor.t.sol#L26

[test_whenInitialPricingBindingsUseBoundaryValues_thenEventsEmit]: constructor.t.sol#L47

[test_whenOhmDecimalsResponseIsOversized_reverts]: constructor.t.sol#L53

[test_whenOhmDecimalsOversizedResponseBoundaries_reverts]: constructor.t.sol#L62
