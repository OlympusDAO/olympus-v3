# Burner Loans Access Control

## Purpose

This document lists the state-changing access-control paths in the Burner Loans system. It shows the
required caller, the delay, and the contract-state requirements for each function.

This document does not list read-only functions. See [ROLES](../ROLES.md) for the protocol-wide role
catalog and expected role allocations.

## Delay Types

The Burner Loans system uses two different delay mechanisms:

| Delay type            | Enforcement                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------- |
| Burner Loans timelock | `BurnerLoansConfigTimelock` enforces the delay before it calls `BurnerLoansConfig`.          |
| OCG governance        | The expected `admin` holder is the OCG Timelock. The target Burner Loans function is direct. |
| Immediate             | The target function does not enforce a delay.                                                |

The Burner Loans timelock has a minimum delay of one day. An action expires three days after its
execution time starts. Any address can execute a valid action during that window.

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

An `admin` can call the delegated Config setters directly through OCG governance. ConfigTimelock
can call the same setters after a delay of at least one day. Both paths require Config to be
enabled.

`setConfigOperator` accepts the zero address. Setting it to zero revokes ConfigTimelock access. When
delegated access is enabled, the expected address is `BurnerLoansConfigTimelock`.

| Contract                  | Function                                | Authorized caller               | Delay          | Main state requirements                                                 |
| ------------------------- | --------------------------------------- | ------------------------------- | -------------- | ----------------------------------------------------------------------- |
| `BurnerLoans`             | `setInventory`                          | `admin`                         | OCG governance | Burner Loans is disabled                                                |
| `BurnerLoans`             | `setConfigurator`                       | `admin`                         | OCG governance | Burner Loans is disabled; replacement validates and migrates atomically |
| `BurnerLoans`             | `setBackingOracle`                      | `admin`                         | OCG governance | Burner Loans is enabled                                                 |
| `BurnerLoansConfig`       | `setFacility`                           | `admin`                         | OCG governance | Config is disabled, and the facility can be set only once               |
| `BurnerLoansConfig`       | `addAsset`                              | `admin`                         | OCG governance | Config is enabled, and the new market starts with originations on       |
| `BurnerLoansConfig`       | `setGlobalDebtCap`                      | `admin`                         | OCG governance | Config is enabled                                                       |
| `BurnerLoansConfig`       | `setConfigOperator`                     | `admin`                         | OCG governance | Config is enabled, and zero revokes delegated access                    |
| `BurnerLoansConfig`       | `setAssetDebtCap`                       | `admin`                         | OCG governance | Config is enabled, and the cap cannot be less than active debt          |
| `BurnerLoansConfig`       | `setAssetDebtCap`                       | ConfigTimelock                  | >= 1 day       | Config is enabled, and the cap cannot be less than active debt          |
| `BurnerLoansConfig`       | `setAssetRiskConfig`                    | `admin`                         | OCG governance | Config is enabled, and the asset and values must be valid               |
| `BurnerLoansConfig`       | `setAssetRiskConfig`                    | ConfigTimelock                  | >= 1 day       | Config is enabled, and the asset and values must be valid               |
| `BurnerLoansConfig`       | `setAssetFeeConfig`                     | `admin`                         | OCG governance | Config is enabled, and the complete fee curve must be valid             |
| `BurnerLoansConfig`       | `setAssetFeeConfig`                     | ConfigTimelock                  | >= 1 day       | Config is enabled, and the complete fee curve must be valid             |
| `BurnerLoansConfig`       | `setAssetOriginationsEnabled`           | `admin`                         | OCG governance | Config is enabled, and enabling revalidates asset dependencies          |
| `BurnerLoansConfig`       | `setAssetOriginationsEnabled`           | ConfigTimelock                  | >= 1 day       | Config is enabled, and enabling revalidates asset dependencies          |
| `BurnerLoansConfig`       | `setYieldRepurchaseRecipient`           | `admin`                         | OCG governance | Config and Burner Loans are enabled                                     |
| `BurnerLoansConfig`       | `setYieldRepurchaseRecipient`           | ConfigTimelock                  | >= 1 day       | Config and Burner Loans are enabled                                     |
| `BurnerLoansConfig`       | `setYieldAssetRouting`                  | `admin`                         | OCG governance | Config and Burner Loans are enabled                                     |
| `BurnerLoansConfig`       | `setYieldAssetRouting`                  | ConfigTimelock                  | >= 1 day       | Config and Burner Loans are enabled                                     |
| `BurnerLoansInventory`    | `setConfigurator`                       | `admin`                         | OCG governance | Inventory is disabled                                                   |
| `BurnerLoansInventory`    | `setGlobalDebtCap`                      | `admin` via `BurnerLoansConfig` | OCG governance | Config is enabled, and the cap cannot be less than active principal     |
| `BurnerLoansInventory`    | `syncMintApproval`                      | `burner_loans_admin`            | Immediate      | Inventory is enabled                                                    |
| `BurnerLoansInventory`    | `burnSurplus`                           | `admin`                         | OCG governance | Inventory is enabled                                                    |
| `BurnerLoansInventory`    | `rescueSurplus`                         | `admin`                         | OCG governance | Inventory is enabled                                                    |
| `BurnerLoansSeizer`       | `addAsset`, `removeAsset`               | `admin`                         | OCG governance | The asset-list transition must be valid                                 |
| `BurnerLoansSeizer`       | `setScanLimits`, `setExecutionGasLimit` | `admin`                         | OCG governance | The new limits must be valid                                            |
| `BurnerLoansSeizer`       | `setScanLimits`, `setExecutionGasLimit` | `burner_loans_admin`            | Immediate      | The new limits must be valid                                            |
| `BurnerLoansYieldClaimer` | `setExecutionGasLimit`                  | `admin`                         | OCG governance | The gas limit must be nonzero                                           |
| `BurnerLoansYieldClaimer` | `setExecutionGasLimit`                  | `burner_loans_admin`            | Immediate      | The gas limit must be nonzero                                           |

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

