# transferPendingPayout scenario plan

Scope: permissionless RD retry and its pendingPayout/getPendingPayoutAssets/getPendingPayoutRecipients views.

Co-located route getters: retries and donations preserve assetState, getAssetDistribution, active membership and assetDistributionHash. treasury()/yieldRecipient() identify current role owners after upgrade/rotation; compare with independent expected destinations. Getters remain callable by fuzzed callers while RD disabled/inactive.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Debt, custody and transfer quantities are uint256 token base units; `MAX` means `type(uint256).max`.

Permissionless: fuzz caller without exclusions. Kernel activity is checked before local enabled state. Active and Retired assets can pay. No asset-listing, zero-asset or zero-recipient validation occurs when entitlement is zero. Fixed configured-address, current global yield-role (Treasury fallback if unset) and current Treasury-role debts combine for an overlapping recipient.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: one token transfer for the full combined entitlement; decrease aggregate debt and custody by that amount, clear only matched buckets, remove recipient/asset indexes only when empty, exactly one Distributed. Failure: one DistributionDeferred, debt and indexes retained. Other recipient/asset debt is isolated; repeat successful retry is silent.

## Lifecycle

| ID | Caller | RD Kernel | RD local | Asset state | Matching entitlement | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-L01 | Any caller, fuzz | Inactive | Fuzz enabled/disabled | Fuzz Active/Retired | Fuzz zero/positive | RevenueDistributor_PolicyInactive() | Unchanged | Covered: [full matrix][test_givenPolicyInactive_whenAnyRetryAttempted_revertsBeforeLocalState], [Treasury-upgrade integration][test_givenPendingTreasury_whenPolicyInactiveAndTreasuryUpgrades_thenRetryWaitsForReactivation] |
| RTRY-L02 | Any caller, fuzz | Active | Disabled | Fuzz Active/Retired | Positive | NotEnabled() | Unchanged | Covered: [full matrix][test_givenDistributorDisabled_whenAnyManagedAssetRetried_reverts], [Active integration][test_givenPendingRecipient_whenDistributorDisabled_thenRetryWaitsForReEnable], [Retired integration][test_givenRetiredAssetAndDisabledDistributor_retryWaitsForReEnable] |

## No entitlement

| ID | Caller | Asset input/state | Recipient input/state | Matching entitlement | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-P01 | Any caller, fuzz | Fuzz zero, EOA, NeverListed contract | Fuzz any address | None | Silent success; no balance query or transfer | No debt, balance, index or event change | Covered: [zero and EOA][test_givenNoPendingPayout_whenInputsAreArbitrary_noOps], [NeverListed contract][test_givenNeverListedContractWithNoPendingPayout_whenRetried_noOps] |
| RTRY-P08 | Any caller, fuzz | Valid contract | Fuzz zero, unrelated EOA, former role without fixed debt | None | Silent success; no balance query or transfer | No debt, balance, index or event change | Covered: [valid asset][test_givenNoPendingPayout_noOps], [input partitions][test_givenNoPendingPayout_whenInputsAreArbitrary_noOps] |
| RTRY-P11 | Any caller, fuzz | Previously owed asset | Previously owed recipient | Already paid | Silent success; no balance query or transfer | No debt, balance, index or event change | Covered: [evidence][test_givenCombinedPendingBuckets_whenRetried_paysOneCombinedTransfer] |

## Transfers

| ID | Caller | Positive bucket mask | Custody | Transfer behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-T01 | Any caller, fuzz | Fuzz nonempty configured/yield/Treasury subset for one recipient | Solvent | Returns false | Success with DistributionDeferred(asset,recipient,entitlement) | Every component of the combined debt and its indexes remains; successful later retry pays once | Covered: [evidence][test_givenCombinedPendingBuckets_whenTransferReturnsFalse_defersThenRetries] |
| RTRY-T03 | Any caller, fuzz | Configured, yield and Treasury buckets for one recipient | Solvent | Reverts | Success with DistributionDeferred(asset,recipient,entitlement) | Every component of the combined debt and its indexes remains; successful later retry pays once | Covered: [evidence][test_givenPendingPayout_whenTransferReverts_defersThenRetries] |
| RTRY-T02 | Any caller, fuzz | Configured, yield and Treasury buckets | Less than entitlement | Standard insufficient-balance failure | Success with DistributionDeferred; no explicit solvency revert | Debt retained; donation restoring funds permits retry | Covered: [evidence][test_givenPendingPayoutExceedsCustody_whenRetried_defersUntilFunded] |

