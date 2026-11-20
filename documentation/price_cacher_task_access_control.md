# Price Cacher Task Access Control

Ordinary mutations apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authority. Disabled-capable recovery and configuration omit the enabled requirement. Lifecycle transitions retain their inherited checks; disable remains available while inactive.

## Purpose

`PriceCacherTask` is a generic Heart task that refreshes an independently configured set of
`PriceCache` asset pairs. It is not part of Burner Loans, and its pair configuration does not derive
from any consumer or seizure policy.

See [Price Cache](./price_cache.md) for snapshot, freshness, and pair-support behavior.

## Authorities

| Authority   | Expected assignment  | Scope                                    |
| ----------- | -------------------- | ---------------------------------------- |
| `admin`     | OCG Timelock         | Cache reference, pair set, and lifecycle |
| `price_admin` | Delegated price administrator | Add/remove cached pairs and re-enable within grace |
| `emergency` | Emergency Multisig   | Immediate disable                        |
| `heart`     | Olympus Heart policy | Periodic execution                       |
| Contract    | `PriceCacherTask` itself | Isolated task-body execution             |

The target contract does not enforce an admin delay. The expected delay comes from the OCG
Timelock holding `admin`.

## Configuration

Only `admin` can change the cache reference. Either `price_admin` or `admin` can add and remove pairs.
These functions remain callable while
`PriceCacherTask` is enabled or disabled so governance can repair configuration without first changing
the task lifecycle.

Pair management is privileged because it changes recurring Heart work and the intended cache coverage.

| Function          | Authorized caller | Main requirements                                                       |
| ----------------- | ----------------- | ----------------------------------------------------------------------- |
| `setPriceCache`   | `admin`           | Different address, required interfaces, same Kernel, and all pairs supported |
| `addAssetPair`    | `price_admin` or `admin` | Valid, unique pair supported by the current `PriceCache`          |
| `removeAssetPair` | `price_admin` or `admin` | Pair exists in either orientation                                 |

All three setters require the task to remain Kernel-active. Cache compatibility requires
`IPriceCache` and `IEnabler`; it does not require `IVersioned` or query `VERSION()`.
Cache selection permits an inactive or disabled replacement. Readiness is checked on activation.

New deployments start with an empty pair set. After Kernel activation gives `PriceCacherTask` access to
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
| `reEnable`        | `price_admin` or `admin` | Grace window is open and the configured cache remains compatible |
| `setGracePeriod`  | `admin`           | Task is enabled and the period is nonzero                        |
| `execute`         | `heart`           | Task is Kernel-active; disabled task returns without work        |
| `selfExecuteTask` | `PriceCacherTask`     | External callers are rejected                                    |

The task and its configured `PriceCache` must be Kernel-active, and the cache must be enabled,
when `PriceCacherTask` is enabled or re-enabled. Activation rechecks cache compatibility and
reported Kernel before readiness. Missing interfaces produce `PriceCacherTask_InvalidPriceCache`.
Failed or malformed Kernel or enabled-state getters produce `PolicyDependency_InvalidDependency`;
a readable foreign Kernel produces `PolicyDependency_KernelMismatch`.
A compatible paused or inactive cache produces `PolicyDependency_NotActive`.
During execution, the self-call checks cache membership and enablement. An inactive or disabled
cache produces `PolicyDependency_NotActive`.
`execute` catches it, emits `ExecutionFailed`, and returns without work. It resumes after the
cache becomes operational.

Each pair is attempted with `maxAge = 0`. Ordinary per-pair failures emit `PairCacheFailed` and do
not prevent later pairs from being attempted. This includes a pair that was supported when added
but later becomes unsupported by `PRICE`. The outer self-call also contains ordinary aggregate
failures. The task has no configurable gas limit; pathological gas consumption by one attempt can
still prevent later pairs, later Heart tasks, or Heart finalization. Governance must therefore keep
the configured pair set and its external pricing costs operationally bounded.