| Function                  | Authorized caller               | Delay     | Main state requirements                                                             |
| ------------------------- | ------------------------------- | --------- | ----------------------------------------------------------------------------------- |
| `queueSetAssetFeeConfig`  | `admin` or `burner_loans_admin` | >= 1 day  | Timelock and Config are enabled, and this timelock is the configured ConfigTimelock |
| `queueSetAssetDebtCap`    | `admin` or `burner_loans_admin` | >= 1 day  | Timelock and Config are enabled, and this timelock is the configured ConfigTimelock |
| `queueSetAssetRiskConfig` | `admin` or `burner_loans_admin` | >= 1 day  | Timelock and Config are enabled, and this timelock is the configured ConfigTimelock |
| `queueBatch`              | `admin` or `burner_loans_admin` | >= 1 day  | Every sub-action must pass its queue-time checks                                    |
| `executeQueuedAction`     | Any address                     | >= 1 day  | The action is executable and unexpired, and Timelock and Config remain enabled      |
| `cancelQueuedAction`      | `emergency`                     | Immediate | The action exists and is not executed or cancelled                                  |

`queueBatch` supports these Config functions:

| Supported Config function     |
| ----------------------------- |
| `setAssetDebtCap`             |
| `setAssetRiskConfig`          |
| `setAssetFeeConfig`           |
| `setAssetOriginationsEnabled` |
| `setYieldRepurchaseRecipient` |
| `setYieldAssetRouting`        |

The typed queue helpers cover debt-cap, risk, and fee changes. Asset-originations and yield-routing
changes use `queueBatch`.

Each queued configuration key records its expected pre-state. Execution fails if that pre-state
changes before execution. A stale action does not block an unrelated action.

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

These functions do not use a timelock.

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
| `BurnerLoansInventory`    | `supply`, `withdraw`                       | `burner_loans_inventory_provider`           | Inventory is enabled                                       |
| `BurnerLoansInventory`    | `draw`, `settleRepayment`, `recordDefault` | Exact Burner Loans facility address         | Inventory is enabled                                       |
| `BurnerLoansSeizer`       | `execute`                                  | `heart`                                     | A disabled Seizer returns without work                     |
| `BurnerLoansSeizer`       | `selfExecuteTask`                          | The Seizer contract itself                  | Called by `execute`                                        |
| `BurnerLoansYieldClaimer` | `execute`                                  | `heart`                                     | A disabled YieldClaimer returns without work               |
| `BurnerLoansYieldClaimer` | `selfExecuteTask`                          | The YieldClaimer contract itself            | Called by `execute`                                        |

A direct permissionless seizure can receive the configured keeper reward. A caller with `heart` or
`burner_loans_seizer` receives no product keeper reward. The Seizer policy must hold
`burner_loans_seizer` before its automated call can proceed.

## Limits Of Each Authority

| Authority                    | Access limit                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `burner_loans_admin`         | Cannot add assets, change the global cap, rotate the backing oracle, change policy links, or bypass ConfigTimelock |
| `emergency`                  | Cannot change parameters, add assets, enable asset originations, or enable a policy                                |
| `heart`                      | Cannot change parameters and can call only the two periodic task entry points                                      |
| ConfigTimelock               | Cannot call functions outside the delegated Config surface                                                         |
| Borrower-authorized operator | Cannot change protocol configuration or another borrower's position                                                |
| Permissionless caller        | Can only repay, seize, claim yield, relay a signed authorization, and execute a valid queued action                |