## Callbacks

| ID | Caller | Positive bucket mask | Nested guarded call | Callback handling | Debt visibility during callback | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-C01 | Any caller, fuzz | Fuzz nonempty configured/yield/Treasury subset | Retry, distribute, rescue or configuration | Caught | Full pre-delivery debt | Nested ReentrancyGuardReentrantCall(); outer success | One full combined payment; getters during callback still show pre-delivery debt | Covered: [guarded-call and bucket matrix][test_givenPendingPayout_whenTokenCatchesAnyGuardedNestedCall_paysOnce], [getter callback][test_givenPendingPayout_whenTokenReadsGetter_callbackSeesPreDeliveryDebt], [retry integration][test_givenPendingPayout_whenTokenReentersRetry_thenPayoutOccursOnce] |
| RTRY-C02 | Any caller, fuzz | Configured bucket | Nested retry | Propagated | Full pre-delivery debt | Success with DistributionDeferred | All debt and custody retained | Covered: [evidence][test_givenPendingPayout_whenTokenPropagatesReentrantFailure_defersPayout] |

## Debt buckets

| ID | Caller | Asset state | Positive bucket | Recipient assignment | Amount | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-P02 | Any caller, fuzz | Fuzz Active/Retired | Configured only | Fixed at allocation | Fuzz 1..MAX; seed 1,MAX | Success | Fixed recipient paid; other blocked configured recipient remains owed | Covered: [state, caller, quantity and isolation matrix][test_givenConfiguredPayout_whenRetried_paysExactAmountAndIsolatesOtherDebt], [maximum seed][test_givenConfiguredPayoutAtMaximum_whenRetried_paysExactAmount], [blocked-recipient integration][test_givenTwoPendingRecipients_whenFirstStillBlocked_thenSecondCanRetryDirectly], [Retired integration][test_givenRetiredAssetAndDisabledDistributor_retryWaitsForReEnable] |

## Yield Recipient changes

| ID | Caller | Asset state | Positive bucket | Yield-recipient transition | Resolved recipient | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-P03 | Any caller, fuzz | Fuzz Active/Retired | Yield only | Compatible policy A -> B | Current policy B | Success at current recipient; former recipient retry is silent | New policy is paid; historical configured debt stays fixed | Covered: [state, caller, quantity and fixed-debt matrix][test_givenYieldPayout_whenRecipientRotates_retryUsesCurrentRole], [maximum seed][test_givenMaximumYieldPayout_whenRecipientRotates_retryPaysMaximum] |
| RTRY-P12 | Any caller, fuzz | Fuzz Active/Retired | Yield only | Policy -> zero | Current Treasury fallback | Success at current Treasury fallback; former recipient retry is silent | Treasury is paid; historical configured debt stays fixed | Covered: [state, caller, quantity and fixed-debt matrix][test_givenYieldPayout_whenRecipientClears_retryUsesTreasuryFallback], [maximum seed][test_givenMaximumYieldPayout_whenRecipientClears_retryPaysTreasuryMaximum] |

## Treasury changes

| ID | Caller | Asset state | Positive bucket | Treasury transition | Resolved recipient | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-P04 | Any caller, fuzz | Fuzz Active/Retired | Treasury only | Treasury A -> B | Current Treasury B | Success at current Treasury; former Treasury retry is silent | Pay new Treasury and clear debt; route state remains unchanged | Covered: [state, caller, quantity and fixed-debt matrix][test_givenTreasuryPayout_whenTreasuryUpgrades_retryUsesCurrentRole], [maximum seed][test_givenMaximumTreasuryPayout_whenTreasuryUpgrades_retryPaysMaximum], [Active integration][test_givenTreasuryPayoutPending_whenTreasuryUpgrades_thenRetryPaysNewTreasury] |

## Overlapping debt buckets

