# Burner Loans Access Control

## Purpose

This document lists the state-changing access-control paths in the Burner Loans system. It shows the
required caller, the delay, and the contract-state requirements for each function.

This document does not list read-only functions. See [ROLES](../ROLES.md) for the protocol-wide role
catalog and expected role allocations.

The generic `PriceCacher` policy is not part of Burner Loans. Its permissions are documented in
[Price Cacher Access Control](./price_cacher_access_control.md).

## Delay Types

The Burner Loans system uses two different delay mechanisms:

| Delay type            | Enforcement                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------- |
| Burner Loans timelock | `BurnerLoansConfigTimelock` enforces the delay before it calls `BurnerLoansConfig`.          |
| OCG governance        | The expected `admin` holder is the OCG Timelock. The target Burner Loans function is direct. |
| Immediate             | The target function does not enforce a delay.                                                |

The shared queue and Burner Loans validation support delays from 1–30 days. The current
`BurnerLoansConfigTimelock` constructor selects one day and exposes no public delay setter, so its
deployed delay remains one day. A future implementation may expose the inherited internal setter,
subject to the same 1–30 day validation. An action expires three days after its execution time
starts. Any address can execute a valid action during that window.

The `admin` role does not force a delay at the target contract. The delay exists only when the OCG
Timelock holds that role and calls the function through governance.

## Authorities And Expected Assignments

| Authority                         | Expected assignment                          | Scope                                                       |
| --------------------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| `admin`                           | OCG Timelock                                 | Governance configuration, policy enablement, and recovery   |
| `burner_loans_admin`              | Designated Burner Loans operations account   | Queues ConfigTimelock actions and performs bounded recovery |
| `emergency`                       | Emergency Multisig                           | Immediate policy disable and timelock cancellation          |
| `heart`                           | Olympus Heart policy                         | Periodic Seizer and YieldClaimer execution                  |
| `burner_loans_seizer`             | `BurnerLoansSeizer` policy                   | Reward-free protocol seizure                                |
| `burner_loans_inventory_provider` | Designated protocol OHM provider             | Supply OHM and withdraw that provider's available claim     |
| ConfigTimelock                    | `BurnerLoansConfigTimelock`, when configured | Calls the bounded Config setters after a delay              |
| Configurator                      | `BurnerLoansConfig`                          | Configures Burner Loans and Burner Loans Inventory          |
| Facility                          | `BurnerLoans`                                | Changes Inventory principal and funding state               |
| Borrower-authorized operator      | Selected by each borrower                    | Acts for that borrower before the authorization deadline    |

The deployment code in this branch does not define the two designated Burner Loans allocations.
The deployment process must record those addresses before activation.

## Configuration Matrix

An `admin` or selected config operator can call the delegated Config setters. The expected operator
is ConfigTimelock, which adds a delay of at least one day. Direct admin calls follow OCG governance.
Both paths require Config to be enabled; individual setters also validate their target dependencies.

`setConfigOperator` accepts the zero address. Setting it to zero revokes ConfigTimelock access. When
delegated access is enabled, the expected address is `BurnerLoansConfigTimelock`. A different
selected operator may call the same delegated setters without the Burner Loans timelock delay.

