# PriceCacherTask.configureDependencies coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-DEPENDENCIES`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
priceCache() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-DEPENDENCIES-L01 | Fuzz all callers | true | false | Paused policy with cached modules | Configuration hook remains callable; preserve pause and data | Covered: [test][test_givenPaused_whenConfigured] |
| PCACHER-DEPENDENCIES-L02 | Fuzz all callers | false | true | Deactivated policy with modules installed | Configuration hook remains callable; preserve local state | Covered: [test][test_givenInactive_whenConfigured] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-DEPENDENCIES-I01 | Any address | true | true | ROLES is absent from intended Kernel | Policy_ModuleDoesNotExist(ROLES) | Covered: [test][test_givenMissingRoles_whenConfigured_reverts] |
| PCACHER-DEPENDENCIES-I02 | Fuzz all callers | true | true | ROLES major uint8 !=1; independent minor uint8; seed 0,2,MAX8 | Policy_WrongModuleVersion(abi.encode([1])) | Covered: [test][test_whenUnsupportedRolesVersion_reverts], [test][test_whenRolesVersionBoundarySeeds_reverts] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-DEPENDENCIES-P01 | Fuzz all callers | true | true | Fuzz caller; repeat configured bindings | Exact dependency keycodes and cached ROLES; preserve seeded data | Covered: [test][test_whenDependenciesConfigured] |
| PCACHER-DEPENDENCIES-P02 | Fuzz all callers | false | false | Never configured/activated/enabled | Bind modules without activation or enablement | Covered: [test][test_givenUnconfigured_whenDependenciesConfigured] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactive_whenConfigured]: configureDependencies.t.sol#L50
[test_givenMissingRoles_whenConfigured_reverts]: configureDependencies.t.sol#L31
[test_givenPaused_whenConfigured]: configureDependencies.t.sol#L44
[test_givenUnconfigured_whenDependenciesConfigured]: configureDependencies.t.sol#L20
[test_whenDependenciesConfigured]: configureDependencies.t.sol#L9
[test_whenRolesVersionBoundarySeeds_reverts]: configureDependencies.t.sol#L78
[test_whenUnsupportedRolesVersion_reverts]: configureDependencies.t.sol#L56
