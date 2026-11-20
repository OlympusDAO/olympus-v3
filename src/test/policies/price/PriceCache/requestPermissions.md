# PriceCache.requestPermissions coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-PERMISSIONS`.

Framework hooks use the bound Kernel and its authoritative module registry. Own local
activity does not gate framework setup or pure discovery. Public kernel(), ROLES() and
PRICE() bindings are asserted with their owning configure/constructor/migration actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-PERMISSIONS-P01 | Fuzz all callers | true | true | Configured policy; query permissions | Return empty array; no writes/logs | Covered: [test][test_whenPermissionsRequested] |
| PCACHE-PERMISSIONS-P02 | Fuzz all callers | false | false | Never configured or activated | Return empty array without dependency reads | Covered: [test][test_givenNeverConfigured_whenPermissionsRequested] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_whenPermissionsRequested]: requestPermissions.t.sol#L10
[test_givenNeverConfigured_whenPermissionsRequested]: requestPermissions.t.sol#L22
