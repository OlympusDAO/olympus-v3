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
| `deposit_manager_admin` | `rescue`                                                                                                                                       | Available while enabled or disabled; only unmanaged ERC-20 balances can be sent to `TRSRY`                                                                                       |
| `deposit_manager_admin` | DepositManagerConfigTimelock queue functions                                                                                                   | Proposes delayed mutable configuration and delayed route creation; cannot perform direct structural registration or onboarding                                                   |
| Config operator         | `addAssetPeriod`, `setAssetDepositCap`, `setAssetMinimumDeposit`, `setAssetShareWithdrawalRequired`, `enableAssetPeriod`, `disableAssetPeriod` | Normally the DepositManagerConfigTimelock; route creation through the timelock starts the route enabled after the delay; authority is revoked by setting another address or zero |
| `emergency`             | `disable`, `disableAssetPeriod`, timelock cancellation                                                                                         | Immediate one-way shutdown and queued-action cancellation; cannot enable a period, create a route queue, change limits, or queue any configuration                               |
| `deposit_operator`      | `deposit`, `withdraw`, `claimYield`, `borrowingWithdraw`, `borrowingRepay`, `borrowingDefault`                                                 | Restricted to the caller's operator namespace; possession is required before a route is created for the operator                                                                 |
| Any address             | Timelock execution after maturity; views and previews                                                                                          | Execution still requires a valid, unexpired operation and matching lifecycle and pre-state; conversion previews do not prove successful execution                                |

Route creation prerequisites are checked by DepositManager's
`validateAddAssetPeriod` at DMCT queue time and by the same internal check at direct or timelocked
dispatch: the asset must be configured, the deposit period must be nonzero, the operator must be
explicitly registered through `setOperatorName`, and the operator must hold `deposit_operator` at
dispatch. DMCT gains no ability to approve assets, register operators, or grant roles. Queued route
creation reuses the asset-period-operator configuration key, so add, enable, and disable for the
same tuple conflict. Direct admin route creation after queueing, or a role revocation, makes the
queued action state-stale and non-executable. `setConfigOperator` is intentionally single-step and
admin-only. It can appoint any address: that address receives the entire config-operator surface,
including direct route creation. Appointing DMCT is the operational choice that imposes its delay.
The initial share-withdrawal requirement remains part of admin-only asset onboarding. Admin can
change it directly after onboarding, while the config-operator route normally uses the timelock's
`queueSetAssetShareWithdrawalRequired`. The timelock cannot add assets, set operator names, rescue
tokens, or change its own authority. There is no separate admin-owned floor for withdrawal mode or
admin whitelist of deposit periods: the configured asset, registered operator, current role, and
nonzero period are the route boundaries. Deposit caps remain direct-admin or config-operator
settings; this change does not redefine their accounting semantics. Admin may directly re-enable a
route that emergency disabled, while `deposit_manager_admin` must queue enablement through DMCT.

## Lifecycle Gates

DepositManager has three distinct lifecycle layers:

1. Kernel activity records whether the policy is installed as an active policy.
2. The global enabled flag gates state-changing custody and configuration entrypoints.
3. The asset-period enabled flag gates new deposits for one operator market.

The DepositManagerConfigTimelock requires both itself and DepositManager to be Kernel-active and
globally enabled when queueing or executing an action. It also requires itself to remain the current
config operator. Execution is permissionless after the delay. Emergency cancellation remains
available when either policy is Kernel-inactive or globally disabled.

Kernel deactivation pauses, rather than destroys, queued actions. After both policies are
reactivated, an unexpired action may execute if its config operator and expected configuration
pre-state still match. Emergency should cancel actions that must not survive a deactivation
incident.

Kernel activity is not a general modifier on DepositManager's own legacy entrypoints. Operational
shutdown should therefore use the global or asset-period disable controls as appropriate; Kernel
deactivation alone is not a substitute for those controls.

`rescue` is independent of the global enabled state. An `admin` or `deposit_manager_admin` can send
the complete balance of an unmanaged ERC-20 token to the current `TRSRY` module. The caller cannot
choose another recipient, and configured assets, vault entry points, and stored share tokens cannot
be rescued. The stored share token remains protected if a mutable ERC-7575 vault later reports a
different token.

For custody, accounting, share withdrawal, and version behavior, see
[Deposit Manager](deposit_manager.md).
