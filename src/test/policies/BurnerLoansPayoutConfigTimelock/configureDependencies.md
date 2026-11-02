# BurnerLoansPayoutConfigTimelock.configureDependencies coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [configureDependencies](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L88).

## Domains and notation

Scenario scope: `BLCUCT-DEPENDENCIES`. Permissionless framework hook across all local/target lifecycle states; no controller-selection requirement.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Module resolution

Fuzz Local active/enabled independently; target getters reject unexpected calls.

| ID | Caller | ROLES state | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-DEPENDENCIES-D01 | Fuzz all callers | Missing ROLES keycode | Policy_ModuleDoesNotExist(keycode) | No cached pointer mutation | Covered: [test][test_givenRolesAbsent_whenConfigured_reverts] |
| BLCUCT-DEPENDENCIES-D02 | Fuzz all callers | Unsupported ROLES major!=1 | BurnerLoans_InvalidModuleVersion() | Cache write rolls back | Covered: [test][test_givenUnsupportedRolesVersion_whenConfigured_reverts] |
| BLCUCT-DEPENDENCIES-D03 | Fuzz all callers | Supported module; initial/repeated/replacement call | Return exactly [ROLES]; cached module refreshed | No queue, target/controller or local enablement change | Covered: [test][test_whenDependenciesConfigured_thenExactRolesCache], [test][test_givenKernelMigration_whenConfigured_thenFreshRolesResolved] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenKernelMigration_whenConfigured_thenFreshRolesResolved]: ./configureDependencies.t.sol#L87
[test_givenRolesAbsent_whenConfigured_reverts]: ./configureDependencies.t.sol#L45
[test_givenUnsupportedRolesVersion_whenConfigured_reverts]: ./configureDependencies.t.sol#L63
[test_whenDependenciesConfigured_thenExactRolesCache]: ./configureDependencies.t.sol#L19
