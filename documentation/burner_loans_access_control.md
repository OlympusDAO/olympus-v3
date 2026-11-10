# Burner Loans access control

Ordinary mutations apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authority. Disabled-capable recovery and configuration omit the enabled requirement. Lifecycle transitions retain their inherited checks; disable remains available while inactive.

## Purpose

This reference describes the modular contracts and their current authority checks. The [main guide](burner_loans.md) covers the execution graph and deployment order.

`admin` means the Kernel role. OCG governance is its expected holder, but these contracts do not add an OCG delay to a direct admin call. A selected config operator is an address-level delegation. Its own implementation determines whether it adds a delay.

## Delay types

| Path | Delay enforced here |
| --- | --- |
| Direct ADMIN call | None; the ADMIN holder's governance process is separate |
| Selected ordinary config operator | None unless that operator implements a delay |
| Burner Loans config timelocks | The queue's configured notice and execution window |
| `burner_loans_admin` operational recovery | None beyond the function's state and grace checks |
| `emergency` pause or cancellation | None beyond the function's state checks |

A queue does not remove direct ADMIN authority. Revoking a queue as config operator blocks its target calls; it does not erase its queued actions or extend their execution windows.

## Authorities and expected assignments

| Authority | Expected holder or use |
| --- | --- |
| `admin` | OCG governance; selects components and independent configuration operators |
| `burner_loans_admin` | Operational administration, queue proposals, task tuning and bounded re-enablement |
| `backing_admin` | Separate backing-oracle proposals and bounded re-enablement of the oracle and its queue |
| `emergency` | Pauses enabled policies and cancels queued actions |
| `heart` | Calls periodic `execute()` entry points |
| `burner_loans_seizer` | Marks protocol seizure with no keeper reward; required on SeizerTask |
| `burner_loans_inventory_provider` | Supplies OHM and withdraws that provider's available claim |
| Operation-specific settlement roles | Permit Collateral, Debt, Seize and YieldClaimerTask to call the corresponding Core settlements |
| Core config operator | The selected BurnerLoansConfig; also the manager of registered FLOAN markets |
| Config's local config operator | Usually ConfigTimelock for delegated market changes |
| Risk's local config operator | RiskConfigTimelock for delayed referral and cache-age settings; Config remains an alternative for cache-age forwarding |
| Payout's local config operator | Usually PayoutConfigTimelock for flags and recovery |
| Inventory's local config operator | Independently selected surplus-recovery authority |
| Borrower-authorized operator | May act for that borrower until the Core-stored grant expires |

Settlement roles authenticate the caller directly. Core does not additionally require the caller to be an active Policy or report the same Kernel. Assign those roles only to reviewed settlement callers.

## Configuration matrix

| Contract | Function | Authorized caller | Required state or validation |
| --- | --- | --- | --- |
| Core | `setRisk`, `setInventory`, `setPayout` | ADMIN | Core active and idle; compatible candidate active/enabled, same Core and Kernel; additional OHM/accounting checks apply |
| Core | `setConfigOperator` | ADMIN | Core active and idle; nonzero, changed authority; atomic registered-market manager handoff |
| Config | `setConfigOperator` | ADMIN | Config active and enabled; zero revokes delegation |
| Config | `addAsset` | ADMIN | Config active/enabled and downstream custody, price and registration checks pass |
| Config | Asset cap, risk struct, fee struct, origination and withdrawal-mode setters | ADMIN or Config's selected operator | Config active/enabled; function-specific validation and downstream authority apply |
| Config | `setPriceCacheMaxAge` | ADMIN or Config's selected operator | Config active/enabled; Risk active/enabled and independently authorizes Config |
| Risk | `setBackingOracle`, `setPriceCache`, `setConfigOperator` | ADMIN | Risk active; local disablement permitted; compatibility checks apply to addresses |
| Risk | `setPriceCacheMaxAge` | ADMIN or Risk's selected operator | Risk active and enabled; unchanged numeric age is a no-op |
| Risk | `setReferralFeeBps`, `setReferrerAllowed` | ADMIN or Risk's selected operator | Risk active/enabled; percentage 0..10000; nonzero referrer; unchanged values are event-free no-ops |
| BackingOracle | `setBacking` | ADMIN or oracle's selected nonzero operator | Oracle active/enabled; nonzero 18-decimal backing within the current change bounds |
| BackingOracle | `setConfigOperator` | ADMIN | Oracle active; local pause permitted; zero revokes delegation |
| Inventory | `setGlobalDebtCap` | ADMIN | Inventory active/enabled, Core idle; cap covers active principal and approval reconciliation succeeds |
| Inventory | `setConfigOperator` | ADMIN | Inventory active, Core idle; local disablement permitted; zero revokes recovery authority |
| Inventory | `syncMintApproval` | `burner_loans_admin` | Inventory active and enabled |
| Inventory | `burnSurplus` | ADMIN or Inventory's selected operator | Inventory active and enabled; preserves supplied idle OHM |
| Inventory | `rescueSurplus` | ADMIN or Inventory's selected operator | Inventory active; local disablement permitted; preserves supplied idle OHM |
| Payout | `setRevenueDistributor`, `setConfigOperator` | ADMIN | Payout Kernel-active and both settlement guards idle; local Payout pause and replacement permit repair; Core activity/enablement is not checked |
| Payout | Fee/yield flags | ADMIN or Payout's selected operator | Payout Kernel-active and settlement idle; local pause permitted; enabling revalidates the distributor, even for an unchanged true flag |
| SeizerTask | `addAsset`, `removeAsset` | ADMIN | Task Kernel-active; valid managed-set transition; adding requires a configured market |
| SeizerTask | Scan/gas limits and both cursor setters | ADMIN or `burner_loans_admin` | Task Kernel-active; valid limits/indexes; local disablement permitted |
| YieldClaimerTask | Gas limit, attempt threshold, reserve and cursor setters | ADMIN or `burner_loans_admin` | Task Kernel-active; valid limits/index; local disablement permitted |

