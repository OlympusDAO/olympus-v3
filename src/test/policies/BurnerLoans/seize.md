# seize payout deferral scenario plan

Only branch-added post-default payout behavior; debt-health/withdrawal math remains in seize.t.sol. Seized backing always belongs to Treasury regardless of revenue flags.

Seize and its executable preview require BL Kernel-active as well as locally enabled. All payout cases below start with active/enabled BL and otherwise eligible seizure inputs. The token controls whether transfer returns false or reverts; neither destination rejects an ordinary ERC20 transfer itself.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Use existing action-specific authorized callers, guards and previews; these plans assess only behavior introduced by this branch, not full parent-function coverage. Token amounts use native base units; preview debt uses 9-decimal OHM. Newly introduced payout buckets are described in [transferPendingPayout](./transferPendingPayout.md).

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Required previewSeize behavior is BL active/enabled and validates the seizure batch. Compare preview with action effects where executable; authoritative debt/custody/recipient balances and pending indexes are independent assertions. Fuzz only within reachable seizure/output domains; parent risk and custody boundaries remain in the existing seizure suite.

## Lifecycle

| ID | Caller | BL Kernel | BL local | Inventory and custody | Batch output | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SEZ-L01 | Any keeper, fuzz | Inactive | Enabled | Active | Eligible, positive | BurnerLoans_PolicyInactive() in action and executable preview | No default, withdrawal or token transfer; debt, collateral, all payout buckets and indexes unchanged | Covered: [inactive action and preview][test_givenPolicyInactive_whenSeizureIsPreviewedOrExecuted_reverts] |
| SEZ-L02 | Any keeper, fuzz | Active | Disabled | Active | Eligible, positive | NotEnabled() in preview and action | Unchanged; no payout | Covered: [caller fuzz and complete rollback][test_givenPolicyDisabled_seizeReverts] |
| SEZ-L03 | Any keeper, fuzz | Inactive | Disabled | Active | Eligible, positive | NotEnabled() before the new activity check, in preview and action | No default, withdrawal or token transfer; debt, collateral, payout buckets and indexes unchanged | Covered: [guard precedence][test_givenDisabledAndPolicyInactive_seizeAndPreviewUseLocalGuard] |

## Seizure distribution

Both routing flags are deliberately varied here to prove they do not affect seizure destinations.

| ID | Caller | Collateral output | `sendFeesToDistributor` | `sendYieldToDistributor` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SEZ-P01 | Any keeper, fuzz | Positive underlying | Fuzz false/true | Fuzz false/true independently | Default succeeds; previewed keeper reward is fixed to initiating caller; remainder goes Treasury | Debt defaults; exact keeper/Treasury deltas; no RD payment | Covered: [all routing flag pairs][test_givenSendFeesToDistributorIsTrue_givenSendYieldToDistributorIsTrue_sendsRemainderToTreasury], [caller fuzz][test_givenUnhealthyPosition_whenCallerIsArbitrary] |
| SEZ-P02 | Any keeper, fuzz | Positive vault shares | Fuzz false/true | Fuzz false/true independently | Default succeeds; previewed keeper reward is fixed to initiating caller; remainder goes Treasury | Debt defaults; exact keeper/Treasury share deltas; no RD payment | Covered: [all routing flag pairs and share output][test_givenVaultYield_whenWithdrawAsShares_routesShareToken], [caller fuzz][test_givenUnhealthyPosition_whenCallerIsArbitrary] |

## Transfers

