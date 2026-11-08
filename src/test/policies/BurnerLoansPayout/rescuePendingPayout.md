# BurnerLoansPayout.rescuePendingPayout coverage plan

> Referral scenarios supplement the retained baseline. Their mappings identify the assertions for the extended API.

Source: [rescuePendingPayout](../../../policies/burnerloans/BurnerLoansPayout.sol#L425). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-PENDING-RESCUE` identifies this contract/function.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

Fuzz permitted recovery callers independently of inputs: ADMIN-only, stored nonzero controller-only and overlap. Unauthorized fuzzing excludes every ADMIN and the selected nonzero controller. Current or previous Payout; outside settlement. amount:uint256 positive, <= combined entitlement A=K[recipient]+eligibleF+eligibleS. Address validation order: destination=Core first; token/excluded destination; recipient zero; amount zero; insufficient amount.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits require the immutable Core caller, own Kernel activity and local enablement. Inactive Payout fails BurnerLoans_PolicyNotActive(Payout) before caller authorization; active non-Core caller fails NotAuthorised(); paused Payout fails NotEnabled(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(), followed by own activity before authority, inputs or token work. During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingProtocolFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; pendingReferralFees R[recipient]; totalPendingKeeperRewards Kt=sum(K); totalPendingReferralFees Rt=sum(R); totalPending T=F+S+Kt+Rt. Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper; R follows original referrer. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-I01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | token=0; destination valid | BurnerLoans_InvalidAsset(token) | Covered: [test_givenZeroToken_whenRecovered_reverts][test_givenZeroToken_whenRecovered_reverts]; [test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts][test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | token is EOA; destination valid | BurnerLoans_InvalidAsset(token) | Covered: [test_givenEoaToken_whenRecovered_reverts][test_givenEoaToken_whenRecovered_reverts]; [test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts][test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I03 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=0 | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenZeroDestination_whenRecovered_reverts][test_givenZeroDestination_whenRecovered_reverts]; [test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I04 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenCoreDestination_whenRecovered_reverts][test_givenCoreDestination_whenRecovered_reverts]; [test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I05 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Payout | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenSelfDestination_whenRecovered_reverts][test_givenSelfDestination_whenRecovered_reverts]; [test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I06 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Config | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenControllerDestination_whenRecovered_reverts][test_givenControllerDestination_whenRecovered_reverts]; [test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I07 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenKernelDestination_whenRecovered_reverts][test_givenKernelDestination_whenRecovered_reverts]; [test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I08 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=token | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenTokenDestination_whenRecovered_reverts][test_givenTokenDestination_whenRecovered_reverts]; [test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-PENDING-RESCUE-I09 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Addresses valid; recipient=0 | BurnerLoans_ZeroAddress() | Covered: [test_whenRecipientZero_reverts][test_whenRecipientZero_reverts]; [test_givenEachRecoveryRole_whenRecipientZero_reverts][test_givenEachRecoveryRole_whenRecipientZero_reverts] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-N01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Addresses/recipient valid; amount=0 | BurnerLoansCore_ZeroAmount() | Unchanged; no committed logs | Covered: [test_whenAmountZero_reverts][test_whenAmountZero_reverts]; [test_givenEachRecoveryRole_whenAmountZero_reverts][test_givenEachRecoveryRole_whenAmountZero_reverts] |
| BLCU-PENDING-RESCUE-N02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Available A<MAX256; amount fuzz A+1..MAX256; seed both endpoints | BurnerLoans_InsufficientPendingPayout(token,amount,A) | Unchanged; no committed logs | Covered: [test_whenAmountExceedsEntitlement_reverts][test_whenAmountExceedsEntitlement_reverts]; [test_whenExcessAtIntervalEndpoints_reverts][test_whenExcessAtIntervalEndpoints_reverts]; [test_givenEachRecoveryRole_whenAmountExceedsEntitlement_reverts][test_givenEachRecoveryRole_whenAmountExceedsEntitlement_reverts]; [test_givenDistinctKeeper_givenFee_whenNoEligibleEntitlement_reverts][test_givenDistinctKeeper_givenFee_whenNoEligibleEntitlement_reverts]; [test_givenDistinctKeeper_givenSeizure_whenNoEligibleEntitlement_reverts][test_givenDistinctKeeper_givenSeizure_whenNoEligibleEntitlement_reverts]; [test_givenDistinctKeeper_givenFeeSeizure_whenNoEligibleEntitlement_reverts][test_givenDistinctKeeper_givenFeeSeizure_whenNoEligibleEntitlement_reverts]; [test_givenKeeperEqualsFee_givenSeizure_whenNoEligibleEntitlement_reverts][test_givenKeeperEqualsFee_givenSeizure_whenNoEligibleEntitlement_reverts]; [test_givenKeeperEqualsTreasury_givenFee_whenNoEligibleEntitlement_reverts][test_givenKeeperEqualsTreasury_givenFee_whenNoEligibleEntitlement_reverts]; [test_givenProtocolRoutesOverlap_givenKeeper_whenNoEligibleEntitlement_reverts][test_givenProtocolRoutesOverlap_givenKeeper_whenNoEligibleEntitlement_reverts]; [test_givenVariableEntitlement_whenAmountTooLarge_thenExactError][test_givenVariableEntitlement_whenAmountTooLarge_thenExactError] |
| BLCU-PENDING-RESCUE-N03 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Available A>0; amount fuzz1..A; seed1,A,MAX256 with funded compatible fixture | Success | Debit K then F then S eligibility; T decreases exactly amount; recipient-specific indexes conserved; strict transfer/event | Covered: [test_givenKeeperOnly_whenRedirected_thenExactAllocation][test_givenKeeperOnly_whenRedirected_thenExactAllocation]; [test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenFeeOnly_whenRedirected_thenExactAllocation][test_givenFeeOnly_whenRedirected_thenExactAllocation]; [test_givenSeizureOnly_whenRedirected_thenExactAllocation][test_givenSeizureOnly_whenRedirected_thenExactAllocation]; [test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation]; [test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation]; [test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation]; [test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup][test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Full debit/reserve/index rollback.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-D01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Valid debit; outgoing transfer reverts | Exact configured token error | Covered: [test_givenTransferReverts_whenRedirected_thenCompleteRollback][test_givenTransferReverts_whenRedirected_thenCompleteRollback]; [test_givenTransferReverts_givenEachRecoveryRole_whenRedirected_thenCompleteRollback][test_givenTransferReverts_givenEachRecoveryRole_whenRedirected_thenCompleteRollback] |
| BLCU-PENDING-RESCUE-D02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Valid debit; outgoing transfer returns false | SafeERC20FailedOperation(token) | Covered: [test_givenTransferReturnsFalse_whenRedirected_thenCompleteRollback][test_givenTransferReturnsFalse_whenRedirected_thenCompleteRollback]; [test_givenTransferReturnsFalse_givenEachRecoveryRole_whenRedirected_thenCompleteRollback][test_givenTransferReturnsFalse_givenEachRecoveryRole_whenRedirected_thenCompleteRollback] |

## Shared assertions

previewRescuePendingPayout returns full available entitlement A, not amount\_. It must validate the same recovery authority and settlement-busy state; validate these before quoting the entitlement. Seed amount0,1,A−1,A,A+1,MAX256 with compatible empty intervals excluded explicitly. Backed balance and entitlement are separate: preview may succeed while actual token transfer later fails. Use all seven nonempty bucket masks; no randomized overlap-only sampling.

Co-located API assertions: `previewRescuePendingPayout`, `pendingRecipientAmount`, `pendingAmounts`, `pendingKeeperReward`, `pendingReferralFee`, `getPendingPayoutTokens`, `getPendingPayoutRecipients`, `getPendingKeepers`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Reuse the extensive five recipient-role layouts ×seven bucket masks and guaranteed interval seed drivers, including MAX256 total entitlement, 3keeper isolation, 2token isolation, destination existingbalance, debtwithoutcustody transfer failure, partial/full callback read visibility, and caught/propagated authorized nested mutations.

## Bucket allocation and overlaps

All positive bucket amounts are independently fuzzed subject to representable T. Unmatched buckets may remain positive for other recipients and must be unchanged. Guarantee each listed recipient equality explicitly, not by random addresses. For each nonempty interval seed its first/last value, neighboring values within that interval, and Q=1 where applicable.

| ID | Caller | Eligible positive buckets | Recipient identities | Amount interval | Execution / debits | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-N07 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | K | recipient=keeper; fee/treasury distinct | Q in 1..K | Success; keeper/fee/seizure debit (Q,0,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenKeeperOnly_whenRedirected_thenExactAllocation][test_givenKeeperOnly_whenRedirected_thenExactAllocation]; [test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenKeeperOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenKeeperOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N08 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | F | recipient=fee; K=0; fee !=treasury | Q in 1..F | Success; keeper/fee/seizure debit (0,Q,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenFeeOnly_whenRedirected_thenExactAllocation][test_givenFeeOnly_whenRedirected_thenExactAllocation]; [test_givenFeeOnly_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenFeeOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenFeeOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenFeeOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N09 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | S | recipient=treasury; K=F=0 | Q in 1..S | Success; keeper/fee/seizure debit (0,0,Q) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenSeizureOnly_whenRedirected_thenExactAllocation][test_givenSeizureOnly_whenRedirected_thenExactAllocation]; [test_givenSeizureOnly_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenSeizureOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenSeizureOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenSeizureOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N10 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KF | keeper=fee !=treasury | Q in 1..K | Success; keeper/fee/seizure debit (Q,0,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndFeeBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperAndFeeBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenKeeperAndFeeBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N11 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KF | keeper=fee !=treasury | Q in K+1..K+F | Success; keeper/fee/seizure debit (K,Q-K,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndFeeAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperAndFeeAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenKeeperAndFeeAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenKeeperAndFeeAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N12 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KS | keeper=treasury !=fee | Q in 1..K | Success; keeper/fee/seizure debit (Q,0,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndSeizureBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperAndSeizureBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenKeeperAndSeizureBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N13 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KS | keeper=treasury !=fee | Q in K+1..K+S | Success; keeper/fee/seizure debit (K,0,Q-K) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation]; [test_givenKeeperAndSeizureAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenKeeperAndSeizureAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenKeeperAndSeizureAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenKeeperAndSeizureAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N14 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | FS | fee=treasury; K=0 | Q in 1..F | Success; keeper/fee/seizure debit (0,Q,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation]; [test_givenFeeAndSeizureBeforeFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenFeeAndSeizureBeforeFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenFeeAndSeizureBeforeFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureBeforeFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N15 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | FS | fee=treasury; K=0 | Q in F+1..F+S | Success; keeper/fee/seizure debit (0,F,Q-F) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation]; [test_givenFeeAndSeizureAfterFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenFeeAndSeizureAfterFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenFeeAndSeizureAfterFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenFeeAndSeizureAfterFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N16 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KFS | keeper=fee=treasury | Q in 1..K | Success; keeper/fee/seizure debit (Q,0,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinReward_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenAllBucketsWithinReward_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenAllBucketsWithinReward_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinReward_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N17 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KFS | keeper=fee=treasury | Q in K+1..K+F | Success; keeper/fee/seizure debit (K,Q-K,0) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinFee_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenAllBucketsWithinFee_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenAllBucketsWithinFee_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinFee_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |
| BLCU-PENDING-RESCUE-N18 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | KFS | keeper=fee=treasury | Q in K+F+1..K+F+S | Success; keeper/fee/seizure debit (K,F,Q-K-F) | T and balance -Q; only nonzero kind-specific rescue events; one token transfer | Covered: [test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation]; [test_givenAllBucketsWithinSeizure_whenQuantityAtIntervalSeeds_thenExactAllocation][test_givenAllBucketsWithinSeizure_whenQuantityAtIntervalSeeds_thenExactAllocation]; [test_givenAllBucketsWithinSeizure_givenEachRecoveryRole_whenRedirected_thenExactAllocation][test_givenAllBucketsWithinSeizure_givenEachRecoveryRole_whenRedirected_thenExactAllocation] |

## Destinations, isolation and indexes

Valid amount Q; use all eligible masks above. Valid destination flags are separate from entitlement identity.

| ID | Caller | Destination / post-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-P01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | destination=original recipient, not a forbidden address | Success | Preserve claim ownership; transfer Q once | Covered: [test_whenDestinationIsOriginalRecipient_thenOwnershipPreserved][test_whenDestinationIsOriginalRecipient_thenOwnershipPreserved]; [test_givenEachRecoveryRole_whenDestinationIsOriginalRecipient_thenOwnershipPreserved][test_givenEachRecoveryRole_whenDestinationIsOriginalRecipient_thenOwnershipPreserved] |
| BLCU-PENDING-RESCUE-P02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Fuzz distinct allowed EOA/contract; destination already has a token balance | Success | Destination +Q; no claim minted for destination | Covered: [test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases][test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases]; [test_whenDestinationIsContract_thenExistingBalancePreserved][test_whenDestinationIsContract_thenExistingBalancePreserved]; [test_givenEachRecoveryRole_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases][test_givenEachRecoveryRole_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases] |
| BLCU-PENDING-RESCUE-P03 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Allowed destination owns another pending keeper claim | Success | Its existing claim is unchanged; only selected recipient buckets debit | Covered: [test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation]; [test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved]; [test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation]; [test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved] |
| BLCU-PENDING-RESCUE-P04 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Q<A; selected keeper bucket remains positive | Success | Keeper index retained; token index retained; unrelated keepers/tokens untouched | Covered: [test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation]; [test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation] |
| BLCU-PENDING-RESCUE-P05 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Q drains K exactly; F/S or other keeper obligations remain | Success | Remove only that keeper index; token stays indexed | Covered: [test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved]; [test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved] |
| BLCU-PENDING-RESCUE-P06 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Q=T; no other token obligations | Success | Remove token pending index; all matched buckets zero | Covered: [test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup][test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup] |
| BLCU-PENDING-RESCUE-P07 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Payout balance=T+donated excess; Q<=A | Success | Donation remains excess after matching balance/liability debit; no extra entitlement | Covered: [test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation]; [test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved]; [test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation][test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation]; [test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved][test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved] |

## Recovery authorization

Core idle; valid recovery with positive entitlement. Payout enablement gates only new credits and direct yield-route use; recovery and routing repair ignore it. Stored controller lifecycle/Kernel/interface getters may reject because the target must not read them.

| ID | Caller | Request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-A01 | Fuzz excluding every ADMIN holder and stored nonzero controller; seed former controller | Valid recovery | NotAuthorised() | No reserve, balance, index or event change | Partial: [test_whenUnauthorizedRecovery_reverts][test_whenUnauthorizedRecovery_reverts]; [test_givenFormerController_whenRecovering_reverts][test_givenFormerController_whenRecovering_reverts]; execution authorization covered; preview authority and settlement-idle requirements remain pending the API decision |

## Recovery lifecycle

Seed ADMIN-only, stored-controller-only and overlap callers; otherwise valid positive recovery. Core must be idle. Current and retired instances retain independent obligations.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-L01 | Fuzz equivalent permitted recovery callers | true | Fuzz true/false | Fuzz true/false | Fuzz true/false | Success | Exact entitlement debit; other recipients/tokens unchanged | Covered: [test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable][test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable]; [test_givenPayoutActive_givenEachRecoveryRole_whenPendingRescued_thenRetiredClaimsAvailable][test_givenPayoutActive_givenEachRecoveryRole_whenPendingRescued_thenRetiredClaimsAvailable]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |
| BLCU-PENDING-RESCUE-L02 | Fuzz equivalent permitted recovery callers | false | Fuzz true/false | Fuzz true/false | Fuzz true/false | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts][test_givenPayoutInactive_whenCalled_reverts] |

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-C01 | ADMIN-only, stored controller-only or overlap; fuzz equivalent callers | Payout→recovery destination strict ERC20 transfer | Authorized nested recovery or permissionless retry reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One recovery transfer; only selected pending allocation consumed once; aggregate and recipient/token indexes agree | Covered: [test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce][test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce]; [test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce][test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce] |
| BLCU-PENDING-RESCUE-C02 | ADMIN-only, stored controller-only or overlap; fuzz equivalent callers | Payout→recovery destination strict ERC20 transfer | Authorized nested recovery or permissionless retry reaching Payout local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback][test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback]; [test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback][test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback] |

- [ ] Resolve the preview API decision: current previews do not enforce the authority and settlement-idle requirements above. Four isolated requirement tests reproduce the gap; production behavior is unchanged.

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-L04 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |

| ID | Sequence | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-L03 | Deactivate Payout; upgrade ROLES, revoke old ADMIN and grant new ADMIN without refreshing Payout; reactivate Payout | Inactive stale ADMIN cannot rescue or appoint an operator; reactivation refreshes cache and current ADMIN can rescue | No debit before reactivation; one exact entitlement debit afterward | Covered: [test_givenInactivePayoutAndRolesUpgrade_whenFormerAdminCalls_thenBlockedUntilReactivation][test_givenInactivePayoutAndRolesUpgrade_whenFormerAdminCalls_thenBlockedUntilReactivation] |

## Referral fee sharing: review draft

Authorized pending-payout rescue includes referral fees as well as keeper rewards, protocol fees and seized collateral. `pendingRecipientAmount` and `previewRescuePendingPayout` use the same complete entitlement. Keep the existing K→protocol fee→seized order and consume referral fees last. Ordinary retries continue to pay the original referrer; surplus rescue still excludes every pending liability.

Existing caller authorization, Kernel activity, disabled/retired operation, destination validation, settlement/reentrancy guards and strict-transfer rollback apply to referral rescue unchanged. These tests extend the existing acceptance matrix rather than duplicating unchanged guard coverage.

### Referral fees under authorized recovery

ADMIN or selected nonzero operator; Payout active and Core idle; local pause and replacement permitted. Unless stated: Rf[a]=40,K[a]=10,eligible protocol fee20,seized30; T=100 and balance100. Destination distinct and valid. All numeric amounts are raw token units.

| ID | Caller | Requested amount | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-P08 | ADMIN or operator | 1..100; seed1,10,11,30,31,60,61,99,100 | Success; preview100; K→protocol fee→seized→referral debit order | Exact amount transferred once; each component, aggregate, recipient/token indexes and backing agree with the remaining entitlement | Covered: [test_givenReferralAndOldCategories_whenCombinedAmountRedirected][test_givenReferralAndOldCategories_whenCombinedAmountRedirected], [test_givenAllBuckets_whenEntireEntitlementRescued][test_givenAllBuckets_whenEntireEntitlementRescued], [test_givenReferralAndOldCategories_whenRescueBoundarySeeds][test_givenReferralAndOldCategories_whenRescueBoundarySeeds] |
| BLCU-PENDING-RESCUE-I10 | ADMIN or operator | 101..MAX256; seed101,MAX256 | BurnerLoans_InsufficientPendingPayout(token,amount,100) | All accounting, indexes and custody unchanged | Covered: [test_givenReferralAndOldCategories_whenRescueExceedsCombinedEntitlement_reverts][test_givenReferralAndOldCategories_whenRescueExceedsCombinedEntitlement_reverts], [test_givenReferralAndOldCategories_whenRescueInvalidBoundarySeeds_reverts][test_givenReferralAndOldCategories_whenRescueInvalidBoundarySeeds_reverts] |
| BLCU-PENDING-RESCUE-P09 | ADMIN or operator; active Payout, independently locally paused and/or retired | Referral-only pending1..MAX256; requested1..pending; seed1,MAX256 and partial/full debit | Success; preview equals pending | Debit original referral and aggregate, remove index only when empty; pay exact destination; blocked retry cannot duplicate rescued amount | Covered: [test_givenOnlyReferral_whenRescued][test_givenOnlyReferral_whenRescued], [test_givenOnlyReferral_whenRescueBoundarySeeds][test_givenOnlyReferral_whenRescueBoundarySeeds] |
| BLCU-PENDING-RESCUE-P10 | ADMIN | K5+R13 for keeper distinct from protocol routes; rescue6; unrelated referrer7 and another token11 | Preview18; success | K5 then referral1 debited; protocol7,seized10,other recipient/token untouched | Covered: [test_givenDistinctProtocolRecipient_whenKeeperAndReferralRescued][test_givenDistinctProtocolRecipient_whenKeeperAndReferralRescued] |
| BLCU-PENDING-RESCUE-T02 | ADMIN | Referral25; destination transfer reverts, then accepts retry | Exact TransferReverted(destination); later success | Revert restores all referral reserves, indexes and custody; retry redirects25 once | Covered: [test_givenReferralPending_whenRescueTransferFails_reverts][test_givenReferralPending_whenRescueTransferFails_reverts] |

### Accounting visible during recovery transfer

| ID | Transfer-time read | Expected accounting | Test |
| --- | --- | --- | --- |
| BLCU-PENDING-RESCUE-C03 | Token reads after a partial keeper debit or after recovery reaches the referral bucket; seed first referral unit, last remaining unit and full debit | All source and aggregate debits and keeper/referrer/token indexes are already visible before the one strict transfer; the five-value reserve getter stays consistent | Covered: [test_givenPartialRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible][test_givenPartialRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible], [test_givenRecoveryIntoReferral_whenTokenReadsAccounting][test_givenRecoveryIntoReferral_whenTokenReadsAccounting], [test_givenRecoveryIntoReferral_whenReadBoundarySeeds][test_givenRecoveryIntoReferral_whenReadBoundarySeeds] |

- [x] Review the referral cases before writing tests.

[test_givenReferralAndOldCategories_whenRescueBoundarySeeds]: rescuePendingPayout.t.sol#L221
[test_givenReferralAndOldCategories_whenRescueInvalidBoundarySeeds_reverts]: rescuePendingPayout.t.sol#L251

[test_givenAllBucketsWithinFee_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1830
[test_givenAllBucketsWithinFee_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1172
[test_givenAllBucketsWithinFee_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1142
[test_givenAllBucketsWithinReward_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1810
[test_givenAllBucketsWithinReward_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1122
[test_givenAllBucketsWithinReward_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1092
[test_givenAllBucketsWithinSeizure_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1850
[test_givenAllBucketsWithinSeizure_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1222
[test_givenAllBucketsWithinSeizure_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1192
[test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce]: ./rescuePendingPayoutCallback.t.sol#L86
[test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce]: ./rescuePendingPayoutCallback.t.sol#L15
[test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1588
[test_givenControllerDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L602
[test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1560
[test_givenCoreDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L562
[test_givenDistinctKeeper_givenFeeSeizure_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2060
[test_givenDistinctKeeper_givenFee_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2010
[test_givenDistinctKeeper_givenSeizure_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2029
[test_givenEachRecoveryRole_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L1471
[test_givenEachRecoveryRole_whenAmountZero_reverts]: ./rescuePendingPayout.t.sol#L1457
[test_givenEachRecoveryRole_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases]: ./rescuePendingPayout.t.sol#L1887
[test_givenEachRecoveryRole_whenDestinationIsOriginalRecipient_thenOwnershipPreserved]: ./rescuePendingPayout.t.sol#L1870
[test_givenEachRecoveryRole_whenRecipientZero_reverts]: ./rescuePendingPayout.t.sol#L1630
[test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1532
[test_givenEoaToken_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L522
[test_givenFeeAndSeizureAfterFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1791
[test_givenFeeAndSeizureAfterFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1073
[test_givenFeeAndSeizureAfterFeeDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1045
[test_givenFeeAndSeizureBeforeFeeDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1772
[test_givenFeeAndSeizureBeforeFeeDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1026
[test_givenFeeAndSeizureBeforeFeeDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L998
[test_givenFeeOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1662
[test_givenFeeOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L748
[test_givenFeeOnly_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L721
[test_givenFormerController_whenRecovering_reverts]: ./rescuePendingPayout.t.sol#L318
[test_givenInactivePayoutAndRolesUpgrade_whenFormerAdminCalls_thenBlockedUntilReactivation]: ./rescuePendingPayout.t.sol#L262
[test_givenKeeperAndFeeAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1715
[test_givenKeeperAndFeeAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L883
[test_givenKeeperAndFeeAfterRewardDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L854
[test_givenKeeperAndFeeBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1696
[test_givenKeeperAndFeeBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L835
[test_givenKeeperAndFeeBeforeRewardDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L806
[test_givenKeeperAndSeizureAfterRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1753
[test_givenKeeperAndSeizureAfterRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L979
[test_givenKeeperAndSeizureAfterRewardDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L950
[test_givenKeeperAndSeizureBeforeRewardDrained_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1734
[test_givenKeeperAndSeizureBeforeRewardDrained_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L931
[test_givenKeeperAndSeizureBeforeRewardDrained_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L902
[test_givenKeeperEqualsFee_givenSeizure_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2127
[test_givenKeeperEqualsTreasury_givenFee_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2251
[test_givenKeeperOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1644
[test_givenKeeperOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L705
[test_givenKeeperOnly_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L679
[test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1602
[test_givenKernelDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L622
[test_givenOtherObligations_givenEachRecoveryRole_whenKeeperFullyRescued_thenOnlyItsIndexRemoved]: ./rescuePendingPayout.t.sol#L1921
[test_givenOtherObligations_whenKeeperFullyRescued_thenOnlyItsIndexRemoved]: ./rescuePendingPayout.t.sol#L1331
[test_givenPayoutActive_givenEachRecoveryRole_whenPendingRescued_thenRetiredClaimsAvailable]: ./rescuePendingPayout.t.sol#L1937
[test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable]: ./rescuePendingPayout.t.sol#L1956
[test_givenPayoutActive_whenPendingRescued_thenRetiredClaimsAvailable]: ./rescuePendingPayout.t.sol#L1386
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./rescuePendingPayout.t.sol#L2702
[test_givenPayoutInactive_whenCalled_reverts]: ./rescuePendingPayout.t.sol#L2682
[test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback]: ./rescuePendingPayoutCallback.t.sol#L99
[test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback]: ./rescuePendingPayoutCallback.t.sol#L50
[test_givenProtocolRoutesOverlap_givenKeeper_whenNoEligibleEntitlement_reverts]: ./rescuePendingPayout.t.sol#L2375
[test_givenSeizureOnly_givenEachRecoveryRole_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L1678
[test_givenSeizureOnly_whenQuantityAtIntervalSeeds_thenExactAllocation]: ./rescuePendingPayout.t.sol#L790
[test_givenSeizureOnly_whenRedirected_thenExactAllocation]: ./rescuePendingPayout.t.sol#L764
[test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1574
[test_givenSelfDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L582
[test_givenThreeKeepersAndTwoTokens_givenEachRecoveryRole_whenPartialKeeperRescued_thenIsolation]: ./rescuePendingPayout.t.sol#L1904
[test_givenThreeKeepersAndTwoTokens_whenPartialKeeperRescued_thenIsolation]: ./rescuePendingPayout.t.sol#L1319
[test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1616
[test_givenTokenDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L642
[test_givenTransferReturnsFalse_givenEachRecoveryRole_whenRedirected_thenCompleteRollback]: ./rescuePendingPayout.t.sol#L1502
[test_givenTransferReturnsFalse_whenRedirected_thenCompleteRollback]: ./rescuePendingPayout.t.sol#L383
[test_givenTransferReverts_givenEachRecoveryRole_whenRedirected_thenCompleteRollback]: ./rescuePendingPayout.t.sol#L1486
[test_givenTransferReverts_whenRedirected_thenCompleteRollback]: ./rescuePendingPayout.t.sol#L366
[test_givenVariableEntitlement_whenAmountTooLarge_thenExactError]: ./rescuePendingPayout.t.sol#L2655
[test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1546
[test_givenZeroDestination_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L542
[test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L1518
[test_givenZeroToken_whenRecovered_reverts]: ./rescuePendingPayout.t.sol#L502
[test_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L342
[test_whenAmountZero_reverts]: ./rescuePendingPayout.t.sol#L325
[test_whenDestinationIsContract_thenExistingBalancePreserved]: ./rescuePendingPayout.t.sol#L1309
[test_whenDestinationIsDistinctWithExistingBalance_thenOnlyBalanceIncreases]: ./rescuePendingPayout.t.sol#L1268
[test_whenDestinationIsOriginalRecipient_thenOwnershipPreserved]: ./rescuePendingPayout.t.sol#L1242
[test_whenExcessAtIntervalEndpoints_reverts]: ./rescuePendingPayout.t.sol#L1449
[test_whenMaximumEntitlementFullyRescued_thenMaximumDebitAndCompleteCleanup]: ./rescuePendingPayout.t.sol#L1411
[test_whenRecipientZero_reverts]: ./rescuePendingPayout.t.sol#L662
[test_whenUnauthorizedRecovery_reverts]: ./rescuePendingPayout.t.sol#L308
[test_givenReferralAndOldCategories_whenCombinedAmountRedirected]: ./rescuePendingPayout.t.sol#L28
[test_givenAllBuckets_whenEntireEntitlementRescued]: ./rescuePendingPayout.t.sol#L77
[test_givenReferralAndOldCategories_whenRescueExceedsCombinedEntitlement_reverts]: ./rescuePendingPayout.t.sol#L106
[test_givenOnlyReferral_whenRescued]: ./rescuePendingPayout.t.sol#L134
[test_givenOnlyReferral_whenRescueBoundarySeeds]: ./rescuePendingPayout.t.sol#L233
[test_givenDistinctProtocolRecipient_whenKeeperAndReferralRescued]: ./rescuePendingPayout.t.sol#L175
[test_givenReferralPending_whenRescueTransferFails_reverts]: ./rescuePendingPayout.t.sol#L196
[test_givenPartialRecovery_whenTokenReadsAccounting_thenDebitAlreadyVisible]: ./rescuePendingPayoutCallback.t.sol#L124
[test_givenRecoveryIntoReferral_whenTokenReadsAccounting]: ./rescuePendingPayoutCallback.t.sol#L155
[test_givenRecoveryIntoReferral_whenReadBoundarySeeds]: ./rescuePendingPayoutCallback.t.sol#L192