Core rejects a zero or unchanged config operator. Its operator setter does not inspect the upstream operator's code, interface, Kernel or lifecycle. Config validates its own binding when activated. Risk, Inventory and Payout controllers do not change when Core's controller changes.

Contract pointers generally reject unchanged values. Numeric no-ops retain each setter's existing validation order. Do not assume an unchanged request bypasses authorization or dependency checks.

### FLOAN manager rotation

Core needs the Kernel-granted FLOAN permission to hand off market managers as their facility. FLOAN permits an unchanged market manager as a no-op. See [Replacing Burner Loans Config](burner_loans.md#replacing-burner-loans-config) for the atomic handoff and replacement procedure.

## Config timelock matrix

All four Burner Loans queues accept proposals from ADMIN or `burner_loans_admin`. Anyone can execute a valid queued action during its inclusive execution window. Only `emergency` can cancel through these queues. Cancellation requires the queue active and does not depend on its target remaining usable. All four permit cancellation while locally paused; own Kernel inactivity still blocks it.

| Queue/action | Target and authority | Queue and execution gates |
| --- | --- | --- |
| ConfigTimelock market/risk/fee parameters and Core surplus rescue | Constructor-bound Config; queue selected as Config's local operator | Queue and Config active/enabled; action-specific downstream checks pass |
| RiskConfigTimelock referral percentage, whitelist and cache age | Constructor-bound Risk; queue selected as Risk's local operator | Queue and Risk active/enabled with matching Kernel; Config and Core are not consulted |
| PayoutConfigTimelock flags and surplus/pending recovery | Constructor-bound Payout; queue selected as Payout's local operator | Queue active/enabled and matching Payout Kernel; Payout mutations and recovery previews require Payout active; local Payout pause and Core state do not gate recovery; settlement must be idle |
| InventoryConfigTimelock surplus burn/rescue | Constructor-bound Inventory; queue selected as Inventory's local operator | Queue active/enabled, Inventory active with matching Kernel, Core idle; burning also requires Inventory enabled, rescue permits local Inventory pause |

All four queues use the same enable/reEnable prerequisites: compatible consumed target interfaces, matching Kernel, active target Policy membership and current operator selection. Target local enablement is not required or read during activation. This permits queue repair while its target is paused; the operation-specific gates in the table still apply when queueing or executing.

The separate [BackingOracleConfigTimelock](backing_oracle.md) accepts ADMIN or `backing_admin` proposals, uses a fixed one-day notice and a seven-day inclusive execution window, and has EMERGENCY-only cancellation. Its enable/reEnable checks require the oracle active with matching Kernel, compatible interfaces and current operator selection, but permit the oracle to remain paused. Queueing and execution require both policies active/enabled. Its recovery role is `backing_admin`, not `burner_loans_admin`.

RiskConfigTimelock dispatches directly to Risk. Selecting Config as Risk's operator enables Config's direct cache-age forwarding but does not authorize RiskConfigTimelock's actions. Select the intended route explicitly. Direct ADMIN access on Risk remains available regardless of that selection.

Pausing Config does not stop RiskConfigTimelock. Pause this queue or Risk, revoke Risk's delegation, or cancel the action to stop that route. Pausing the queue still permits emergency cancellation.

RiskConfigTimelock binds one immutable Risk destination. Core selecting another Risk cannot redirect queued actions. Cache age, referral percentage and each referrer's membership have independent keys and commitments to their current value plus selected operator. They can coexist and execute in any order. Direct changes to a committed value make that action stale until the original state is restored. A failed attempt preserves the action and reservations within its original window; expiry alone does not release keys.

PayoutConfigTimelock excludes distributor pointer replacement, including in `queueBatch`. ADMIN must disable both flags before clearing that pointer directly. Fee and yield flags have separate conflict keys.

See [Config Timelock Batch Queue](config_timelock_batch_queue.md) for shared notice, expiry, keys, state hashes and atomic batch behavior.

## Asset-originations control

See [Operating states](burner_loans.md#operating-states) for the effect of the asset origination flag. Local pauses and unavailable dependencies can still block servicing.

## Policy-lifecycle matrix

Core, Collateral, Debt, Seize, Risk, Inventory, Payout, Config, all four config queues and both Burner Loans tasks use the shared enable/disable and re-enable/grace model. Lens has no Kernel lifecycle.

| Transition | Caller | Conditions |
| --- | --- | --- |
| `enable` | ADMIN | Locally disabled; own Kernel activity and concrete dependency checks pass |
| `disable` | ADMIN or `emergency` | Locally enabled; broken dependencies or Kernel deactivation do not by themselves prevent a pause |
| `reEnable` where supported | ADMIN or `burner_loans_admin` | Previously initialized, disabled and within inclusive grace; activation checks pass again |
| `setGracePeriod` where supported | ADMIN | Nonzero period and the component's state/activity checks pass |

Unused lifecycle payloads must be empty. A pause does not clear positions, pending obligations or queue history. An expired fast re-enable window does not remove ADMIN's ordinary `enable` path.

Payout uses a seven-day default grace window measured from its last transition. Its ADMIN-only grace setter requires local enablement and Kernel activity; same-value nonzero updates emit the grace event. Both settlement guards reject lifecycle and grace changes during payouts or Core settlement. Enable and re-enable share Payout's own activity checks, with no Core lifecycle or selection requirement. Recovery stays available while Payout is locally paused or replaced.

## User and automation matrix

| Contract | Entry point | Caller |
| --- | --- | --- |
| Core | Authorization grant/cancellation | Borrower; a valid signed grant can be relayed |
| Collateral | Deposit/withdraw | Borrower or an authorized operator |
| Debt | Borrow/extend | Borrower or an authorized operator |
| Debt | Repay | Any payer using its own OHM |
| Seize | Seize | Any caller; reward depends on keeper identity/roles |
| YieldClaimerTask | `claimYield` | Any caller |
| Payout | Pending discovery and `transferPendingPayout` | Any caller; retries require Kernel activity and permit local pause or replacement |
| Payout | `validatePayoutRecipient` | Any caller; view independent of Kernel activity, enablement and Core state |
| Core | Surplus rescue | Core's selected Config or ADMIN; Core active, local disablement permitted |
| Config | Forward Core surplus rescue | Config's local operator or ADMIN; Config active/enabled and Core recovery checks pass |
| Payout | Surplus and pending-entitlement rescue | Payout's local operator or ADMIN; Payout Kernel-active, local pause/replacement permitted, outside settlement; Core activity/enablement is not checked |
| SeizerTask / YieldClaimerTask | `execute` | `heart`; inactive task reverts, active disabled task returns without work |
| Either task | `selfExecuteTask` | The task itself |

Action previews and Lens reads are permissionless. They retain their applicable input, lifecycle and economic checks. A preview is not a borrower authorization or an executable commitment.

## Limits of each authority

`burner_loans_admin` alone cannot select Core services, add collateral assets, change Inventory's global cap or replace oracle/cache pointers. It can propose supported delayed actions and tune the explicit task controls.

`emergency` alone cannot reopen originations, change economic parameters or enable a policy. ADMIN retains its direct governance routes. A selected operator gains only the entry points delegated by that component.