| ID | Caller | Output mode | Keeper transfer | Treasury transfer | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SEZ-T01 | Any keeper, fuzz | Fuzz underlying/shares | Representative ordinary transfer failure | Succeeds | Default succeeds; only keeper reward pending | Fixed original keeper remains discoverable; Treasury gets exact remainder | Covered: [complete output, caller, event and index matrix][test_givenKeeperTransferFails_seizureDefersExactRewardForEveryOutput] |
| SEZ-T02 | Nonzero keeper, fuzz; zero separately in SEZ-T07 | Fuzz underlying/shares | Succeeds | Representative ordinary transfer failure | Default succeeds; only Treasury payout pending | Keeper paid exactly; seized-collateral bucket, custody and total reserve conserved | Covered: [complete output, caller, event and index matrix][test_givenTreasuryTransferFails_seizureDefersExactBackingForEveryOutput] |
| SEZ-T03 | Any keeper, fuzz | Fuzz underlying/shares | Reports success without movement | Reports success without movement | Default still succeeds; successful-return convention clears payout obligation | Actual residual remains in BL; token admission assumption explicit | Covered: [both output modes, caller fuzz, events and pending getters][test_givenCollateralTransferLeavesResidualBalance_seizeStillDefaults] |
| SEZ-T06 | Any keeper, fuzz | Fuzz underlying/shares | Representative ordinary transfer failure | Representative ordinary transfer failure | Default succeeds; both payouts deferred; SafeERC20 owns false/revert return-shape coverage | Both buckets and total reserve retained; neither recipient paid | Covered: [both output modes, caller fuzz, events and indexes][test_givenBothTransfersFail_seizureDefersBothOutputs] |
| SEZ-T07 | Zero-address keeper | Fuzz underlying/shares | Standard ERC-20 rejects zero-address transfer | Succeeds | Default succeeds; unsendable keeper reward is deferred | Zero recipient remains indexed with exact reward; Treasury paid exactly; custody and total reserve conserved | Covered: [zero-caller boundary for both outputs][test_givenZeroAddressKeeper_seizureDefersUnsendableReward] |

## Callbacks

| ID | Caller | Callback destination | Nested failure handling | Other transfer | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SEZ-C01 | Nonzero keeper, fuzz; zero separately in SEZ-T07 | Keeper | Caught | Succeeds | Nested ReentrancyGuardReentrantCall(); outer default succeeds once | Exactly one default and keeper payment | Covered: [recipient and failure matrix][test_givenSeizureRecipientCallback_outerDefaultExecutesOnce] |
| SEZ-C03 | Nonzero keeper, fuzz; zero separately in SEZ-T07 | Treasury | Caught | Succeeds | Nested ReentrancyGuardReentrantCall(); outer default succeeds once | Exactly one default and Treasury payment | Covered: [recipient and failure matrix][test_givenSeizureRecipientCallback_outerDefaultExecutesOnce] |
| SEZ-C02 | Nonzero keeper, fuzz; zero separately in SEZ-T07 | Fuzz keeper/Treasury | Propagated | Succeeds | Callback destination is deferred; other payout succeeds | No movement from failed transfer; debt default retained and matching bucket owed | Covered: [recipient and failure matrix][test_givenSeizureRecipientCallback_outerDefaultExecutesOnce] |

[test_givenPolicyDisabled_seizeReverts]: ./seize.t.sol#L1554
[test_givenCollateralTransferLeavesResidualBalance_seizeStillDefaults]: ./seize.t.sol#L1403
[test_givenSendFeesToDistributorIsTrue_givenSendYieldToDistributorIsTrue_sendsRemainderToTreasury]: ./seize.t.sol#L148
[test_givenVaultYield_whenWithdrawAsShares_routesShareToken]: ./seize.t.sol#L765
[test_givenUnhealthyPosition_whenCallerIsArbitrary]: ./seize.t.sol#L739
[test_givenPolicyInactive_whenSeizureIsPreviewedOrExecuted_reverts]: ./seize.t.sol#L1610
[test_givenDisabledAndPolicyInactive_seizeAndPreviewUseLocalGuard]: ./seize.t.sol#L1652
[test_givenSeizureRecipientCallback_outerDefaultExecutesOnce]: ./seize.t.sol#L60
[test_givenKeeperTransferFails_seizureDefersExactRewardForEveryOutput]: ./seize.t.sol#L367
[test_givenTreasuryTransferFails_seizureDefersExactBackingForEveryOutput]: ./seize.t.sol#L431
[test_givenBothTransfersFail_seizureDefersBothOutputs]: ./seize.t.sol#L509
[test_givenZeroAddressKeeper_seizureDefersUnsendableReward]: ./seize.t.sol#L595
