# PriceCache.configureDependencies coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-DEPENDENCIES`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
PRICE() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DEPENDENCIES-L01 | Fuzz all callers | true | false | Paused policy with cached modules | Configuration hook remains callable; preserve pause and data | Covered: [test][test_givenPaused_whenDependenciesConfigured] |
| PCACHE-DEPENDENCIES-L02 | Fuzz all callers | false | true | Deactivated policy with modules installed | Configuration hook remains callable; preserve local state | Covered: [test][test_givenInactive_whenDependenciesConfigured] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DEPENDENCIES-I01 | Any address | true | true | ROLES is absent from intended Kernel | Policy_ModuleDoesNotExist(ROLES) | Covered: [test][test_givenMissingRoles_whenConfigured_reverts] |
| PCACHE-DEPENDENCIES-I02 | Fuzz all callers | true | true | ROLES major uint8 !=1; independent minor uint8; seed 0,2,MAX8 | PriceCache_UnsupportedModuleVersion(ROLES,major,minor) | Covered: [test][test_whenRolesMajorUnsupported_reverts], [test][test_whenRolesMajorBoundarySeeds_reverts] |
| PCACHE-DEPENDENCIES-I03 | Any address | true | true | PRICE missing | Policy_ModuleDoesNotExist(PRICE) | Covered: [test][test_givenPriceModuleMissing_whenConfigured_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DEPENDENCIES-D01 | Any address | true | true | PRICE major=1,minor<2 or major=0; seed 0,1.0,1.1 | PriceCache_UnsupportedModuleVersion(PRICE,major,minor) | Covered: [test][test_whenPriceMajorZero_reverts], [test][test_whenPriceOneMinorBelowTwo_reverts] |
| PCACHE-DEPENDENCIES-D02 | Any address | true | true | PRICE omits IPRICEv2 advertisement | PriceCache_UnsupportedModuleInterface(PRICE,IPriceV2) | Covered: [test][test_givenPriceInterfaceMissing_whenConfigured_reverts] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DEPENDENCIES-P01 | Fuzz all callers | true | true | Fuzz caller; repeat configured bindings | Exact dependency keycodes and cached ROLES; preserve seeded data | Covered: [test][test_whenDependenciesConfigured] |
| PCACHE-DEPENDENCIES-P02 | Fuzz all callers | false | false | Never configured/activated/enabled | Bind modules without activation or enablement | Covered: [test][test_givenUnconfigured_whenDependenciesConfigured] |
| PCACHE-DEPENDENCIES-P03 | Kernel | true | true | Compatible PRICE replacement | Advance cache epoch; old snapshots become zero in both directions | Covered: [test][test_whenPriceUpgradeInvalidatesEveryOrientation], [test][test_whenPRICEModuleIsUpgraded_invalidatesExistingSnapshots] |
| PCACHE-DEPENDENCIES-P04 | Any address | true | true | Existing unit-of-account metadata was manually updated; configure again | Do not overwrite existing unit metadata or invalidate unrelated snapshots | Covered: [test][test_whenRepeatedConfigurationPreservesCustomUnitMetadata] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenPaused_whenDependenciesConfigured]: configureDependencies.t.sol#L58
[test_givenInactive_whenDependenciesConfigured]: configureDependencies.t.sol#L73
[test_givenMissingRoles_whenConfigured_reverts]: configureDependencies.t.sol#L45
[test_whenRolesMajorUnsupported_reverts]: configureDependencies.t.sol#L88
[test_whenRolesMajorBoundarySeeds_reverts]: configureDependencies.t.sol#L107
[test_givenPriceModuleMissing_whenConfigured_reverts]: configureDependencies.t.sol#L114
[test_whenPriceMajorZero_reverts]: configureDependencies.t.sol#L127
[test_whenPriceOneMinorBelowTwo_reverts]: configureDependencies.t.sol#L145
[test_givenPriceInterfaceMissing_whenConfigured_reverts]: configureDependencies.t.sol#L164
[test_whenDependenciesConfigured]: configureDependencies.t.sol#L21
[test_givenUnconfigured_whenDependenciesConfigured]: configureDependencies.t.sol#L34
[test_whenPriceUpgradeInvalidatesEveryOrientation]: configureDependencies.t.sol#L181
[test_whenPRICEModuleIsUpgraded_invalidatesExistingSnapshots]: getCachedPrice.t.sol#L55
[test_whenRepeatedConfigurationPreservesCustomUnitMetadata]: configureDependencies.t.sol#L198
