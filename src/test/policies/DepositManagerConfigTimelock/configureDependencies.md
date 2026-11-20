# DepositManagerConfigTimelock.configureDependencies coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-DEPENDENCIES`.

Permissionless framework hook binds the intended Kernel's ROLES module; no own membership or
enablement gate. ROLES is a module, not an operational policy. Major version must be 1;
all uint8 minor versions are compatible. No module write permissions are requested.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Module binding

| ID | Caller | ROLES registry / version | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-DEPENDENCIES-P01 | Fuzz all callers | Major 1; independent uint8 minor | Return exactly ROLES dependency; cache module address; preserve target state | Covered: [test][test_whenDependenciesConfigured] |
| DMCT-DEPENDENCIES-I01 | Any | ROLES missing | Policy_ModuleDoesNotExist(ROLES) | Covered: [test][test_givenRolesMissing_whenConfigured_reverts] |
| DMCT-DEPENDENCIES-I02 | Any | Fuzz uint8 major !=1 and independent minor; seeds 0,2,MAX8 | DepositManagerConfigTimelock_InvalidModuleVersion() | Covered: [test][test_whenRolesMajorUnsupported_reverts], [test][test_whenRolesMajorBoundarySeeds_reverts] |

## Lifecycle independence

| ID | Caller | Local active | Local enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-DEPENDENCIES-L01 | Fuzz all callers | false | false | Bind ROLES while paused/inactive; no activation or enablement | Covered: [test][test_givenPausedInactive_whenDependenciesConfigured] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_whenDependenciesConfigured]: configureDependencies.t.sol#L15
[test_givenRolesMissing_whenConfigured_reverts]: configureDependencies.t.sol#L42
[test_whenRolesMajorUnsupported_reverts]: configureDependencies.t.sol#L55
[test_whenRolesMajorBoundarySeeds_reverts]: configureDependencies.t.sol#L69
[test_givenPausedInactive_whenDependenciesConfigured]: configureDependencies.t.sol#L31
