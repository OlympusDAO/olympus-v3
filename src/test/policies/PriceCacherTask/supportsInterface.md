# PriceCacherTask.supportsInterface coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-INTERFACES`.

ERC165 discovery is permissionless and does not consume operational dependencies.
Required IDs include IERC165, IPeriodicTask, IPriceCacherTask, IVersioned, IEnabler,
IEnablerV2, IReEnabler and IGracePeriod. Unknown IDs, including 0 and 0xffffffff, return false.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-INTERFACES-L01 | Fuzz all callers | false | false | Policy inactive/paused or dependencies unavailable | Same discovery result, no writes | Covered: [test][test_givenInactivePausedAndBrokenCache_whenDiscoveryQueried] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-INTERFACES-N01 | Any caller | true | true | 0xffffffff boundary | Return false | Covered: [test][test_givenUnsupportedInterface_returnsFalse] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-INTERFACES-P01 | Any caller | true | true | Task, periodic-task and version IDs | Return true for each exact ID | Covered: [test][test_givenSupportedInterfaces_returnsTrue] |
| PCACHER-INTERFACES-P02 | Fuzz all callers | true | true | IERC165 and all lifecycle IDs | Return true | Covered: [test][test_whenLifecycleInterfacesQueried] |
| PCACHER-INTERFACES-P03 | Fuzz all callers | true | true | Fuzz every other bytes4 ID | Return false | Covered: [test][test_whenUnknownInterfaceQueried] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePausedAndBrokenCache_whenDiscoveryQueried]: supportsInterface.t.sol#L73
[test_givenSupportedInterfaces_returnsTrue]: supportsInterface.t.sol#L22
[test_givenUnsupportedInterface_returnsFalse]: supportsInterface.t.sol#L35
[test_whenLifecycleInterfacesQueried]: supportsInterface.t.sol#L40
[test_whenUnknownInterfaceQueried]: supportsInterface.t.sol#L57
