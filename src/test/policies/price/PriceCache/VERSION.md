# PriceCache.VERSION coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-VERSION`.

Version discovery is permissionless and independent of local enablement, Kernel membership
and operational dependencies. It returns version 1.0 without reading or changing policy state.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VERSION-L01 | Fuzz all callers | false | false | Policy paused and inactive | Same version independent of lifecycle | Covered: [test][test_givenInactivePaused_whenVersionQueried] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VERSION-P01 | Fuzz all callers | true | true | Any caller; no operational dependency required | Return major=1, minor=0; no writes | Covered: [test][test_whenAnyCallerQueriesVersion] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePaused_whenVersionQueried]: VERSION.t.sol#L17
[test_whenAnyCallerQueriesVersion]: VERSION.t.sol#L9
