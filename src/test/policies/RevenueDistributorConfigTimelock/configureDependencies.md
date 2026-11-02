# RevenueDistributorConfigTimelock.configureDependencies scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: permissionless ROLES dependency discovery and refresh in every policy lifecycle state.

## Scenarios

| ID | Caller | Local active | Local enabled | ROLES module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-DEPS-P01 | Fuzz all callers | true | true | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles], [test][test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds] |
| RDCT-DEPS-P03 | Fuzz all callers | true | false | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles], [test][test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds] |
| RDCT-DEPS-P04 | Fuzz all callers | false | true | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles], [test][test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds] |
| RDCT-DEPS-P05 | Fuzz all callers | false | false | Present, major 1 | Returns `[ROLES]` | Cached ROLES address refreshes; other state unchanged | Covered: [test][test_whenCalledInAnyLifecycleState_refreshesRoles], [test][test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds] |
| RDCT-DEPS-P02 | Fuzz all callers | true | true | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement], [test][test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds] |
| RDCT-DEPS-P06 | Fuzz all callers | true | false | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement], [test][test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds] |
| RDCT-DEPS-P07 | Fuzz all callers | false | true | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement], [test][test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds] |
| RDCT-DEPS-P08 | Fuzz all callers | false | false | Replaced with compatible minor version | Success | Cached ROLES address changes | Covered: [test][test_whenRolesUpgraded_refreshesCompatibleReplacement], [test][test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds] |
| RDCT-DEPS-I01 | Fuzz all callers | true | true | Missing | Policy_ModuleDoesNotExist(ROLES) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenRolesMissing_reverts] |
| RDCT-DEPS-I02 | Fuzz all callers | true | true | Present, major not 1 | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenRolesUnsupportedMajor_reverts] |

[test_whenCalledInAnyLifecycleState_refreshesRoles]: ./configureDependencies.t.sol#L18
[test_whenRolesUpgraded_refreshesCompatibleReplacement]: ./configureDependencies.t.sol#L55

[test_whenCalledInAnyLifecycleState_refreshesRolesLifecycleSeeds]: ./configureDependencies.t.sol#L126

[test_whenRolesUpgraded_refreshesCompatibleReplacementLifecycleSeeds]: ./configureDependencies.t.sol#L138

[test_givenActivePolicy_whenRolesMissing_reverts]: ./configureDependencies.t.sol#L150

[test_givenActivePolicy_whenRolesUnsupportedMajor_reverts]: ./configureDependencies.t.sol#L180