| Contract                  | Function                                | Authorized caller               | Delay           | Main state requirements                                                 |
| ------------------------- | --------------------------------------- | ------------------------------- | --------------- | ----------------------------------------------------------------------- |
| `BurnerLoans`             | `setInventory`                          | `admin`                         | OCG governance  | Burner Loans is disabled                                                |
| `BurnerLoans`             | `setConfigurator`                       | `admin`                         | OCG governance  | Burner Loans is disabled; replacement validates and migrates atomically |
| `BurnerLoans`             | `setBackingOracle`                      | `admin`                         | OCG governance  | Burner Loans is enabled                                                 |
| `BurnerLoans`             | `setPriceCache`                         | `admin`                         | OCG governance  | Zero selects PRICE; nonzero cache must be compatible and same-Kernel    |
| `BurnerLoans`             | `setRevenueDistributor`                 | `admin`                         | OCG governance  | Burner Loans enabled and Kernel-active; nonzero distributor enabled, active, compatible, same-Kernel; zero requires both send flags false |
| `BurnerLoansConfig`       | `setFacility`                           | `admin`                         | OCG governance  | Config disabled and Kernel-active; facility active, compatible, same-Kernel; one-time binding               |
| `BurnerLoansConfig`       | `addAsset`                              | `admin`                         | OCG governance  | Config and Burner Loans enabled; custody and PRICE support valid; new market starts with originations on       |
| `BurnerLoansConfig`       | `setGlobalDebtCap`                      | `admin`                         | OCG governance  | Config is enabled                                                       |
| `BurnerLoansConfig`       | `setPriceCacheMaxAge`                   | `admin` or selected operator       | OCG or operator delay | Config and Burner Loans are enabled; a timelocked action also requires its queued pre-state to match |
| `BurnerLoansConfig`       | `setSendFeesToDistributor`              | `admin` or selected operator    | OCG or operator delay | Config and Burner Loans enabled and Kernel-active; enabling requires a nonzero, enabled, active, compatible, same-Kernel distributor |
| `BurnerLoansConfig`       | `setSendYieldToDistributor`             | `admin` or selected operator    | OCG or operator delay | Config and Burner Loans enabled and Kernel-active; enabling requires a nonzero, enabled, active, compatible, same-Kernel distributor |
| `BurnerLoansConfig`       | `setConfigOperator`                     | `admin`                         | OCG governance  | Config is enabled, and zero revokes delegated access                    |
| `BurnerLoansConfig`       | `setAssetDebtCap`                       | `admin` or selected operator       | OCG or operator delay | Config is enabled, and the cap cannot be less than active debt          |
| `BurnerLoansConfig`       | `setAssetRiskConfig`                    | `admin` or selected operator       | OCG or operator delay | Config is enabled, and the asset and values must be valid               |
| `BurnerLoansConfig`       | `setAssetFeeConfig`                     | `admin` or selected operator       | OCG or operator delay | Config is enabled, and the complete fee curve must be valid             |
| `BurnerLoansConfig`       | `setAssetOriginationsEnabled`           | `admin` or selected operator       | OCG or operator delay | Config is enabled, and enabling revalidates asset dependencies          |
| `BurnerLoansConfig`       | `setAssetWithdrawAsShares`              | `admin` or selected operator       | OCG or operator delay | Config is enabled, and DepositManager accepts the withdrawal mode       |
| `BurnerLoansInventory`    | `setConfigurator`                       | `admin`                         | OCG governance  | Inventory is disabled                                                   |
| `BurnerLoansInventory`    | `setGlobalDebtCap`                      | `admin` via `BurnerLoansConfig` | OCG governance  | Config is enabled, and the cap cannot be less than active principal     |
| `BurnerLoansInventory`    | `syncMintApproval`                      | `burner_loans_admin`            | Immediate       | Inventory is enabled                                                    |
| `BurnerLoansInventory`    | `burnSurplus`                           | `admin`                         | OCG governance  | Inventory is enabled                                                    |
| `BurnerLoansInventory`    | `rescueSurplus`                         | `admin`                         | OCG governance  | Inventory is enabled                                                    |
| `BurnerLoansSeizer`       | `addAsset`, `removeAsset`               | `admin`                         | OCG governance  | The asset-list transition must be valid                                 |
| `BurnerLoansSeizer`       | `setScanLimits`, `setExecutionGasLimit` | `admin`                         | OCG governance  | The new limits must be valid                                            |
| `BurnerLoansSeizer`       | `setScanLimits`, `setExecutionGasLimit` | `burner_loans_admin`            | Immediate       | The new limits must be valid                                            |
| `BurnerLoansYieldClaimer` | `setExecutionGasLimit`                  | `admin`                         | OCG governance  | The gas limit must be nonzero                                           |
| `BurnerLoansYieldClaimer` | `setExecutionGasLimit`                  | `burner_loans_admin`            | Immediate       | The gas limit must be nonzero                                           |
| `BurnerLoansYieldClaimer` | `setMinimumGasToAttempt`                | `admin`                         | OCG governance  | The threshold must exceed the cleanup reserve; callable while locally disabled or Kernel-inactive |
| `BurnerLoansYieldClaimer` | `setMinimumGasToAttempt`                | `burner_loans_admin`            | Immediate       | The threshold must exceed the cleanup reserve; callable while locally disabled or Kernel-inactive |
| `BurnerLoansYieldClaimer` | `setGasReserve`                         | `admin`                         | OCG governance  | The reserve must be at least 100,000 gas and below the threshold; callable while locally disabled or Kernel-inactive |
| `BurnerLoansYieldClaimer` | `setGasReserve`                         | `burner_loans_admin`            | Immediate       | The reserve must be at least 100,000 gas and below the threshold; callable while locally disabled or Kernel-inactive |
| `BurnerLoansYieldClaimer` | `setNextAssetIndex`                     | `admin`                         | OCG governance  | Zero resets the cursor; nonzero must be below the live registry count; callable while locally disabled or Kernel-inactive |
| `BurnerLoansYieldClaimer` | `setNextAssetIndex`                     | `burner_loans_admin`            | Immediate       | Zero resets the cursor; nonzero must be below the live registry count; callable while locally disabled or Kernel-inactive |

