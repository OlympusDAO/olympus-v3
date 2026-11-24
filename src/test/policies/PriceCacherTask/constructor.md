# PriceCacherTask.constructor coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-CONSTRUCTOR`.

Construction validates cache compatibility and Kernel binding without requiring cache
readiness. The deployer is permissionless. Required interfaces are IPriceCache and IEnabler. Cache version discovery and numeric versions are not required. Initial state is
disabled, lastTransitionAt=0, grace=7 days, no configured pairs. The deployer supplies
both gas limits using the validation shared with [setGasLimits](setGasLimits.md).

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

Cache compatibility is defined by the consumed interfaces and Kernel binding.
The task must neither require IVersioned support nor call the cache VERSION getter.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-L01 | Fuzz deployers | Not installed | false | Compatible cache active/inactive independently of enabled/disabled | Construction accepts all four startup states; readiness belongs to activation | Covered: [test][test_givenCacheLifecycle_whenDeployed], [test][test_whenStartupLifecycleSeedsUsed] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-I01 | Deployer | N/A | N/A | Cache=0 | PriceCacherTask_ZeroAddress() | Covered: [test][test_whenPriceCacheIsZero_reverts] |
| PCACHER-CONSTRUCTOR-I02 | Deployer | N/A | N/A | Cache is nonzero EOA | PriceCacherTask_InvalidPriceCache(cache) | Covered: [test][test_whenPriceCacheIsNotContract_reverts] |
| PCACHER-CONSTRUCTOR-I03 | Deployer | N/A | N/A | Valid cache and zero pair limit for any execution limit | PriceCacherTask_InvalidGasLimits() | Covered: [test][test_whenPairGasLimitIsZero_reverts] |
| PCACHER-CONSTRUCTOR-I04 | Deployer | N/A | N/A | Valid cache and execution limit equal to the pair limit plus the cleanup reserve | PriceCacherTask_InvalidGasLimits() | Covered: [test][test_whenExecutionGasEqualsPairGasPlusReserve_reverts] |
| PCACHER-CONSTRUCTOR-I05 | Deployer | N/A | N/A | Invalid boundary limits, including execution gas zero and one, the first viable pair limit with insufficient execution gas, and the maximum `uint32` pair limit | PriceCacherTask_InvalidGasLimits() | Covered: [test][test_whenGasLimitsAreInvalid_revertsAtBoundaries] |
| PCACHER-CONSTRUCTOR-I06 | Deployer | N/A | N/A | Nonzero pair limit and execution limit from zero through the pair limit plus the cleanup reserve, bounded by the maximum `uint32` | PriceCacherTask_InvalidGasLimits() | Covered: [test][test_whenExecutionGasLeavesInsufficientGasForAPair_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-D01 | Deployer | N/A | N/A | Cache omits IEnabler | PriceCacherTask_InvalidPriceCache(cache) | Covered: [test][test_whenPriceCacheDoesNotSupportRequiredInterface_reverts] |
| PCACHER-CONSTRUCTOR-D02 | Deployer | N/A | N/A | Cache omits IPriceCache | PriceCacherTask_InvalidPriceCache(cache) | Covered: [test][test_givenCacheInterfaceMissing_whenDeployed_reverts] |
| PCACHER-CONSTRUCTOR-D05 | Deployer | N/A | N/A | Foreign reported Kernel | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | Covered: [test][test_whenPriceCacheUsesDifferentKernel_reverts] |
| PCACHER-CONSTRUCTOR-D06 | Deployer | N/A | N/A | Compatible cache VERSION getter reverts | Accept; do not query VERSION; exact initial state | Covered: [test][test_givenVersionGetterReverts_whenDeployed_thenIgnored] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-P01 | Fuzz deployers | Not installed | false | Valid cache, Kernel, and explicit gas limits | Store exact Kernel, cache and gas limits. Start disabled with no transition history, standard grace and no pairs | Covered: [test][test_whenConfigurationIsValid_startsWithNoAssetPairs] |
| PCACHER-CONSTRUCTOR-P02 | Deployer | Not installed | false | Smallest valid execution and pair limits, adjacent valid values, and largest valid limits | Store both exact limits | Covered: [test][test_whenGasLimitsAreValid_storesBoundaryValues] |
| PCACHER-CONSTRUCTOR-P03 | Deployer | Not installed | false | Execution limit from 40,002 through the maximum `uint32`. Pair limit from one through execution limit minus 40,001 | Store both exact limits | Covered: [test][test_whenGasLimitsAreValid_storesBoth] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-D08 | Deployer | N/A | N/A | kernel() reverts | PolicyDependency_InvalidDependency(cache) | Covered: [test][test_givenKernelGetterReverts_whenDeployed_reverts] |
| PCACHER-CONSTRUCTOR-D09 | Deployer | N/A | N/A | kernel() returns malformed address ABI | PolicyDependency_InvalidDependency(cache) | Covered: [test][test_givenMalformedKernelLength_whenDeployed_reverts], [test][test_givenNoncanonicalKernel_whenDeployed_reverts], [test][test_whenMalformedMetadataBoundarySeeds_reverts] |
| PCACHER-CONSTRUCTOR-D10 | Deployer | N/A | N/A | Compatible cache omits IVersioned | Accept; do not query VERSION; exact initial state | Covered: [test][test_givenNoVersionInterface_whenDeployed_thenAccepted] |

## Additional authorization and boundary cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-CONSTRUCTOR-D11 | Deployer | N/A | N/A | ERC165 probe reverts | PriceCacherTask_InvalidPriceCache(cache) | Covered: [test][test_givenInterfaceProbeReverts_whenDeployed_reverts] |
| PCACHER-CONSTRUCTOR-D12 | Deployer | N/A | N/A | ERC165 probe returns malformed bool ABI | PriceCacherTask_InvalidPriceCache(cache) | Covered: [test][test_givenInterfaceProbeMalformed_whenDeployed_reverts] |

[test_givenCacheInterfaceMissing_whenDeployed_reverts]: constructor.t.sol#L183
[test_givenCacheLifecycle_whenDeployed]: constructor.t.sol#L163
[test_givenInterfaceProbeMalformed_whenDeployed_reverts]: constructor.t.sol#L245
[test_givenInterfaceProbeReverts_whenDeployed_reverts]: constructor.t.sol#L235
[test_givenKernelGetterReverts_whenDeployed_reverts]: constructor.t.sol#L189
[test_givenMalformedKernelLength_whenDeployed_reverts]: constructor.t.sol#L195
[test_givenNoVersionInterface_whenDeployed_thenAccepted]: constructor.t.sol#L255
[test_givenNoncanonicalKernel_whenDeployed_reverts]: constructor.t.sol#L202
[test_givenVersionGetterReverts_whenDeployed_thenIgnored]: constructor.t.sol#L262
[test_whenConfigurationIsValid_startsWithNoAssetPairs]: constructor.t.sol#L148
[test_whenExecutionGasEqualsPairGasPlusReserve_reverts]: constructor.t.sol#L32
[test_whenExecutionGasLeavesInsufficientGasForAPair_reverts]: constructor.t.sol#L48
[test_whenGasLimitsAreInvalid_revertsAtBoundaries]: constructor.t.sol#L37
[test_whenGasLimitsAreValid_storesBoth]: constructor.t.sol#L70
[test_whenGasLimitsAreValid_storesBoundaryValues]: constructor.t.sol#L62
[test_whenMalformedMetadataBoundarySeeds_reverts]: constructor.t.sol#L209
[test_whenPairGasLimitIsZero_reverts]: constructor.t.sol#L27
[test_whenPriceCacheDoesNotSupportRequiredInterface_reverts]: constructor.t.sol#L114
[test_whenPriceCacheIsNotContract_reverts]: constructor.t.sol#L100
[test_whenPriceCacheIsZero_reverts]: constructor.t.sol#L21
[test_whenPriceCacheUsesDifferentKernel_reverts]: constructor.t.sol#L130
[test_whenStartupLifecycleSeedsUsed]: constructor.t.sol#L173
