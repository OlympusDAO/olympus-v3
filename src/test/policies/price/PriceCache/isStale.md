# PriceCache.isStale coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-STALE`.

Permissionless active/enabled view. Let U=updatedAt and A=maxAge in seconds (uint48).
Stale iff U=0 or block.timestamp>uint256(U)+uint256(A); equality is fresh. Validation
precedes staleness. This view does not refresh, change round IDs or read live USD prices.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-STALE-L01 | Any caller | true | false | Paused policy | NotEnabled() | Covered: [test][test_whenPolicyDisabled_reverts] |
| PCACHE-STALE-L02 | Any caller | false | true | Inactive policy | PriceCache_PolicyNotActive() | Covered: [test][test_whenPolicyIsDeactivated_reverts] |
| PCACHE-STALE-L03 | Fuzz all callers | true | true | After reEnable/reactivation | Return model-consistent staleness; preserve stored snapshot | Covered: [test][test_givenReEnabled_whenStalenessQueried], [test][test_givenReactivated_whenStalenessQueried] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-STALE-I01 | Fuzz all callers | true | true | Asset=0 | PriceCache_InvalidPair(0,quote) | Covered: [test][test_whenAssetZero_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-STALE-N01 | Fuzz all callers | true | true | Fuzz full maxAge 0..MAX48 and now=U..U+A | false, including exact deadline | Covered: [test][test_whenFullUint48AgeIsFresh], [test][test_whenAgeBoundarySeeds] |
| PCACHE-STALE-N02 | Fuzz all callers | true | true | Fuzz full nonempty stale interval now>U+A | true | Covered: [test][test_whenFullUint48AgeIsStale], [test][test_whenAgeBoundarySeeds] |
| PCACHE-STALE-N03 | Fuzz all callers | true | true | A=0,1,MAX48; now=U,U+A,U+A+1 | Exact boolean; no overflow of widened addition | Covered: [test][test_whenAgeBoundarySeeds] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-STALE-P01 | Any caller | true | true | No snapshot | true | Covered: [test][test_whenNoSnapshotExists_returnsTrue] |
| PCACHE-STALE-P02 | Any caller | true | true | Module replacement invalidates snapshot | true | Covered: [test][test_whenPRICEModuleIsUpgraded_returnsTrue] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-STALE-I02 | Fuzz all callers | true | true | Quote=0 | PriceCache_InvalidPair(asset,0) | Covered: [test][test_whenQuoteZero_reverts] |
| PCACHE-STALE-I03 | Fuzz all callers | true | true | Asset equals quote | PriceCache_InvalidPair(asset,asset) | Covered: [test][test_whenSamePair_reverts] |
| PCACHE-STALE-I04 | Fuzz all callers | true | true | Asset unapproved | PRICE_AssetNotApproved(asset) | Covered: [test][test_whenAssetUnapproved_reverts] |
| PCACHE-STALE-I05 | Fuzz all callers | true | true | Quote unapproved | PRICE_AssetNotApproved(quote) | Covered: [test][test_whenQuoteUnapproved_reverts] |
| PCACHE-STALE-I06 | Fuzz all callers | true | true | Approved non-contract asset lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_whenAssetMetadataMissing_reverts] |
| PCACHE-STALE-I07 | Fuzz all callers | true | true | Approved non-contract quote lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(quote) | Covered: [test][test_whenQuoteMetadataMissing_reverts] |

[test_whenPolicyDisabled_reverts]: isStale.t.sol#L40
[test_whenPolicyIsDeactivated_reverts]: isStale.t.sol#L116
[test_givenReEnabled_whenStalenessQueried]: isStale.t.sol#L243
[test_givenReactivated_whenStalenessQueried]: isStale.t.sol#L254
[test_whenAssetZero_reverts]: isStale.t.sol#L126
[test_whenFullUint48AgeIsFresh]: isStale.t.sol#L213
[test_whenAgeBoundarySeeds]: isStale.t.sol#L267
[test_whenFullUint48AgeIsStale]: isStale.t.sol#L231
[test_whenNoSnapshotExists_returnsTrue]: isStale.t.sol#L51
[test_whenPRICEModuleIsUpgraded_returnsTrue]: isStale.t.sol#L57
[test_whenQuoteZero_reverts]: isStale.t.sol#L139
[test_whenSamePair_reverts]: isStale.t.sol#L152
[test_whenAssetUnapproved_reverts]: isStale.t.sol#L165
[test_whenQuoteUnapproved_reverts]: isStale.t.sol#L174
[test_whenAssetMetadataMissing_reverts]: isStale.t.sol#L183
[test_whenQuoteMetadataMissing_reverts]: isStale.t.sol#L198
