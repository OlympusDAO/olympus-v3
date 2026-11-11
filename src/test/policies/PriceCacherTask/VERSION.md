# PriceCacherTask.VERSION coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-VERSION`.

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
| PCACHER-VERSION-L01 | Fuzz all callers | false | false | Policy paused and inactive | Same version independent of lifecycle | Covered: [test][test_givenInactivePaused_whenVersionQueried] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-VERSION-P01 | Fuzz all callers | true | true | Any caller; no operational dependency required | Return major=1, minor=0; no writes | Covered: [test][test_whenAnyCallerQueriesVersion] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePaused_whenVersionQueried]: VERSION.t.sol#L20
[test_whenAnyCallerQueriesVersion]: VERSION.t.sol#L9
