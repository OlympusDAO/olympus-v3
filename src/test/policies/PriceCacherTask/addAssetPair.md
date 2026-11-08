# PriceCacherTask.addAssetPair coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-ADD-PAIR`.

ADMIN or PRICE_ADMIN (`price_admin`) may configure pairs while enabled or paused. The cache validates support; pair
identity is unordered for duplicate detection but insertion preserves requested orientation.
getAssetPairs() is the corresponding permissionless getter. No protocol pair-count cap is
defined; counts 0,1,2,32 are practical fixture seeds rather than a promised execution bound.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-A01 | Fuzz unauthorized callers | true | true | Fuzz callers excluding ADMIN and PRICE_ADMIN | NotAuthorised() | Covered: [test][test_whenCallerIsNotAuthorized_reverts] |
| PCACHER-ADD-PAIR-A02 | Fuzz ADMIN holders | true | true | Fuzz any ADMIN holder; include secondary-role overlaps | Append exact pair and emit AssetPairAdded | Covered: [test][test_whenAdminAndPairDomainVary_thenExactAppend], [test][test_whenPairAndCollectionBoundarySeedsUsed] |
| PCACHER-ADD-PAIR-A03 | Fuzz PRICE_ADMIN-only holders | true | Fuzz true/false | Caller has no ADMIN role | Exact pair mutation/event; lifecycle preserved | Covered: [test][test_whenPriceAdminAddsPair] |
| PCACHER-ADD-PAIR-A04 | Fuzz ADMIN and PRICE_ADMIN overlap | true | true | Both grants held | Exact pair mutation/event; lifecycle preserved | Covered: [test][test_whenBothRolesAddPair] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-L01 | ADMIN | true | false | Supported pair while paused | Append pair; remain paused | Covered: [test][test_givenDisabled_whenAdminAddsPair] |
| PCACHER-ADD-PAIR-L02 | ADMIN | true | true | Supported pair after reEnable | Append pair; remain enabled | Covered: [test][test_givenReEnabled_whenAdminAddsPair] |
| PCACHER-ADD-PAIR-L03 | ADMIN | false | Fuzz true/false | Kernel-inactive task with cached roles | PriceCacherTask_PolicyInactive(subject) before support probes; unchanged | Covered: [test][test_givenInactive_whenPairAdded_reverts] |
| PCACHER-ADD-PAIR-L04 | Fuzz PRICE_ADMIN-only holders | true | Fuzz true/false | Enabled or paused task | Exact pair mutation/event; preserve lifecycle | Covered: [test][test_whenPriceAdminAddsPair] |
| PCACHER-ADD-PAIR-L05 | PRICE_ADMIN-only holder | false | Fuzz true/false | Kernel-inactive task | PriceCacherTask_PolicyInactive(subject); unchanged | Covered: [test][test_givenInactive_whenPriceAdminAddsPair_reverts] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-I01 | ADMIN | true | true | Asset=0 | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenAssetIsZero_reverts] |
| PCACHER-ADD-PAIR-I02 | ADMIN | true | true | Quote=0 | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenQuoteIsZero_reverts] |
| PCACHER-ADD-PAIR-I03 | ADMIN | true | true | Asset=quote | PriceCacherTask_InvalidAssetPair() | Covered: [test][test_whenAssetEqualsQuote_reverts] |
| PCACHER-ADD-PAIR-I04 | ADMIN | true | true | Exact pair already present | PriceCacherTask_AssetPairAlreadyAdded(asset,quote) | Covered: [test][test_givenPairExists_reverts] |
| PCACHER-ADD-PAIR-I05 | ADMIN | true | true | Reverse pair already present | PriceCacherTask_AssetPairAlreadyAdded(requested asset,quote) | Covered: [test][test_givenPairExistsInReverseOrder_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-D01 | ADMIN | true | true | Cache rejects valid pair | Propagate exact PairUnsupported(asset,quote) | Covered: [test][test_whenPairIsNotSupportedByPriceCache_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-N01 | ADMIN | true | true | Empty, single and larger configured sets; full nonzero address range | Append without corrupting unrelated pairs; seed 0,1,32 item fixtures | Covered: [test][test_whenAdminAndPairDomainVary_thenExactAppend], [test][test_whenPairAndCollectionBoundarySeedsUsed] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-P01 | ADMIN | true | true | Append two supported pairs to existing two | Exact events, retain prefix and requested orientation in getter | Covered: [test][test_givenEnabled_whenAdminAddsMultiplePairs] |
| PCACHER-ADD-PAIR-P02 | Fuzz all callers | Fuzz true/false | Fuzz true/false | Arbitrary getter caller before/after mutations in all lifecycle states | Return an exact copy; no writes | Covered: [test][test_whenPairGetterHasArbitraryCallerAndLifecycle] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-ADD-PAIR-L06 | Any address, fuzz, without authorization exclusions | false | false | Task paused, then Kernel-deactivated; existing cache/pair fixture retained; Asset and quote both `address(0)` | `PriceCacherTask_PolicyInactive(task)` before caller, input and dependency checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst] |

[test_givenDisabled_whenAdminAddsPair]: addAssetPair.t.sol#L165
[test_givenEnabled_whenAdminAddsMultiplePairs]: addAssetPair.t.sol#L137
[test_givenInactive_whenPairAdded_reverts]: addAssetPair.t.sol#L237
[test_givenPairExistsInReverseOrder_reverts]: addAssetPair.t.sol#L108
[test_givenPairExists_reverts]: addAssetPair.t.sol#L92
[test_givenReEnabled_whenAdminAddsPair]: addAssetPair.t.sol#L177
[test_whenAdminAndPairDomainVary_thenExactAppend]: addAssetPair.t.sol#L188
[test_whenAssetEqualsQuote_reverts]: addAssetPair.t.sol#L82
[test_whenAssetIsZero_reverts]: addAssetPair.t.sol#L64
[test_whenCallerIsNotAuthorized_reverts]: addAssetPair.t.sol#L21
[test_whenPairAndCollectionBoundarySeedsUsed]: addAssetPair.t.sol#L212
[test_whenPairGetterHasArbitraryCallerAndLifecycle]: addAssetPair.t.sol#L251
[test_whenPairIsNotSupportedByPriceCache_reverts]: addAssetPair.t.sol#L123
[test_whenQuoteIsZero_reverts]: addAssetPair.t.sol#L73
[test_whenPriceAdminAddsPair]: addAssetPair.t.sol#L31
[test_whenBothRolesAddPair]: addAssetPair.t.sol#L39
[test_givenInactive_whenPriceAdminAddsPair_reverts]: addAssetPair.t.sol#L46
[test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst]: ./addAssetPair.t.sol#L291
