# PriceCache.constructor coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-CONSTRUCTOR`.

Deployer is permissionless. Constructor takes the Kernel, unit-of-account decimals
(uint8, full 0..MAX8 valid), and a symbol whose byte length must be 1..32. Module binding
and initial unit metadata registration happen in configureDependencies, not construction.
Assumption for symbol round trips: every accepted 1..32-byte string retains its exact bytes,
including embedded NUL.
Initial lifecycle is disabled, lastTransitionAt=0, configurable grace=7 days.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CONSTRUCTOR-I01 | Deployer | N/A | N/A | Empty symbol | PriceCache_InvalidAssetSymbol() | Covered: [test][test_whenConstructorSymbolIsEmpty_reverts] |
| PCACHE-CONSTRUCTOR-I02 | Deployer | N/A | N/A | 33-byte symbol | PriceCache_InvalidAssetSymbol() | Covered: [test][test_whenConstructorSymbolExceedsMaximumLength_reverts] |
| PCACHE-CONSTRUCTOR-I03 | Deployer | N/A | false | Kernel=0 | Inherited KernelAdapter stores zero Kernel; policy remains disabled and unconfigured | Covered: [test][test_whenKernelIsZero_constructorStoresZero] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CONSTRUCTOR-N01 | Deployer | Not installed | false | Unit decimals 0,1,MAX8 | All accepted and round-trip exactly | Covered: [test][test_whenConstructorDecimalBoundarySeeds] |
| PCACHE-CONSTRUCTOR-N02 | Deployer | Not installed | false | 32-byte symbol | Whole symbol survives registration/getter | Covered: [test][test_whenConstructorSymbolHasMaximumLength_returnsEntireSymbol] |
| PCACHE-CONSTRUCTOR-N03 | Fuzz deployers | Not installed | false | Fuzz valid symbol bytes lengths 1..32; include embedded NUL | Exact opaque-byte round trip | Covered: [test][test_whenConstructorSymbolContainsArbitraryBytes] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CONSTRUCTOR-P01 | Fuzz deployers | Not installed | false | Any deployer; fuzz uint8 unit decimals | Exact Kernel, disabled/history/grace; unit metadata after installation | Covered: [test][test_whenAnyDeployerConstructs] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_whenConstructorSymbolIsEmpty_reverts]: constructor.t.sol#L69
[test_whenConstructorSymbolExceedsMaximumLength_reverts]: constructor.t.sol#L75
[test_whenKernelIsZero_constructorStoresZero]: constructor.t.sol#L58
[test_whenConstructorDecimalBoundarySeeds]: constructor.t.sol#L35
[test_whenConstructorSymbolHasMaximumLength_returnsEntireSymbol]: constructor.t.sol#L81
[test_whenConstructorSymbolContainsArbitraryBytes]: constructor.t.sol#L42
[test_whenAnyDeployerConstructs]: constructor.t.sol#L14
