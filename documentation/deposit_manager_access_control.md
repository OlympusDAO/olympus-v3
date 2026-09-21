# Deposit Manager Access Control

## Authority Matrix

| Authority               | Functions                                                                                      | Timing and limits                                                                                  |
| ----------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `admin`                 | `enable`, `disable`, `reEnable`, `setGracePeriod`, `setConfigOperator`                         | Direct governance lifecycle control; `reEnable` is bounded by the configured grace period          |
| `admin`                 | `addAsset`, `addAssetPeriod`, `setOperatorName`                                                | Structural custody configuration remains direct governance-only                                    |
| `admin`                 | `rescue`                                                                                       | Available while enabled or disabled; only unmanaged ERC-20 balances can be sent to `TRSRY`         |
| `admin`                 | `setAssetDepositCap`, `setAssetMinimumDeposit`, `setAssetShareWithdrawalRequired`, `enableAssetPeriod`, `disableAssetPeriod` | Governance can apply mutable configuration directly                                                |
| `deposit_manager_admin` | `reEnable`                                                                                     | Immediate bounded recovery during the re-enable grace period                                       |
| `deposit_manager_admin` | `rescue`                                                                                       | Available while enabled or disabled; only unmanaged ERC-20 balances can be sent to `TRSRY`         |
| `deposit_manager_admin` | DepositManagerConfigTimelock queue functions                                                   | Proposes delayed mutable configuration; cannot perform structural registration                     |
| Config operator         | `setAssetDepositCap`, `setAssetMinimumDeposit`, `setAssetShareWithdrawalRequired`, `enableAssetPeriod`, `disableAssetPeriod` | Normally the DepositManagerConfigTimelock; authority is revoked by setting another address or zero |
| `emergency`             | `disable`, `disableAssetPeriod`                                                                | Immediate one-way shutdown; cannot enable a period or change limits                                |
| `deposit_operator`      | `deposit`, `withdraw`, `claimYield`, `borrowingWithdraw`, `borrowingRepay`, `borrowingDefault` | Restricted to the caller's operator namespace                                                      |
| Any address             | Views and previews                                                                             | Conversion previews do not prove authorization or successful execution                             |

`setConfigOperator` is intentionally single-step and admin-only. Assigning a timelock gives it only
the mutable configuration authority listed above. The initial share-withdrawal requirement remains
part of admin-only asset onboarding. Admin can change it directly after onboarding, while the
config-operator route normally uses the timelock's `queueSetAssetShareWithdrawalRequired`. The
timelock cannot add assets, add periods, set operator names, rescue tokens, or change its own
authority.

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
