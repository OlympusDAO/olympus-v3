# Deposit Manager Access Control

## Authority Matrix

| Authority               | Functions                                                                                                                                      | Timing and limits                                                                                                                                                                |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `admin`                 | `enable`, `disable`, `reEnable`, `setGracePeriod`, `setConfigOperator`                                                                         | Direct governance lifecycle control; `reEnable` is bounded by the configured grace period                                                                                        |
| `admin`                 | `addAsset`, `setOperatorName`                                                                                                                  | Asset onboarding and operator registration remain direct governance-only                                                                                                         |
| `admin`                 | `rescue`                                                                                                                                       | Available while enabled or disabled; only unmanaged ERC-20 balances can be sent to `TRSRY`                                                                                       |
| `admin`                 | `addAssetPeriod`, `setAssetDepositCap`, `setAssetMinimumDeposit`, `setAssetShareWithdrawalRequired`, `enableAssetPeriod`, `disableAssetPeriod` | Governance can bypass the configuration timelock and apply operational configuration directly                                                                                    |
| `admin`                 | DepositManagerConfigTimelock queue functions                                                                                                   | Can also propose delayed configuration, although governance already has a timelock and can use the direct path                                                                   |
| `deposit_manager_admin` | `reEnable`                                                                                                                                     | Immediate bounded recovery during the re-enable grace period                                                                                                                     |
| `deposit_manager_admin` | DepositManagerConfigTimelock queue functions                                                                                                   | Proposes delayed mutable configuration and delayed route creation; cannot perform direct structural registration or onboarding                                                   |
| Config operator         | `addAssetPeriod`, `setAssetDepositCap`, `setAssetMinimumDeposit`, `setAssetShareWithdrawalRequired`, `enableAssetPeriod`, `disableAssetPeriod` | Normally the DepositManagerConfigTimelock; route creation through the timelock starts the route enabled after the delay; authority is revoked by setting another address or zero |
| Config operator         | `rescue` | Normally DepositManagerConfigTimelock; delayed recovery permits local disablement and sends only unmanaged tokens to current TRSRY |
| `emergency`             | `disable`, `disableAssetPeriod`, timelock cancellation                                                                                         | Immediate one-way shutdown and queued-action cancellation; cannot enable a period, create a route queue, change limits, or queue any configuration                               |
| `deposit_operator`      | `deposit`, `withdraw`, `claimYield`, `borrowingWithdraw`, `borrowingRepay`, `borrowingDefault`                                                 | Restricted to the caller's operator namespace; possession is required before a route is created for the operator                                                                 |
| Any address             | Timelock execution after maturity; views and previews                                                                                          | Execution requires a valid, unexpired operation and matching lifecycle and pre-state; rescue previews require DM active and permit local disablement |

DepositManager's `validateAddAssetPeriod` checks route prerequisites at DMCT queue time. Dispatch applies the same internal check. The asset must be configured and the period nonzero. The operator must be registered through `setOperatorName` and hold `deposit_operator` at dispatch. DMCT gains no ability to approve assets, register operators, or grant roles. Queued route
creation reuses the asset-period-operator configuration key, so add, enable, and disable for the
same tuple conflict. Direct admin route creation after queueing, or a role revocation, makes the
queued action state-stale and non-executable. `setConfigOperator` is intentionally single-step and
admin-only. It can appoint any address: that address receives the entire config-operator surface,
including direct route creation. Appointing DMCT is the operational choice that imposes its delay.
The initial share-withdrawal requirement remains part of admin-only asset onboarding. Admin can
change it directly after onboarding, while the config-operator route normally uses the timelock's
`queueSetAssetShareWithdrawalRequired`. The timelock cannot add assets, set operator names, or change
its own authority. `queueRescue` schedules unmanaged-token recovery. There is no separate admin-owned floor for withdrawal mode or
admin whitelist of deposit periods: the configured asset, registered operator, current role, and
nonzero period are the route boundaries. Deposit caps remain direct-admin or config-operator
settings; this change does not redefine their accounting semantics. Admin may directly re-enable a
route that emergency disabled, while `deposit_manager_admin` must queue enablement through DMCT.

## Lifecycle Gates

DepositManager has three distinct lifecycle layers:

1. Kernel activity gates ordinary custody and configuration actions, rescue, and enable/re-enable admission.
2. The global enabled flag gates state-changing custody and configuration entrypoints.
3. The asset-period enabled flag gates new deposits for one operator market.

The DepositManagerConfigTimelock requires both policies Kernel-active and requires itself locally enabled.
Ordinary configuration also requires DepositManager enabled. Rescue-only queues and executions permit
a disabled DepositManager; mixed batches retain every configuration action's enabled requirement.
The timelock must remain the selected config operator. Execution is permissionless after the delay. Emergency cancellation requires the
timelock active, permits its local disablement, and does not inspect DepositManager's lifecycle.

Kernel deactivation pauses, rather than destroys, queued actions. After both policies are
reactivated, an unexpired action may execute if its config operator and expected configuration
pre-state still match. An active timelock can cancel an action while DepositManager remains inactive.

Ordinary actions check existing reentrancy guards, own Kernel activity, local enablement, then caller
authority. Inactivity takes precedence over a local pause or missing role. Views and conversion
previews remain readable; a conversion estimate alone does not establish execution readiness.

`rescue` requires DepositManager active and is independent of the global enabled state. ADMIN or the selected nonzero config operator can send
the complete balance of an unmanaged ERC-20 token to the current `TRSRY` module. The caller cannot
choose another recipient, and configured assets, vault entry points, and stored share tokens cannot
be rescued. The stored share token remains protected if a mutable ERC-7575 vault later reports a
different token.

Holding `deposit_manager_admin` alone does not permit direct rescue. ADMIN or a manager can propose
`queueRescue(token)` through the selected timelock. The queue uses `previewRescue(token)` for admission.
It commits eligibility rather than a balance. Execution rechecks eligibility and transfers the full
live balance to the current Treasury. New receipts and Treasury upgrades do not stale the action.
Onboarding the token as an asset, vault, or stored share token makes the rescue commitment stale.
ADMIN retains direct recovery if the timelock is unavailable.

`previewRescue(token)` is permissionless and returns the live balance, including zero. It shares
token, balance-read and Treasury validation with rescue. A quote does not establish execution authority
or guarantee token delivery. It changes no accounting and does not reserve tokens.

For custody, accounting, share withdrawal, and version behavior, see
[Deposit Manager](deposit_manager.md).

Config-operator rotation on DepositManager requires own Kernel activity, local enablement, then ADMIN. Zero revokes delegation. The queue checks target Kernel compatibility before target enablement, so a paused foreign-Kernel target still reports the Kernel mismatch.
