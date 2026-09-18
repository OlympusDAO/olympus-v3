# Price Cache

## Purpose

`PriceCache` stores reusable asset/quote snapshots sourced from the installed `PRICE` module. Each
snapshot stores the USD value of both legs, the source timestamp, and a pair-local round ID. A
consumer can use one snapshot throughout an operation instead of repeating the underlying oracle
lookups.

The cache is a generic policy. It is not owned by Burner Loans or by `PriceCacher`.

## Dependencies And Version

`PriceCache` resolves `PRICE` and `ROLES` through their Kernel keycodes. Reconfiguring dependencies
after a `PRICE` module upgrade advances the cache epoch, which invalidates every snapshot written
against the prior module.

PriceCache has not been deployed, so the returned snapshot from `cachePriceIfNecessary` and
`validateAssetPair` are part of version 1.0. Integrations that rely on those behaviors must require
major version 1.

## Supported Pairs

`validateAssetPair(asset, quote)` checks that:

- neither address is zero;
- the asset and quote differ;
- each non-unit leg is approved by the installed `PRICE` module; and
- the amount decimals for both legs can be resolved.

The validation is available while `PriceCache` is inactive or disabled. This allows governance to
prepare dependent policy configuration during an incident or deployment. Validation does not prove
that a future price lookup will succeed; feeds can fail or `PRICE` support can change later.

Contract assets obtain decimals from the token contract. Non-contract asset identifiers require
metadata registered in both `PRICE` and `PriceCache`. Changing or removing non-contract decimals
advances that asset's epoch and invalidates every cached pair containing it.

## Cache Operations

| Function                              | Behavior                                                                 |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `cachePrice(asset, quote)`            | Always reads current `PRICE` values and writes a new pair snapshot       |
| `cachePriceIfNecessary(..., maxAge)`  | Returns the existing snapshot when fresh; otherwise writes and returns it |
| `getCachedPrice(asset, quote)`        | Returns the current-epoch snapshot without refreshing it                 |
| `isStale(asset, quote, maxAge)`       | Reports whether the current-epoch snapshot is absent or too old          |
| `validateAssetPair(asset, quote)`     | Validates support without requiring the policy to be active or enabled   |

Cache writes and cached reads require the policy to be active and enabled. Cache writes are
permissionless because the values can only be sourced from the installed `PRICE` module.

The snapshot timestamp is the older timestamp of the two USD legs. The unit-of-account leg uses the
current block timestamp. A snapshot is stale when it is absent or when:

```text
block.timestamp > updatedAt + maxAge
```

`maxAge = 0` therefore means same-timestamp freshness. Because timestamps have block granularity,
it does not distinguish transaction ordering within one block and does not prove that the caller
created a new oracle observation.

## Consumer Fallback

`PriceCache` does not define fallback behavior. Each consumer decides whether an inactive,
disabled, missing, or stale cache should cause a revert or a direct `PRICE` lookup. Burner Loans,
for example, falls back to `PRICE` for unavailable or stale view reads and refreshes an operational
cache during price-dependent actions.

An error from an otherwise operational cache should normally propagate. Retrying `PRICE` after an
unexpected cache error can hide an invalid pair or integration fault and makes preview/action
behavior harder to reason about.

## Access Control

| Function                                                  | Authorized caller          | State requirement                   |
| --------------------------------------------------------- | -------------------------- | ----------------------------------- |
| `cachePrice`, `cachePriceIfNecessary`                     | Any address                | Policy is active and enabled        |
| `setNonContractAssetMetadata`, `removeNonContractAssetMetadata` | `price_admin` or `admin` | Policy is enabled                   |
| `enable`                                                  | `admin`                    | Policy is disabled                  |
| `disable`                                                 | `admin` or `emergency`     | Policy is enabled                   |
| `validateAssetPair`                                       | Any address                | None                                |

The expected `admin` holder is the OCG Timelock. The contract itself does not impose a delay on an
admin call.

## Periodic Warming

`PriceCacher` is the generic Heart task for warming a governance-configured pair set. It is
documented separately in
[Price Cacher Access Control](./price_cacher_access_control.md).
