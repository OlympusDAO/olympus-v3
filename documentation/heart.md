# Olympus Heart Policy

The Olympus Heart policy orchestrates the core protocol heartbeat. When a keeper calls the `beat` function, the policy updates market data, triggers the distributor rebase, and executes a configured pipeline of periodic tasks before minting any keeper reward. This document outlines the cadence, access control, reward logic, and periodic task management model for the Heart.

## Beat Cadence

The Heart cadence is derived from the moving-average oracle managed by the PRICE module. The policy exposes `frequency()` as a passthrough to the module’s observation frequency, so the heartbeat always aligns with oracle updates. Calling `beat()` before `lastBeat + frequency()` reverts with `Heart_OutOfCycle`, ensuring that successive beats remain spaced by the oracle interval. If a beat is missed, the contract realigns the schedule by setting `lastBeat` to the most recent multiple of the frequency, preventing accumulated backlog.

### Expected Cadence and Recovery

The system currently targets three beats per day (approximately every eight hours), and several downstream contracts assume this cadence. If heartbeats are blocked for an extended period, operators should restore the schedule by calling the admin-only `resetBeat()` to set the last beat in the past, then immediately invoking `beat()` so the protocol catches back up without drifting further.

## Caller Access

Heart beats are permissionless: any externally owned account or contract can call `beat()` when the cycle allows. The policy simply checks that it is enabled and that the required time has elapsed. Administrative controls such as `setRewardAuctionParams`, `setDistributor`, and `resetBeat` remain gated to the DAO’s manager/admin roles via `PolicyAdmin`.

### Resetting the Beat

`resetBeat()` is restricted to addresses with either the `manager` or `admin` role. This function backdates `lastBeat` by exactly one heartbeat interval, allowing a subsequent keeper to call `beat()` immediately without violating the cadence checks.

## Reward Auction

Keeper rewards follow a linear auction that begins at zero once a beat is available. The reward grows until the configured `auctionDuration` elapses, capped at `maxReward`, and is minted in OHM as part of the beat execution.

- `maxReward` and `auctionDuration` are configurable by an admin, with validation that the auction cannot exceed the heartbeat frequency.
- Rewards mint only after all periodic tasks succeed; a failed task reverts the beat and prevents the reward from being issued.

## Periodic Task Pipeline

Heart inherits from `BasePeriodicTaskManager`, which maintains an ordered list of task contracts. Each beat runs `_executePeriodicTasks()`, iterating in order and either calling the default `IPeriodicTask.execute()` or a custom selector per task.

### Current Task Order

Before the periodic tasks, the Heart performs two core actions inside `beat()`:

1. `PRICE.updateMovingAverage()` — refreshes the oracle so downstream logic consumes up-to-date pricing data.
2. `distributor.triggerRebase()` — executes the distributor rebase cycle to maintain supply policy.

Only after those calls succeed does the Heart walk through the periodic task pipeline.

The task ordering as of the execution of `ConvertibleDepositProposal` are:

| Index | Task                          | Selector      | Rationale |
| ----- | ----------------------------- | ------------- | --- |
| 0     | `ConvertibleDepositFacility`  | `execute()`   | Runs facility accounting before any reserve movements so that new deposits/withdrawals are reflected first. |
| 1     | `ReserveMigrator`             | `migrate()`   | Executes pending reserve migrations immediately after facility updates so treasury assets are up to date. |
| 2     | `ReserveWrapper`              | `execute()`   | Wraps reserves after migrations, ensuring downstream consumers see the latest balances. |
| 3     | `Operator`                    | `operate()`   | Applies RBS (Range-Bound Stability) operations once treasury movements settle. |
| 4     | `YieldRepurchaseFacility`     | `endEpoch()`  | Settlement of the yield program happens after the prior three steps, as noted in the activator comments, so the facility sees finalized balances. |
| 5     | `EmissionManager`             | `execute()`   | Updates emission schedules last, incorporating the state changes from the preceding tasks before computing new emission targets. |

### Adding or Reordering Tasks

Only addresses holding the Heart policy’s admin role can modify the task list. The manager exposes two primary helpers:

- `addPeriodicTask(address task)` appends a contract that implements `IPeriodicTask`.
- `addPeriodicTaskAtIndex(address task, bytes4 selector, uint256 index)` inserts at a specific index and optionally supplies a custom function selector.

When supplying a custom selector, ensure the target contract exposes the function publicly and that it is safe to call without arguments. The manager reverts if the selector fails during execution, so prefer using `IPeriodicTask.execute()` unless specialized behavior is required.

To change ordering:

1. Remove the existing entry with `removePeriodicTask(address task)` or `removePeriodicTaskAtIndex(uint256 index)` only when the relative ordering of existing tasks needs to change.
2. Re-add the task with the desired selector and index. You can also insert a new task at a specific index without removing others — the manager shifts the subsequent entries down automatically.
3. If the task contains enablement logic, call the relevant `IEnabler.enable` before scheduling it so the HEART beat does not revert.

### Periodic Task Implementation Notes

- Each task should exit early if its own contract (or any required dependency) is disabled, avoiding unnecessary work.
- Non-critical failure paths should never bubble up as reverts. Prefer guarding the condition ahead of time, returning early, or catching and emitting an event so off-chain alerting can flag the issue without halting the entire heartbeat.

After any modifications, consider extending the governance proposal validation checks (similar to the Convertible Deposit proposal) to assert the intended ordering.

## Operational Checklist

- Never disable or deactivate the current Heart policy unless a replacement Heart contract is already enabled and active; otherwise the protocol loses its heartbeat entirely.
- Monitor the PRICE module’s observation frequency when changing oracle configurations; heartbeat cadence updates automatically.
- Adjust `maxReward` and `auctionDuration` in tandem to reflect keeper incentives, and avoid calling `setRewardAuctionParams` while a beat is available (the function will revert).
- Any new periodic task should either implement `IPeriodicTask` or be invoked through a selector that fails safely. Test the full beat flow to ensure the task cannot cause unexpected reverts.
- Leverage off-chain monitoring such as the [RBS Discord Alerts](https://github.com/OlympusDAO/rbs-discord-alerts/) service to track missed beats and related anomalies.
