# claimYield revenue routing scenario plan

Only branch-added yield destination and failure semantics; yield is delivered by DepositManager/custody and never becomes BL pending fee/seizure debt.

BL must be Kernel-active before this action or its executable preview can proceed. All success/input/transfer rows assume BL active. Inactive rejection is tested with otherwise valid inputs and retained caller authorization, for each routing flag; disabled BL remains a separate case.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Use existing action-specific authorized callers, guards and previews; these plans assess only behavior introduced by this branch, not full parent-function coverage. Token amounts use native base units; yield quantities use the output token’s native base units. This action takes only an asset address; there is no numeric claim-amount input. Newly introduced payout buckets are described in [transferPendingPayout](./transferPendingPayout.md).

BL state separates Kernel membership from local enablement. `sendYieldToDistributor=false` selects the current Treasury; `true` selects the current nonzero Revenue Distributor. Destination lifecycle is relevant only to proving that the direct DepositManager transfer does not call RD lifecycle gates. Custody/output mode has three partitions: direct custody returns the asset, vault custody with `withdrawAsShares=false` returns the underlying asset, and vault custody with `withdrawAsShares=true` returns the vault share token. Asset-originations state is independent because disabling new originations does not block yield claims.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Required previewClaimYield behavior is permissionless but requires BL active/enabled and a registered, supported custody route. Compare preview with action effects where executable; authoritative debt/custody/recipient balances and pending indexes are independent assertions. Fuzz only reachable yield/custody relationships. Numeric extremes refer to claimable yield and output-share rounding, not a nonexistent amount parameter.

## Lifecycle

| ID | Caller | BL Kernel | BL local | Asset registration/originations | `sendYieldToDistributor` | Live destination state | Custody/output mode | Yield state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-P02 | Any caller, fuzz | Active | Enabled | Registered; originations enabled or disabled | `true` | Current RD is Kernel-active but locally disabled | Direct custody, vault underlying and vault shares separately | Positive claimable yield | Success; direct yield payment does not enforce RD lifecycle guards | Exact previewed yield reaches RD; no BL pending payout | Covered: [all custody and originations modes][test_givenDistributorUnavailable_claimRoutesEveryCustodyMode] |
| YLD-L04 | Any caller, fuzz | Inactive after deactivation | Enabled | Registered; originations enabled or disabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | Direct custody, vault underlying and vault shares separately | Positive claimable yield | BurnerLoans_PolicyInactive() in action and executable preview | Yield remains claimable; custody, all BL pending buckets and recipient balances unchanged; no dependency claim or payout | Covered: [inactive action and preview][test_givenPolicyInactive_whenYieldIsPreviewedOrClaimed_reverts] |
| YLD-L01 | Any caller, fuzz | Active | Enabled | Registered; originations enabled or disabled | `true` | Current RD is Kernel-inactive but locally enabled | Direct custody, vault underlying and vault shares separately | Positive claimable yield | Success; direct yield payment does not enforce RD lifecycle guards | Exact previewed yield reaches RD; no BL pending payout | Covered: [all custody and originations modes][test_givenDistributorUnavailable_claimRoutesEveryCustodyMode] |
| YLD-L02 | Any caller, fuzz | Active | Disabled | Registered; originations enabled or disabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | Direct custody, vault underlying and vault shares separately | Positive claimable yield | NotEnabled() in preview and execution | Unchanged; no claim or payment | Covered: [action, preview and full rollback matrix][test_givenLocallyDisabled_claimAndPreviewRollbackEveryCustodyMode] |
| YLD-L03 | Any caller, fuzz | Active | Enabled | Registered; originations disabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | Direct custody, vault underlying and vault shares separately | Positive claimable yield | Claim remains callable | Exact previewed yield to live destination | Covered: [all output modes and routes][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput] |
| YLD-L05 | Any caller, fuzz | Inactive | Disabled | Registered; originations enabled or disabled | `false`; `true` separately | Current Treasury or nonzero RD respectively | Direct custody, vault underlying and vault shares separately | Positive claimable yield | NotEnabled() before the new activity check, in preview and execution | Yield remains claimable; custody, pending buckets and recipients unchanged; no dependency claim or payout | Covered: [guard precedence][test_givenDisabledAndPolicyInactive_claimAndPreviewUseLocalGuard] |

## Yield distribution

Reuse the same custody and routing fixtures for positive- and zero-yield cases. The zero-yield case changes only the claimable-yield state; it must still validate and return the correct output token for each custody mode.

