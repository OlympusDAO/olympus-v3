# Revenue Distributor access control

`admin` is expected to be delayed OCG governance. `revenue_distributor_admin` proposes timelock
changes and manages the periodic task; it has no direct distributor configuration or rescue access
unless separately selected as operator. `emergency` can disable policies and cancel queued actions.
`heart` runs the task. Check live assignments before enabling receipts.

A selected operator can be any address, including an EOA. Selecting the config timelock adds its
delay to operator calls; direct admin calls follow the admin holder's governance delay.
See [contract linkages](revenue_distributor.md#contract-linkages) and
[Burner Loans access control](burner_loans_access_control.md) for source-policy permissions.

Ordinary mutations apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authority. Disabled-capable recovery and configuration omit the enabled requirement. Lifecycle transitions retain their inherited checks; disable remains available while inactive.

## RevenueDistributor

| Function | Caller | Requirements and effect |
| --- | --- | --- |
| `setConfigOperator` | Admin | Kernel-active; enabled or disabled. Selects an operator immediately; zero revokes delegation. |
| `setAssetRoutes`, `disableAssetRoutes` | Admin or selected operator | Enabled and Kernel-active; validates the requested route. |
| `setYieldRecipient` | ADMIN only | Enabled and Kernel-active; validates the global recipient. |
| `distribute` | Anyone | Enabled, Kernel-active, active asset route; allocates new receipts and retries current destinations. |
| `transferPendingPayout` | Anyone | Enabled and Kernel-active; retries the recipient's combined debt, including for retired assets. |
| `rescue`, `rescuePendingPayout` | Admin or selected operator | Kernel-active; local disablement allowed. Sweeps never-listed tokens or redirects existing debt. |

Admin can rescue directly when the selected timelock is disabled or Kernel-inactive. Kernel
deactivation of the distributor blocks rescue and its previews until reactivation.

## RevenueDistributorConfigTimelock

Queueing and execution require this timelock to be enabled, Kernel-active, and the selected operator.
Route configuration also requires the distributor enabled and Kernel-active. Rescue
requires the distributor Kernel-active but permits its local disablement.

| Function | Caller | Requirements and effect |
| --- | --- | --- |
| `queueSetAssetRoutes`, `queueDisableAssetRoutes` | Admin or revenue distributor admin | Validates configuration and starts the delay. |
| `queueRescue`, `queueRescuePendingPayout` | Admin or revenue distributor admin | Validates the rescue preview and starts the delay. |
| `queueBatch` | Admin or revenue distributor admin | Applies the same gates and each action's checks; acquires nonconflicting keys. |
| `executeQueuedAction` | Anyone | Ready, unexpired action; rechecks current state and executes atomically. |
| `cancelQueuedAction` | Recorded proposer or current `emergency` holder | Unfinished action; this timelock Kernel-active, including while locally disabled. The proposer retains cancellation authority after losing its queueing role. No target/operator reads. |

The shared queue and Revenue Distributor validation support delays from 1–30 days. The current
`RevenueDistributorConfigTimelock` constructor selects one day and exposes no public delay setter;
a future implementation may expose the inherited internal setter within the same bounds. The delay
is followed by a three-day execution window. During a local pause, the recorded proposer and
`emergency` can still cancel. Kernel deactivation blocks queueing, execution, and cancellation.
Existing actions remain queued and time continues to pass;
restoration allows retry only within the original execution window.

Route changes, retirement, and rescues conflict on the same asset key. Global yield-recipient
replacement is ADMIN-only and has no typed or generic queue path. Every state hash includes the current config operator alongside its relevant configuration; rescue rechecks live availability
without binding balances at queue time. A failed execution retains its action and keys. See
[configuration and timelock](revenue_distributor.md#configuration-and-timelock).

## RevenueDistributorTask

| Function | Caller | Requirements and effect |
| --- | --- | --- |
| `execute` | Heart | An inactive task reverts. An active disabled task, or an unavailable distributor, produces no work; otherwise attempts active assets within its gas budget. |
| `selfExecuteTask` | Task itself | Internal execution path reached through `execute`. |
| `setExecutionGasLimit`, `setMinimumGasToAttempt`, `setGasReserve` | Admin or revenue distributor admin | Task Kernel-active; local disablement allowed. Validates gas settings. |
| `setNextAssetIndex` | Admin or revenue distributor admin | Task Kernel-active; local disablement allowed. Zero or an index in the active asset set. |

## Policy lifecycle

These functions apply to the distributor, its config timelock, and its task.

| Function | Caller | Requirements |
| --- | --- | --- |
| `enable` | Admin | Locally disabled; dependency checks pass. |
| `disable` | Admin or emergency | Locally enabled. |
| `reEnable` | Admin or revenue distributor admin | Previously enabled, now disabled, within the grace period; dependency checks pass. |
| `setGracePeriod` | Admin | Locally enabled; nonzero period. |

The initial grace period is seven days. Timelock enablement and re-enablement require compatible consumed interfaces, the same Kernel, active distributor membership and selection as its config operator. They do not read or require distributor enablement, so the queue can be repaired while the distributor remains paused. Task enablement and
re-enablement require its distributor enabled and Kernel-active. Local enablement does not activate
a policy in the Kernel; Kernel membership remains an independent operational gate.
