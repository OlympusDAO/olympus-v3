# RevenueDistributor.configureDependencies scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: dependency discovery and refresh. The function is callable by any caller regardless of the policy's Kernel-active or local enabled state.

## Scenarios

| ID | Caller | Local active | Local enabled | ROLES module | TRSRY module | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD-DEPS-P01 | Fuzz all callers | true | true | Present, major 1 | Present, major 1 | Returns `[ROLES, TRSRY]` in order | Both cached module addresses refresh; other state and balances unchanged | Covered: [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys], [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds] |
| RD-DEPS-P03 | Fuzz all callers | true | false | Present, major 1 | Present, major 1 | Returns `[ROLES, TRSRY]` in order | Both cached module addresses refresh; other state and balances unchanged | Covered: [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys], [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds] |
| RD-DEPS-P04 | Fuzz all callers | false | true | Present, major 1 | Present, major 1 | Returns `[ROLES, TRSRY]` in order | Both cached module addresses refresh; other state and balances unchanged | Covered: [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys], [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds] |
| RD-DEPS-P05 | Fuzz all callers | false | false | Present, major 1 | Present, major 1 | Returns `[ROLES, TRSRY]` in order | Both cached module addresses refresh; other state and balances unchanged | Covered: [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys], [test][test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds] |
| RD-DEPS-P02 | Fuzz all callers | true | true | Present, compatible | Present, compatible; replace either module | Success | Only the selected module address changes | Covered: [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds] |
| RD-DEPS-P06 | Fuzz all callers | true | false | Present, compatible | Present, compatible; replace either module | Success | Only the selected module address changes | Covered: [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds] |
| RD-DEPS-P07 | Fuzz all callers | false | true | Present, compatible | Present, compatible; replace either module | Success | Only the selected module address changes | Covered: [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds] |
| RD-DEPS-P08 | Fuzz all callers | false | false | Present, compatible | Present, compatible; replace either module | Success | Only the selected module address changes | Covered: [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes], [test][test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds], [test][test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds] |
| RD-DEPS-I01 | Fuzz all callers | true | true | Missing | Any | Policy_ModuleDoesNotExist(ROLES) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenRolesMissing_reverts] |
| RD-DEPS-I02 | Fuzz all callers | true | true | Present, compatible | Missing | Policy_ModuleDoesNotExist(TRSRY) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenTreasuryMissing_reverts] |
| RD-DEPS-I03 | Fuzz all callers | true | true | Present, major not 1 | Present | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenRolesUnsupportedMajor_reverts] |
| RD-DEPS-I04 | Fuzz all callers | true | true | Present, major 1 | Present, major not 1 | Policy_WrongModuleVersion(abi.encode([1])) | Atomic rollback | Covered: [test][test_givenActivePolicy_whenTreasuryUnsupportedMajor_reverts] |

[test_whenAnyCallerConfiguresDependencies_returnsOrderedKeys]: ./configureDependencies.t.sol#L14

[test_whenAnyCallerConfiguresDependencies_returnsOrderedKeysLifecycleSeeds]: ./configureDependencies.t.sol#L144

[test_givenCompatibleRolesReplacement_whenAnyCallerRefreshes]: ./configureDependencies.t.sol#L156

[test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshes]: ./configureDependencies.t.sol#L209

[test_givenCompatibleRolesReplacement_whenAnyCallerRefreshesLifecycleSeeds]: ./configureDependencies.t.sol#L197

[test_givenCompatibleTreasuryReplacement_whenAnyCallerRefreshesLifecycleSeeds]: ./configureDependencies.t.sol#L257

[test_givenActivePolicy_whenRolesMissing_reverts]: ./configureDependencies.t.sol#L269

[test_givenActivePolicy_whenRolesUnsupportedMajor_reverts]: ./configureDependencies.t.sol#L299

[test_givenActivePolicy_whenTreasuryMissing_reverts]: ./configureDependencies.t.sol#L332

[test_givenActivePolicy_whenTreasuryUnsupportedMajor_reverts]: ./configureDependencies.t.sol#L362