| ID | Caller | BL state | Asset registration/originations | `sendYieldToDistributor` | Live recipient | Custody/output mode | Claimable yield | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-P01 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `false` | Current Treasury | Direct custody; output is asset | Positive | Success; preview selects Treasury and the custody asset | Exact positive Treasury delta; BL pending ledger unchanged | Covered: [all direct-custody dimensions][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput] |
| YLD-P05 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `false` | Current Treasury | Vault custody; `withdrawAsShares=false`; output is underlying | Positive | Success; preview selects Treasury and underlying token | Exact positive Treasury delta; BL pending ledger unchanged | Covered: [vault-underlying route][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput] |
| YLD-P06 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `false` | Current Treasury | Vault custody; `withdrawAsShares=true`; output is vault share token, including an external share token | Positive | Success; preview selects Treasury and share token | Exact positive Treasury delta; BL pending ledger unchanged | Covered: [vault-share route][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput], [external share token][test_givenExternalShareToken_distributesPositiveYield] |
| YLD-P04 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `true` | Current nonzero RD | Direct custody; output is asset | Positive | Success; preview selects RD and custody asset | Exact positive RD receipt; BL pending ledger unchanged | Covered: [all direct-custody dimensions][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput] |
| YLD-P07 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `true` | Current nonzero RD | Vault custody; `withdrawAsShares=false`; output is underlying | Positive | Success; preview selects RD and underlying token | Exact positive RD receipt; BL pending ledger unchanged | Covered: [vault-underlying route][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput] |
| YLD-P08 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `true` | Current nonzero RD | Vault custody; `withdrawAsShares=true`; output is vault share token, including an external share token | Positive | Success; preview selects RD and share token | Exact positive RD receipt; BL pending ledger unchanged | Covered: [vault-share route][test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput], [external share token][test_givenExternalShareToken_distributesPositiveYield] |
| YLD-I02 | Any caller, fuzz | Active/enabled | Registered; originations enabled or disabled | `false`/Treasury and `true`/RD separately | Current selected recipient | Direct custody, vault underlying and vault shares separately | Zero | Success; preview and execution return the custody mode's output token with zero amount | No DepositManager claim, payout event or BL pending entry; custody and recipient balances unchanged | Covered: [all zero-yield output modes][test_givenZeroYield_whenClaimed_returnsCustodyOutputWithoutPayout] |

## Invalid inputs

| ID | Caller | BL state | `sendYieldToDistributor` | Asset input/registration | Custody/output mode | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-I01 | Any caller, fuzz | Active/enabled | Fuzz `false`/`true` | `asset_=address(0)`; unregistered | Not reached | BurnerLoans_AssetNotConfigured(asset) in preview and execution | Unchanged | Covered: [unregistered asset classes][test_givenUnregisteredAssetClass_previewAndClaimRevert] |
| YLD-I05 | Any caller, fuzz | Active/enabled | Fuzz `false`/`true` | `asset_` is an EOA; unregistered | Not reached | BurnerLoans_AssetNotConfigured(asset) in preview and execution | Unchanged | Covered: [unregistered asset classes][test_givenUnregisteredAssetClass_previewAndClaimRevert] |
| YLD-I06 | Any caller, fuzz | Active/enabled | Fuzz `false`/`true` | `asset_` is a contract but unregistered | Not reached | BurnerLoans_AssetNotConfigured(asset) in preview and execution | Unchanged | Covered: [unregistered asset classes][test_givenUnregisteredAssetClass_previewAndClaimRevert] |

## Numeric extremes and rounding

| ID | Caller | BL state | `sendYieldToDistributor` / recipient | Custody/output mode | Yield and rounding state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-P03 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Vault custody; `withdrawAsShares=true`; output is shares | Positive theoretical yield below one share; retained dust later reaches one share; seed adjacent conversion thresholds | Zero output succeeds without consuming claimable dust; later positive share pays | Preserve custody/debt; no fabricated pending payout | Covered: [both routes and adjacent share thresholds][test_givenShareYieldBelowOneShare_whenRepeatedClaims] |
| YLD-N01 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Direct custody; output is asset | Funded claimable yield=1 with zero other custody liabilities | Success with exact one-unit output | Exact destination/custody delta; no BL pending entry | Covered: [one-unit direct yield][test_givenOneUnitDirectYield_routesExactUnit] |

## Transfers

| ID | Caller | BL state | `sendYieldToDistributor` | Live recipient | Custody/output mode | Output-token behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-T02 | Any caller, fuzz | Active/enabled | `false` | Current Treasury | Direct custody, vault underlying and vault shares separately | Representative mandatory output transfer failure; SafeERC20 owns false/revert return-shape coverage | Claim reverts with exact controlled token error | Claimable yield/custody restored; no committed output event or BL pending payout | Covered: [all output modes][test_givenOutputTransferFailure_claimRollsBackEveryCustodyMode] |
| YLD-T04 | Any caller, fuzz | Active/enabled | `true` | Current nonzero RD | Direct custody, vault underlying and vault shares separately | Representative mandatory output transfer failure; SafeERC20 owns false/revert return-shape coverage | Claim reverts with exact controlled token error | Claimable yield/custody restored; no committed output event or BL pending payout | Covered: [all output modes][test_givenOutputTransferFailure_claimRollsBackEveryCustodyMode] |

