# PriceCache.supportsInterface coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-INTERFACES`.

Discovery is permissionless, including while inactive, paused or never configured.
Required IDs are IERC165, IPriceCache, IVersioned and every inherited lifecycle interface.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-INTERFACES-L01 | Fuzz all callers | false | false | Inactive and paused; no PRICE required | Same results without module reads | Covered: [test][test_givenInactivePaused_whenInterfacesQueried] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-INTERFACES-P01 | Fuzz all callers | true | true | Each required ERC165/cache/version/lifecycle ID | Return true | Covered: [test][test_whenKnownInterfacesQueried] |
| PCACHE-INTERFACES-P02 | Fuzz all callers | true | true | Fuzz bytes4 excluding all supported IDs | Return false | Covered: [test][test_whenUnknownInterfaceQueried] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePaused_whenInterfacesQueried]: supportsInterface.t.sol#L55
[test_whenKnownInterfacesQueried]: supportsInterface.t.sol#L18
[test_whenUnknownInterfaceQueried]: supportsInterface.t.sol#L40