| ID | Caller | Shared recipient | Positive bucket mask | Amount domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RTRY-P05 | Any caller, fuzz | One address resolves for every selected bucket | Fuzz every nonempty configured/yield/Treasury mask | Independent positive quantities whose sum does not overflow | One transfer of the exact combined entitlement | Clear selected buckets once; aggregate reserve and indexes clear; repeat retry is silent | Covered: [historical integration][test_givenPendingConfiguredRecipientBecomesTreasury_whenNewReceiptsArrive_paysBoth], [all masks and quantities][test_givenCombinedPendingBuckets_whenRetried_paysOneCombinedTransfer] |

[test_givenPendingTreasury_whenPolicyInactiveAndTreasuryUpgrades_thenRetryWaitsForReactivation]: ./transferPendingPayout.t.sol#L346
[test_givenPendingRecipient_whenDistributorDisabled_thenRetryWaitsForReEnable]: ./transferPendingPayout.t.sol#L383
[test_givenRetiredAssetAndDisabledDistributor_retryWaitsForReEnable]: ./transferPendingPayout.t.sol#L219
[test_givenNoPendingPayout_noOps]: ./transferPendingPayout.t.sol#L68
[test_givenTwoPendingRecipients_whenFirstStillBlocked_thenSecondCanRetryDirectly]: ./transferPendingPayout.t.sol#L251
[test_givenTreasuryPayoutPending_whenTreasuryUpgrades_thenRetryPaysNewTreasury]: ./transferPendingPayout.t.sol#L413
[test_givenPendingConfiguredRecipientBecomesTreasury_whenNewReceiptsArrive_paysBoth]: ./transferPendingPayout.t.sol#L154
[test_givenPendingPayout_whenTokenReentersRetry_thenPayoutOccursOnce]: ./transferPendingPayout.t.sol#L626
[test_givenNoPendingPayout_whenInputsAreArbitrary_noOps]: ./transferPendingPayout.t.sol#L23
[test_givenNeverListedContractWithNoPendingPayout_whenRetried_noOps]: ./transferPendingPayout.t.sol#L43
[test_givenCombinedPendingBuckets_whenRetried_paysOneCombinedTransfer]: ./transferPendingPayout.t.sol#L779
[test_givenCombinedPendingBuckets_whenTransferReturnsFalse_defersThenRetries]: ./transferPendingPayout.t.sol#L830
[test_givenPendingPayout_whenTransferReverts_defersThenRetries]: ./transferPendingPayout.t.sol#L869
[test_givenPendingPayoutExceedsCustody_whenRetried_defersUntilFunded]: ./transferPendingPayout.t.sol#L893
[test_givenPendingPayout_whenTokenPropagatesReentrantFailure_defersPayout]: ./transferPendingPayout.t.sol#L750
[test_givenPolicyInactive_whenAnyRetryAttempted_revertsBeforeLocalState]: ./transferPendingPayout.t.sol#L80
[test_givenDistributorDisabled_whenAnyManagedAssetRetried_reverts]: ./transferPendingPayout.t.sol#L113
[test_givenConfiguredPayout_whenRetried_paysExactAmountAndIsolatesOtherDebt]: ./transferPendingPayout.t.sol#L296
[test_givenConfiguredPayoutAtMaximum_whenRetried_paysExactAmount]: ./transferPendingPayout.t.sol#L329
[test_givenTreasuryPayout_whenTreasuryUpgrades_retryUsesCurrentRole]: ./transferPendingPayout.t.sol#L446
[test_givenMaximumTreasuryPayout_whenTreasuryUpgrades_retryPaysMaximum]: ./transferPendingPayout.t.sol#L484
[test_givenYieldPayout_whenRecipientRotates_retryUsesCurrentRole]: ./transferPendingPayout.t.sol#L502
[test_givenMaximumYieldPayout_whenRecipientRotates_retryPaysMaximum]: ./transferPendingPayout.t.sol#L546
[test_givenYieldPayout_whenRecipientClears_retryUsesTreasuryFallback]: ./transferPendingPayout.t.sol#L567
[test_givenMaximumYieldPayout_whenRecipientClears_retryPaysTreasuryMaximum]: ./transferPendingPayout.t.sol#L606
[test_givenPendingPayout_whenTokenCatchesAnyGuardedNestedCall_paysOnce]: ./transferPendingPayout.t.sol#L654
[test_givenPendingPayout_whenTokenReadsGetter_callbackSeesPreDeliveryDebt]: ./transferPendingPayout.t.sol#L725
