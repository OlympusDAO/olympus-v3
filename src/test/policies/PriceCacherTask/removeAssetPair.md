# PriceCacherTask.removeAssetPair coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-REMOVE-PAIR`.

ADMIN or PRICE_ADMIN (`price_admin`) may remove pairs while paused. Unordered identity finds either request orientation.
Removal emits the stored orientation and may swap the last entry into the removed index.
Removing the final pair is supported. getAssetPairs() must reflect the exact remaining set.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-A01 | Fuzz unauthorized callers | true | true | Fuzz callers excluding ADMIN and PRICE_ADMIN | NotAuthorised() | Covered: [test][test_whenCallerIsNotAuthorized_reverts] |
| PCACHER-REMOVE-PAIR-A02 | Fuzz ADMIN holders | true | true | Fuzz all ADMIN identities | Remove matching pair with exact event | Covered: [test][test_whenAdminAndRemovalIndexVary_thenExactSurvivors] |
| PCACHER-REMOVE-PAIR-A03 | Fuzz PRICE_ADMIN-only holders | true | Fuzz true/false | Caller has no ADMIN role | Exact pair mutation/event; lifecycle preserved | Covered: [test][test_whenPriceAdminRemovesPair] |
| PCACHER-REMOVE-PAIR-A04 | Fuzz ADMIN and PRICE_ADMIN overlap | true | true | Both grants held | Exact pair mutation/event; lifecycle preserved | Covered: [test][test_whenBothRolesRemovePair] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-L01 | ADMIN | true | false | Task paused | Remove and remain paused | Covered: [test][test_givenDisabled_whenAdminRemovesPair] |
| PCACHER-REMOVE-PAIR-L02 | ADMIN | true | true | Task re-enabled | Remove and stay enabled | Covered: [test][test_givenReEnabled_whenAdminRemovesPair] |
| PCACHER-REMOVE-PAIR-L03 | ADMIN | false | Fuzz true/false | Task Kernel-inactive | PriceCacherTask_PolicyInactive(subject); unchanged | Covered: [test][test_givenInactive_whenPairRemoved_reverts] |
| PCACHER-REMOVE-PAIR-L04 | Fuzz PRICE_ADMIN-only holders | true | Fuzz true/false | Enabled or paused task | Exact pair mutation/event; preserve lifecycle | Covered: [test][test_whenPriceAdminRemovesPair] |
| PCACHER-REMOVE-PAIR-L05 | PRICE_ADMIN-only holder | false | Fuzz true/false | Kernel-inactive task | PriceCacherTask_PolicyInactive(subject); unchanged | Covered: [test][test_givenInactive_whenPriceAdminRemovesPair_reverts] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-I01 | ADMIN | true | true | Asset=0 | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenAssetIsZero_reverts] |
| PCACHER-REMOVE-PAIR-I02 | ADMIN | true | true | Quote=0 | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenQuoteIsZero_reverts] |
| PCACHER-REMOVE-PAIR-I03 | ADMIN | true | true | Asset=quote | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenAssetEqualsQuote_reverts] |
| PCACHER-REMOVE-PAIR-I04 | ADMIN | true | true | Pair absent | PriceCacherTask_AssetPairNotFound(asset,quote) | Covered: [test][test_whenPairDoesNotExist_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-D01 | ADMIN | true | true | Pair no longer supported by cache | Removal remains available without cache support validation | Covered: [test][test_givenPairIsNoLongerSupported_whenAdminRemovesPair] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-N01 | ADMIN | true | true | Fuzz valid nonzero pair identities and counts 1..32 | Correct unique removal and preservation of all other entries | Covered: [test][test_whenAdminAndRemovalIndexVary_thenExactSurvivors], [test][test_whenRemovalBoundarySeedsUsed], [test][test_whenFullAddressPairRemoved], [test][test_whenAddressBoundaryPairRemoved] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-P01 | ADMIN | true | true | Reverse request removes existing pair | Emit stored orientation; exact remaining tuple | Covered: [test][test_givenPairExistsInReverseOrder_whenAdminRemovesPair] |
| PCACHER-REMOVE-PAIR-P02 | ADMIN | true | true | Remove multiple non-tail entries | Exact events and swap-and-pop result; preserve unrelated entries | Covered: [test][test_givenMultipleEntries_whenAdminRemovesMultiplePairs] |
| PCACHER-REMOVE-PAIR-P03 | ADMIN | true | true | Remove last remaining entry | Empty set supported | Covered: [test][test_givenOnePair_whenAdminRemovesPair_allowsEmptyConfiguration] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-REMOVE-PAIR-L06 | Any address, fuzz, without authorization exclusions | false | false | Task paused, then Kernel-deactivated; existing cache/pair fixture retained; Asset and quote both `address(0)` | `PriceCacherTask_PolicyInactive(task)` before caller, input and dependency checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst] |

[test_givenDisabled_whenAdminRemovesPair]: removeAssetPair.t.sol#L160
[test_givenInactive_whenPairRemoved_reverts]: removeAssetPair.t.sol#L230
[test_givenMultipleEntries_whenAdminRemovesMultiplePairs]: removeAssetPair.t.sol#L134
[test_givenOnePair_whenAdminRemovesPair_allowsEmptyConfiguration]: removeAssetPair.t.sol#L186
[test_givenPairExistsInReverseOrder_whenAdminRemovesPair]: removeAssetPair.t.sol#L118
[test_givenPairIsNoLongerSupported_whenAdminRemovesPair]: removeAssetPair.t.sol#L104
[test_givenReEnabled_whenAdminRemovesPair]: removeAssetPair.t.sol#L172
[test_whenAddressBoundaryPairRemoved]: removeAssetPair.t.sol#L244
[test_whenAdminAndRemovalIndexVary_thenExactSurvivors]: removeAssetPair.t.sol#L196
[test_whenAssetEqualsQuote_reverts]: removeAssetPair.t.sol#L79
[test_whenAssetIsZero_reverts]: removeAssetPair.t.sol#L61
[test_whenCallerIsNotAuthorized_reverts]: removeAssetPair.t.sol#L18
[test_whenFullAddressPairRemoved]: removeAssetPair.t.sol#L221
[test_whenPairDoesNotExist_reverts]: removeAssetPair.t.sol#L88
[test_whenQuoteIsZero_reverts]: removeAssetPair.t.sol#L70
[test_whenRemovalBoundarySeedsUsed]: removeAssetPair.t.sol#L214
[test_whenPriceAdminRemovesPair]: removeAssetPair.t.sol#L28
[test_whenBothRolesRemovePair]: removeAssetPair.t.sol#L36
[test_givenInactive_whenPriceAdminRemovesPair_reverts]: removeAssetPair.t.sol#L43
[test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst]: ./removeAssetPair.t.sol#L274
