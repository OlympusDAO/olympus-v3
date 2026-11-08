# BurnerLoansPayout.configureDependencies coverage plan

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansPayout.sol#L124). Coverage is recorded in the Test column. Apply [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md).

## Domains and behavior

Scenario scope: `BLCU-DEPENDENCIES` identifies this contract/function.

Permissionless framework hook; no local enablement or policy activity gate. Returns ordered ROLES,TRSRY dependencies. ROLES is cached from this policy's Kernel and must have major version 1. TRSRY is resolved to validate presence; its recipient stays a live Kernel lookup so retired claims follow Treasury replacement. No Core context reads.

| ID | Caller | Kernel modules | Payout active | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-DEPENDENCIES-P01 | Fuzz any address | Both installed; first/repeated/replaced | true | Ordered keycodes; cache current ROLES; preserve balances and routing | Covered: [test_whenConfigured_thenOrderedDependenciesAndCache][test_whenConfigured_thenOrderedDependenciesAndCache]; [test_givenNewRoles_whenConfigured_thenCacheReplaced][test_givenNewRoles_whenConfigured_thenCacheReplaced] |
| BLCU-DEPENDENCIES-P02 | Fuzz any address | Both installed; first/repeated/replaced | false | Ordered keycodes; cache current ROLES; preserve balances and routing | Covered: [test_whenConfigured_thenOrderedDependenciesAndCache][test_whenConfigured_thenOrderedDependenciesAndCache]; [test_givenNewRoles_whenConfigured_thenCacheReplaced][test_givenNewRoles_whenConfigured_thenCacheReplaced]; [test_givenNeverActivated_whenFirstConfigured_thenCacheInitialized][test_givenNeverActivated_whenFirstConfigured_thenCacheInitialized] |
| BLCU-DEPENDENCIES-P03 | Fuzz any address | ROLES absent | true | Policy_ModuleDoesNotExist(missingKeycode) | Covered: [test_givenRolesMissing_whenConfigured_reverts][test_givenRolesMissing_whenConfigured_reverts] |
| BLCU-DEPENDENCIES-P04 | Fuzz any address | ROLES absent | false | Policy_ModuleDoesNotExist(missingKeycode) | Covered: [test_givenRolesMissing_whenConfigured_reverts][test_givenRolesMissing_whenConfigured_reverts] |

Co-located treasury getter resolves the current TRSRY. Upgrade TRSRY with current and previous Payout contracts active/inactive and assert liquidation/fee retries use the new module without calling Core.configureDependencies. The Treasury getter does not check the module major version; configureDependencies requires ROLES major version 1.

- [x] Review expectations before production test implementation.
- [x] Adapt existing Framework/recovery tests and map passing proofs.

| ID | Caller | Module state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-DEPENDENCIES-D01 | ADMIN on a previously activated Payout | ROLES already cached; later Kernel ROLES lookup configured to revert | Subsequent flag setter succeeds through cached ROLES | No repeated Kernel role resolution | Covered: [test_givenCachedRoles_whenAdminConfigures_thenNoKernelRolesLookup][test_givenCachedRoles_whenAdminConfigures_thenNoKernelRolesLookup] |

## Missing Treasury and incompatible ROLES

| ID | Caller | Local active | Missing/incompatible module | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-DEPENDENCIES-I01 | Fuzz all callers | true | TRSRY absent; ROLES valid | Policy_ModuleDoesNotExist(TRSRY) | ROLES cache write rolls back | Covered: [test_givenTreasuryMissing_whenConfigured_reverts][test_givenTreasuryMissing_whenConfigured_reverts] |
| BLCU-DEPENDENCIES-I02 | Fuzz all callers | false | TRSRY absent; ROLES valid | Policy_ModuleDoesNotExist(TRSRY) | ROLES cache write rolls back | Covered: [test_givenTreasuryMissing_whenConfigured_reverts][test_givenTreasuryMissing_whenConfigured_reverts] |
| BLCU-DEPENDENCIES-D02 | Fuzz all callers | Fuzz true/false | ROLES major !=1 | Policy_WrongModuleVersion(abi.encode([uint8(1)])) | No cache/balance/route change | Covered: [test_givenUnsupportedRolesVersion_whenConfigured_reverts][test_givenUnsupportedRolesVersion_whenConfigured_reverts] |

[test_givenCachedRoles_whenAdminConfigures_thenNoKernelRolesLookup]: ./configureDependencies.t.sol#L110
[test_givenNeverActivated_whenFirstConfigured_thenCacheInitialized]: ./configureDependencies.t.sol#L133
[test_givenNewRoles_whenConfigured_thenCacheReplaced]: ./configureDependencies.t.sol#L34
[test_givenRolesMissing_whenConfigured_reverts]: ./configureDependencies.t.sol#L52
[test_givenTreasuryMissing_whenConfigured_reverts]: ./configureDependencies.t.sol#L70
[test_givenUnsupportedRolesVersion_whenConfigured_reverts]: ./configureDependencies.t.sol#L88
[test_whenConfigured_thenOrderedDependenciesAndCache]: ./configureDependencies.t.sol#L15
