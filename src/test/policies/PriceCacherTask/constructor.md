# PriceCacherTask.constructor coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-CONSTRUCTOR`.

Construction validates cache compatibility and Kernel binding without requiring cache
readiness. The deployer is permissionless. Required interfaces are IPriceCache and IEnabler. Cache version discovery and numeric versions are not required. Initial state is
disabled, lastTransitionAt=0, grace=7 days, no configured pairs.

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
| PCACHER-CONSTRUCTOR-P01 | Fuzz deployers | Not installed | false | Valid cache and Kernel | Store exact Kernel/cache; initial disabled/history/grace/empty set | Covered: [test][test_whenConfigurationIsValid_startsWithNoAssetPairs] |

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

[test_givenCacheInterfaceMissing_whenDeployed_reverts]: constructor.t.sol#L110
[test_givenCacheLifecycle_whenDeployed]: constructor.t.sol#L90
[test_givenInterfaceProbeMalformed_whenDeployed_reverts]: constructor.t.sol#L172
[test_givenInterfaceProbeReverts_whenDeployed_reverts]: constructor.t.sol#L162
[test_givenKernelGetterReverts_whenDeployed_reverts]: constructor.t.sol#L116
[test_givenMalformedKernelLength_whenDeployed_reverts]: constructor.t.sol#L122
[test_givenNoVersionInterface_whenDeployed_thenAccepted]: constructor.t.sol#L182
[test_givenNoncanonicalKernel_whenDeployed_reverts]: constructor.t.sol#L129
[test_givenVersionGetterReverts_whenDeployed_thenIgnored]: constructor.t.sol#L189
[test_whenConfigurationIsValid_startsWithNoAssetPairs]: constructor.t.sol#L77
[test_whenMalformedMetadataBoundarySeeds_reverts]: constructor.t.sol#L136
[test_whenPriceCacheDoesNotSupportRequiredInterface_reverts]: constructor.t.sol#L43
[test_whenPriceCacheIsNotContract_reverts]: constructor.t.sol#L29
[test_whenPriceCacheIsZero_reverts]: constructor.t.sol#L21
[test_whenPriceCacheUsesDifferentKernel_reverts]: constructor.t.sol#L59
[test_whenStartupLifecycleSeedsUsed]: constructor.t.sol#L100