`burner_loans_admin` cannot add a market or call a Config setter directly. It can queue only the
supported Config changes through `BurnerLoansConfigTimelock`.

### FLOAN Manager Rotation

`FLOAN.setMarketManager` has two independent checks. The caller must have the Kernel permission for
that selector and must be either the market's current manager or its current facility. The
manager-or-facility identity check does not apply to other FLOAN market setters; they remain
current-manager-only.

Burner Loans requests only the `setMarketManager` selector for configuration migration. Its facility
authority is reachable through `BurnerLoans.setConfigurator`, which remains `admin`-only and
disabled-state-only. See [Replacing Burner Loans Config](./burner_loans.md#replacing-burner-loans-config)
for the complete migration procedure and rollback guarantees.

## Config Timelock Matrix

“Both policies” below means ConfigTimelock and Config. Each action also checks its target inputs;
rescue previews require Burner Loans Kernel-active even at queue time, while allowing local disablement.

| Function                        | Authorized caller               | Delay     | Main state requirements                                                                  |
| ------------------------------- | ------------------------------- | --------- | ---------------------------------------------------------------------------------------- |
| `queueSetAssetFeeConfig`        | `admin` or `burner_loans_admin` | >= 1 day  | Both policies are Kernel-active and enabled; the timelock is the current config operator |
| `queueSetAssetDebtCap`          | `admin` or `burner_loans_admin` | >= 1 day  | Both policies are Kernel-active and enabled; the timelock is the current config operator |
| `queueSetAssetRiskConfig`       | `admin` or `burner_loans_admin` | >= 1 day  | Both policies are Kernel-active and enabled; the timelock is the current config operator |
| `queueSetPriceCacheMaxAge`      | `admin` or `burner_loans_admin` | >= 1 day  | Both policies are Kernel-active and enabled; the timelock is the current config operator |
| `queueSetAssetWithdrawAsShares` | `admin` or `burner_loans_admin` | >= 1 day  | Both policies are Kernel-active and enabled; the timelock is the current config operator |
| `queueSetSendFeesToDistributor`, `queueSetSendYieldToDistributor` | `admin` or `burner_loans_admin` | >= 1 day | Both policies enabled and Kernel-active; selected operator; enabling validates the distributor |
| `queueRescue`, `queueRescuePendingPayout` | `admin` or `burner_loans_admin` | >= 1 day | Both policies enabled and Kernel-active; selected operator; Burner Loans Kernel-active, enabled or disabled |
| `queueBatch`                    | `admin` or `burner_loans_admin` | >= 1 day  | The same lifecycle gates apply and every sub-action passes its queue-time checks         |
| `executeQueuedAction`           | Any address                     | >= 1 day  | Action ready and unexpired; both policies enabled and Kernel-active; timelock remains selected; live target checks pass            |
| `cancelQueuedAction`            | `emergency`                     | Immediate | Unfinished action; ConfigTimelock enabled and Kernel-active; Config state and operator selection do not gate cancellation |

`queueBatch` supports these Config functions:

| Supported Config function     |
| ----------------------------- |
| `setAssetDebtCap`             |
| `setAssetRiskConfig`          |
| `setAssetFeeConfig`           |
| `setAssetOriginationsEnabled` |
| `setPriceCacheMaxAge`         |
| `setAssetWithdrawAsShares`    |
| `setSendFeesToDistributor`    |
| `setSendYieldToDistributor`   |
| `rescue`                      |
| `rescuePendingPayout`          |

The typed queue helpers cover debt-cap, risk, fee, PriceCache max-age, withdrawal-output, both
send flags, and both rescues. Asset-originations changes use `queueBatch`. Revenue allocations are
configured on [Revenue Distributor](revenue_distributor_access_control.md).

Each queued configuration key records its expected pre-state. Execution fails if that pre-state
changes before execution. A stale action does not block an unrelated action.

The fee, risk, debt-cap, origination, and withdrawal-mode actions use separate per-asset domains.
The PriceCache max-age action and each distributor send flag use separate global domains. Every
queued state hash is scoped to the selected Config address and binds its facility and relevant
configuration. Surplus rescue uses a separate token key; pending rescue uses a token/recipient key,
so different recipients can be queued concurrently. Rescue hashes bind only the facility: balances
and entitlements are checked live. Live debt is checked when a debt-cap action executes, so ordinary
repayments and borrows do not make that action stale.

Disablement or Kernel deactivation of ConfigTimelock blocks queueing, execution, and cancellation.
Config disablement or deactivation blocks queueing and execution. Existing actions and their
execution windows remain unchanged. After restoration, an unexpired action can execute if the
operator, expected state, and live inputs remain valid. Emergency must cancel unwanted actions
while ConfigTimelock is enabled and Kernel-active.

## Asset-Originations Control

`addAsset` creates a new market with originations enabled. Only `admin` can add a market.
ConfigTimelock cannot add a market.

`setAssetOriginationsEnabled` uses the same authority for both values. ConfigTimelock can
disable or enable originations through the Burner Loans timelock. Enabling also revalidates PRICE
and DepositManager dependencies.

The `emergency` role cannot change one asset's origination state. It can immediately disable a
policy when an incident requires a strict pause.

| Action              | Originations enabled | Originations disabled | Burner Loans disabled |
| ------------------- | -------------------- | --------------------- | --------------------- |
| Deposit collateral  | Allowed              | Blocked               | Blocked               |
| Borrow              | Allowed              | Blocked               | Blocked               |
| Extend maturity     | Allowed              | Blocked               | Blocked               |
| Repay               | Allowed              | Allowed               | Blocked               |
| Withdraw collateral | Allowed              | Allowed               | Blocked               |
| Seize               | Allowed              | Allowed               | Blocked               |
| Claim yield         | Allowed              | Allowed               | Blocked               |
| Retry pending payout | Allowed             | Allowed               | Blocked               |
| Authorized rescue   | Allowed              | Allowed               | Allowed               |

## Policy-Lifecycle Matrix

`enable` and `disable` are direct policy calls. They do not use `BurnerLoansConfigTimelock`.

| Policy                                                                                                                                  | Function         | Authorized caller    | Delay          | Main state requirements                                          |
| --------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | -------------------- | -------------- | ---------------------------------------------------------------- |
| `BurnerLoans`, `BurnerLoansConfig`, `BurnerLoansConfigTimelock`, `BurnerLoansInventory`, `BurnerLoansSeizer`, `BurnerLoansYieldClaimer` | `enable`         | `admin`              | OCG governance | The policy is disabled and its dependency checks pass            |
| `BurnerLoans`, `BurnerLoansConfig`, `BurnerLoansConfigTimelock`, `BurnerLoansInventory`, `BurnerLoansSeizer`, `BurnerLoansYieldClaimer` | `disable`        | `admin`              | OCG governance | The policy is enabled                                            |
| `BurnerLoans`, `BurnerLoansConfig`, `BurnerLoansConfigTimelock`, `BurnerLoansInventory`, `BurnerLoansSeizer`, `BurnerLoansYieldClaimer` | `disable`        | `emergency`          | Immediate      | The policy is enabled                                            |
| `BurnerLoans`                                                                                                                           | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoans`                                                                                                                           | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoansConfig`                                                                                                                     | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoansConfig`                                                                                                                     | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoansConfigTimelock`                                                                                                             | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoansConfigTimelock`                                                                                                             | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoansInventory`                                                                                                                  | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoansInventory`                                                                                                                  | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoansSeizer`                                                                                                                     | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoansSeizer`                                                                                                                     | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoansYieldClaimer`                                                                                                               | `reEnable`       | `admin`              | OCG governance | The policy was enabled before, and the grace window remains open |
| `BurnerLoansYieldClaimer`                                                                                                               | `reEnable`       | `burner_loans_admin` | Immediate      | The policy was enabled before, and the grace window remains open |
| `BurnerLoans`, `BurnerLoansConfig`, `BurnerLoansConfigTimelock`, `BurnerLoansInventory`, `BurnerLoansSeizer`, `BurnerLoansYieldClaimer` | `setGracePeriod` | `admin`              | OCG governance | The policy is enabled and the period is nonzero                  |

The six policies are `BurnerLoans`, `BurnerLoansConfig`, `BurnerLoansConfigTimelock`,
`BurnerLoansInventory`, `BurnerLoansSeizer`, and `BurnerLoansYieldClaimer`.

Each policy revalidates its required dependencies before re-enabling.

## User And Automation Matrix

These entry points do not impose a delay. Admin calls follow the admin role holder's governance delay;
a selected Config operator may itself be a timelock.

| Contract                  | Function                                   | Authorized caller                           | Main state requirements                                    |
| ------------------------- | ------------------------------------------ | ------------------------------------------- | ---------------------------------------------------------- |
| `BurnerLoans`             | `setAuthorization`                         | The borrower                                | The authorization deadline is not expired                  |
| `BurnerLoans`             | `setAuthorizationWithSig`                  | Any relayer with a valid borrower signature | The signature and authorization deadlines are not expired  |
| `BurnerLoans`             | `cancelAuthorization`                      | The borrower                                | None                                                       |
| `BurnerLoans`             | `depositCollateral`                        | Borrower or borrower-authorized operator    | Burner Loans and asset originations are enabled            |
| `BurnerLoans`             | `withdrawCollateral`                       | Borrower or borrower-authorized operator    | Burner Loans is enabled, and asset originations can be off |
| `BurnerLoans`             | `borrow`                                   | Borrower or borrower-authorized operator    | Burner Loans and asset originations are enabled            |
| `BurnerLoans`             | `extend`                                   | Borrower or borrower-authorized operator    | Burner Loans and asset originations are enabled            |
| `BurnerLoans`             | `repay`                                    | Any address                                 | Burner Loans and Inventory are enabled                     |
| `BurnerLoans`             | `seize`                                    | Any address                                 | Burner Loans, Inventory, and custody are enabled           |
| `BurnerLoans`             | `claimYield`                               | Any address                                 | Burner Loans is enabled                                    |
| `BurnerLoans`             | `transferPendingPayout`                    | Any address                                 | Enabled and Kernel-active                                   |
| `BurnerLoans`             | `rescue`, `rescuePendingPayout` | Bound Config or `admin` | Burner Loans Kernel-active; local disablement allowed |
| `BurnerLoansConfig`       | `rescue`, `rescuePendingPayout` | `admin` or selected config operator | Config enabled and Kernel-active; Burner Loans Kernel-active, with local disablement allowed |
| `BurnerLoansInventory`    | `supply`, `withdraw`                       | `burner_loans_inventory_provider`           | Inventory is enabled                                       |
| `BurnerLoansInventory`    | `draw`, `settleRepayment`, `recordDefault` | Exact Burner Loans facility address         | Inventory is enabled                                       |
| `BurnerLoansSeizer`       | `execute`                                  | `heart`                                     | A disabled Seizer returns without work                     |
| `BurnerLoansSeizer`       | `selfExecuteTask`                          | The Seizer contract itself                  | Called by `execute`                                        |
| `BurnerLoansYieldClaimer` | `execute`                                  | `heart`                                     | A Kernel-inactive or disabled YieldClaimer returns without work |
| `BurnerLoansYieldClaimer` | `selfExecuteTask`                          | The YieldClaimer contract itself            | Skips while Burner Loans is Kernel-inactive or disabled    |

A direct permissionless seizure can receive the configured keeper reward. A caller with `heart` or
`burner_loans_seizer` receives no product keeper reward. The Seizer policy must hold
`burner_loans_seizer` before its automated call can proceed.

## Limits Of Each Authority

These limits describe each role alone. Additional roles or selection as config operator can grant
other access.

| Authority                    | Access limit                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `burner_loans_admin`         | Cannot add assets, change the global cap, rotate the backing oracle, change policy links, or bypass ConfigTimelock |
| `emergency`                  | Cannot change parameters, add assets, enable asset originations, or enable a policy                                |
| `heart`                      | Cannot change parameters and can call only configured periodic task entry points                                   |
| ConfigTimelock               | Cannot call functions outside the delegated Config surface                                                         |
| Borrower-authorized operator | Cannot change protocol configuration or another borrower's position                                                |
| Permissionless caller        | Can repay, seize, claim yield, retry pending payouts, relay a signed authorization, and execute valid queued actions                |

If ConfigTimelock or Config is disabled or Kernel-inactive, `admin` can rescue directly on
`BurnerLoans`. Burner Loans must remain Kernel-active; it may be locally disabled. This direct
path does not consume a queued action or bypass any token, destination, or entitlement checks.