## Callbacks

| ID | Caller | BL state | `sendYieldToDistributor` / recipient | Custody/output mode | Callback source and behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-C01 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Direct custody, vault underlying and vault shares separately | DepositManager catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer claim succeeds once | One exact payment; custody/pending ledger consistent | Covered: [complete callback matrix][test_givenDepositManagerCallback_claimHandlesEveryCustodyMode] |
| YLD-C03 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Direct custody, vault underlying and vault shares separately | Output token catches a nested guarded call | Nested ReentrancyGuardReentrantCall(); outer claim succeeds once | One exact payment; custody/pending ledger consistent | Covered: [complete callback matrix][test_givenOutputTokenCallback_claimHandlesEveryCustodyMode] |
| YLD-C02 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Direct custody, vault underlying and vault shares separately | DepositManager propagates the nested guarded-call failure | Claim reverts with controlled callback error | All claim/custody effects roll back; yield remains claimable | Covered: [complete callback matrix][test_givenDepositManagerCallback_claimHandlesEveryCustodyMode] |
| YLD-C04 | Any caller, fuzz | Active/enabled | `false`/Treasury and `true`/RD separately | Direct custody, vault underlying and vault shares separately | Output token propagates the nested guarded-call failure | Claim reverts with controlled callback error | All claim/custody effects roll back; yield remains claimable | Covered: [complete callback matrix][test_givenOutputTokenCallback_claimHandlesEveryCustodyMode] |

## Routing changes

| ID | Caller | BL state | Routing flag before retry | Destination transition | Custody/output mode | Yield state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YLD-S01 | Any caller, fuzz | Active/enabled | `sendYieldToDistributor=true` | Failed transfer to former RD; replace selected RD before a fresh claim | Direct custody, vault underlying and vault shares separately | Original claim rolled back and remains claimable | Fresh claim pays current RD | Old RD gets no later payment; exact custody and event deltas | Covered: [all custody modes and caller fuzz][test_givenFailedClaim_whenDestinationChanges_freshClaimUsesLiveRecipient] |
| YLD-S02 | Any caller, fuzz | Active/enabled | `sendYieldToDistributor=false` | Failed transfer to former Treasury; upgrade Treasury before a fresh claim | Direct custody, vault underlying and vault shares separately | Original claim rolled back and remains claimable | Fresh claim pays current Treasury | Former Treasury gets no later payment; exact custody and event deltas | Covered: [all custody modes and caller fuzz][test_givenFailedClaim_whenDestinationChanges_freshClaimUsesLiveRecipient] |

[test_givenShareYieldBelowOneShare_whenRepeatedClaims]: ./claimYield.t.sol#L343
[test_givenExternalShareToken_distributesPositiveYield]: ./claimYield.t.sol#L684
[test_givenPolicyInactive_whenYieldIsPreviewedOrClaimed_reverts]: ./claimYield.t.sol#L923
[test_givenDisabledAndPolicyInactive_claimAndPreviewUseLocalGuard]: ./claimYield.t.sol#L965
[test_givenPositiveYield_whenClaimed_routesExactPreviewedOutput]: ./claimYield.t.sol#L980
[test_givenZeroYield_whenClaimed_returnsCustodyOutputWithoutPayout]: ./claimYield.t.sol#L1034
[test_givenUnregisteredAssetClass_previewAndClaimRevert]: ./claimYield.t.sol#L1065
[test_givenOneUnitDirectYield_routesExactUnit]: ./claimYield.t.sol#L1093
[test_givenOutputTransferFailure_claimRollsBackEveryCustodyMode]: ./claimYield.t.sol#L41
[test_givenDistributorUnavailable_claimRoutesEveryCustodyMode]: ./claimYield.t.sol#L146
[test_givenLocallyDisabled_claimAndPreviewRollbackEveryCustodyMode]: ./claimYield.t.sol#L187
[test_givenDepositManagerCallback_claimHandlesEveryCustodyMode]: ./claimYield.t.sol#L1262
[test_givenOutputTokenCallback_claimHandlesEveryCustodyMode]: ./claimYield.t.sol#L82
[test_givenFailedClaim_whenDestinationChanges_freshClaimUsesLiveRecipient]: ./claimYield.t.sol#L487
