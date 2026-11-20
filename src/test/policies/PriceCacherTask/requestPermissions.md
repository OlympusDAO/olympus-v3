# PriceCacherTask.requestPermissions coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-PERMISSIONS`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
priceCache() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-PERMISSIONS-P01 | Fuzz all callers | true | true | Configured policy; query permissions | Return empty array; no writes/logs | Covered: [test][test_whenPermissionsRequested] |
| PCACHER-PERMISSIONS-P02 | Fuzz all callers | false | false | Never configured or activated | Return empty array without dependency reads | Covered: [test][test_givenNeverConfigured_whenPermissionsRequested] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenNeverConfigured_whenPermissionsRequested]: requestPermissions.t.sol#L21
[test_whenPermissionsRequested]: requestPermissions.t.sol#L9
