# Price Cacher Access Control

## Purpose

`PriceCacher` is a generic Heart task that refreshes an independently configured set of
`PriceCache` asset pairs. It is not part of Burner Loans, and its pair configuration does not derive
from any consumer or seizure policy.

See [Price Cache](./price_cache.md) for snapshot, freshness, and pair-support behavior.

## Authorities

| Authority   | Expected assignment  | Scope                                    |
| ----------- | -------------------- | ---------------------------------------- |
| `admin`     | OCG Timelock         | Cache reference, pair set, and lifecycle |
| `emergency` | Emergency Multisig   | Immediate disable                        |
| `heart`     | Olympus Heart policy | Periodic execution                       |
| Contract    | `PriceCacher` itself | Isolated task-body execution             |

The target contract does not enforce an admin delay. The expected delay comes from the OCG
Timelock holding `admin`.

## Configuration

Only `admin` can change the cache reference or pair set. These functions remain callable while
`PriceCacher` is enabled or disabled so governance can repair configuration without first changing
the task lifecycle.

There is no useful permissionless configuration path: adding pairs increases recurring Heart work,
and removing pairs can suppress intended cache warming. Both decisions are governance policy.

| Function          | Authorized caller | Main requirements                                                       |
| ----------------- | ----------------- | ----------------------------------------------------------------------- |
| `setPriceCache`   | `admin`           | Major version 1, required interfaces, same Kernel, and all pairs supported |
| `addAssetPair`    | `admin`           | Valid, unique pair supported by the current `PriceCache`                |
| `removeAssetPair` | `admin`           | Exact pair exists                                                       |

New deployments start with an empty pair set. After Kernel activation gives `PriceCacher` access to
`ROLES`, OCG admin adds the intended pairs before enabling the task. Each addition validates support
through `PriceCache.validateAssetPair`, and cache rotation validates every configured pair. Removal
intentionally does not revalidate support, so governance can remove a pair after `PRICE` support or
token metadata changes.

Additions append pairs to the execution order. Removal swaps in the final entry, so it may reorder
the remaining pairs. The final pair may be removed, leaving an empty periodic configuration.

## Lifecycle And Execution

| Function          | Authorized caller | Main requirements                                                |
| ----------------- | ----------------- | ---------------------------------------------------------------- |
| `enable`          | `admin`           | Task is disabled and the configured cache remains compatible     |
| `disable`         | `admin`           | Task is enabled                                                  |
| `disable`         | `emergency`       | Task is enabled                                                  |
| `reEnable`        | `admin`           | Grace window is open and the configured cache remains compatible |
| `setGracePeriod`  | `admin`           | Task is enabled and the period is nonzero                        |
| `execute`         | `heart`           | Disabled task returns without work                               |
| `selfExecuteTask` | `PriceCacher`     | External callers are rejected                                    |

The configured `PriceCache` does not need to be active or enabled when `PriceCacher` is enabled.
`execute` returns without work while the cache is inactive or disabled, then resumes after the
cache becomes operational.

Each pair is attempted with `maxAge = 0`. Ordinary per-pair failures emit `PairCacheFailed` and do
not prevent later pairs from being attempted. This includes a pair that was supported when added
but later becomes unsupported by `PRICE`. The outer self-call also contains ordinary aggregate
failures. The task has no configurable gas limit; pathological gas consumption by one attempt can
still prevent later pairs, later Heart tasks, or Heart finalization. Governance must therefore keep
the configured pair set and its external pricing costs operationally bounded.
