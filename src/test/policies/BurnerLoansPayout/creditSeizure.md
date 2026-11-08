# BurnerLoansPayout.creditSeizure coverage plan

Source: [creditSeizure](../../../policies/burnerloans/BurnerLoansPayout.sol#L343). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CREDIT-SEIZURE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansPayout; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansPayout)` before body/input/idempotent work. Apply own Kernel activity before required local enablement and caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only immutable Core, local guard; reward,remainder:uint256 already received. Validate backing for reward+remainder before any payment; reward then Treasury attempts.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits check own Kernel activity, then local enablement, then the immutable Core caller. Inactivity reports BurnerLoans_PolicyNotActive(Payout), a local pause reports NotEnabled(), and an operational Payout rejects non-Core callers with NotAuthorised(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(). During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingProtocolFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; pendingReferralFees R[recipient]; totalPendingKeeperRewards Kt=sum(K); totalPendingReferralFees Rt=sum(R); totalPending T=F+S+Kt+Rt. Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper; R follows original referrer. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Authorization

Payout is active and enabled; the local guard is idle. On rejection there is no credit, token transfer or committed log.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-P02 | Fuzz caller excluding immutable Core | Caller is not immutable Core | NotAuthorised() | Covered: [test_whenCallerIsNotCore_reverts][test_whenCallerIsNotCore_reverts] |

## Lifecycle

Valid backed allocations; other prerequisites ready.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-L01 | Immutable Core | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCredited_reverts][test_givenInactivePayout_whenCredited_reverts] |
| BLCU-CREDIT-SEIZURE-L02 | Immutable Core | true | false | NotEnabled() | Unchanged | Covered: [test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain][test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain] |
| BLCU-CREDIT-SEIZURE-L03 | Immutable Core | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCredited_reverts][test_givenInactivePayout_whenCredited_reverts] |
| BLCU-CREDIT-SEIZURE-L04 | Immutable Core | true | true | Success | Exact keeper/Treasury allocation | Covered: [test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried][test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried]; [test_whenBothRecipientsAccept_thenBothBucketsPaid][test_whenBothRecipientsAccept_thenBothBucketsPaid]; [test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts][test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts] |

## Zero allocations

Fixed for this table: Accounting / events: Per-kind transfer/defer events only if pending positive.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-I01 | Selected Core | reward/remainder=0/nonzero independently; preexisting keeper and seizure buckets | Zero new allocation still retries old bucket | Covered: [test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried][test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried]; [test_whenBothRecipientsAccept_thenBothBucketsPaid][test_whenBothRecipientsAccept_thenBothBucketsPaid]; [test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts][test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts]; [test_givenExistingBuckets_whenNewRewardZero_thenBothOldBucketsRetried][test_givenExistingBuckets_whenNewRewardZero_thenBothOldBucketsRetried]; [test_givenExistingBuckets_whenNewSeizureZero_thenBothOldBucketsRetried][test_givenExistingBuckets_whenNewSeizureZero_thenBothOldBucketsRetried] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Both buckets and prior payments rollback.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-N01 | Immutable Core | oldT=5; reward=4; remainder=3; balance=11; all sums representable | BurnerLoansPayout_InsufficientBalance(token,11,12) | Unchanged; neither payout attempted | Covered: [test_givenPendingFees_whenSeizureReceiptIsShort_reverts][test_givenPendingFees_whenSeizureReceiptIsShort_reverts] |

## Configuration transitions

Fixed for this table: Accounting / events: No credit.

| ID | Caller | Prior configuration / update | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-P01 | Immutable Core | Old Payout disabled after Core selects its replacement | NotEnabled() | No new credit; old pending payouts remain recoverable | Covered: [test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain][test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: T=sum residual obligations; no merged overlap debit; balance/reserve correct.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-D01 | Selected Core | Keeper and Treasury transfer success/failure independently; addresses equal/distinct | Allocation retained or paid separately | Covered: [test_whenBothRecipientsAccept_thenBothBucketsPaid][test_whenBothRecipientsAccept_thenBothBucketsPaid]; [test_givenKeeperBlocked_whenCredited_thenOnlyRewardDeferred][test_givenKeeperBlocked_whenCredited_thenOnlyRewardDeferred]; [test_givenTreasuryBlocked_whenCredited_thenOnlySeizureDeferred][test_givenTreasuryBlocked_whenCredited_thenOnlySeizureDeferred]; [test_givenBothBlocked_whenCredited_thenBothBucketsDeferred][test_givenBothBlocked_whenCredited_thenBothBucketsDeferred]; [test_givenSharedRecipient_whenBothAccept_thenBothBucketsPaidOnce][test_givenSharedRecipient_whenBothAccept_thenBothBucketsPaidOnce] |
| BLCU-CREDIT-SEIZURE-D02 | Immutable Core | Positive reward1..MAX256, remainder0..MAX256-reward; keeper=Payout | BurnerLoansPayout_InvalidRecipient(Payout) before backing reads or delivery; all state unchanged | Covered: [test_whenKeeperEqualsPayout_reverts][test_whenKeeperEqualsPayout_reverts], [test_whenSelfKeeperBoundarySeeds_reverts][test_whenSelfKeeperBoundarySeeds_reverts] |
| BLCU-CREDIT-SEIZURE-D03 | Immutable Core | Keeper5, seized7; current Treasury=Payout, injected as malformed Kernel routing; receipt12 funded | BurnerLoansPayout_InvalidRecipient(Payout) before either bucket is credited or either transfer attempted | Covered: [test_givenTreasuryEqualsPayout_whenSeizureCredited_reverts][test_givenTreasuryEqualsPayout_whenSeizureCredited_reverts] |
| BLCU-CREDIT-SEIZURE-P03 | Immutable Core | Keeper=Payout but reward0; seized7 to valid Treasury | Success; no keeper obligation, Treasury receives7 | Covered: [test_whenKeeperEqualsPayout_whenRewardZero][test_whenKeeperEqualsPayout_whenRewardZero] |
| BLCU-CREDIT-SEIZURE-D04 | Immutable Core | Keeper=0, reward fuzz1..MAX256, seized fuzz0..MAX256-reward; seed reward1,MAX256 and combined MAX256 | BurnerLoansPayout_InvalidRecipient(0) before backing reads or delivery; all buckets and custody unchanged | Covered: [test_whenKeeperIsZero_whenRewardPositive_reverts][test_whenKeeperIsZero_whenRewardPositive_reverts], [test_whenZeroKeeperRewardBoundarySeeds_reverts][test_whenZeroKeeperRewardBoundarySeeds_reverts] |
| BLCU-CREDIT-SEIZURE-P05 | Immutable Core | Keeper=0, reward0, seized7 to valid Treasury | Success; no zero-address keeper claim or index; Treasury receives7 | Covered: [test_whenKeeperIsZero_whenRewardZero][test_whenKeeperIsZero_whenRewardZero] |

## Shared assertions

Recipient/token enumeration must agree with underlying keeper membership and all buckets. The token-wide keeper reserve is stored explicitly and must equal the sum of the per-keeper rewards after credit, successful or failed delivery, retry and authorized rescue. Record callback reads: obligations can be transient during outgoing token call; guard protects mutations, not a final read oracle. No migration when replacement selected.

| ID | Established state and viewer | Expected getters | Test |
| --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-P04 | Fuzz permissionless viewer; one recipient owns keeper11, referral13, protocol7 and seized17; another keeper3 and another token5; zero/unknown token or keeper | pendingKeeperReward isolates11,3,5 and returns0 for absent claims; pendingRecipientAmount for the overlapping recipient is48; token-wide keeper aggregate14 and total51 | Covered: [test_givenOverlappingEntitlements_whenKeeperRewardRead][test_givenOverlappingEntitlements_whenKeeperRewardRead] |

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-C01 | Immutable selected Core | Outgoing optional keeper and Treasury payouts; independently trigger each | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; delivery clears only its bucket once | Covered: [test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce][test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce]; [test_givenEachTransferPhase_whenCaughtCallback_thenBothPaidOnce][test_givenEachTransferPhase_whenCaughtCallback_thenBothPaidOnce] |
| BLCU-CREDIT-SEIZURE-C02 | Immutable selected Core | Outgoing optional keeper and Treasury payouts; independently trigger each | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test_givenKeeperCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred][test_givenKeeperCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred]; [test_givenTreasuryCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred][test_givenTreasuryCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred] |

## Allocation overflow

| ID | Caller | Existing reserve | Reward | Remainder | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-N02 | Immutable Core | 0 | MAX256 | 1 | BurnerLoansPayout_AmountOverflow(MAX256,1) | No credit or payout | Covered: [test_whenRewardAndRemainderOverflow_reverts][test_whenRewardAndRemainderOverflow_reverts]; [test_whenAllocationSumOverflows_thenExactError][test_whenAllocationSumOverflows_thenExactError] |
| BLCU-CREDIT-SEIZURE-N03 | Immutable Core | 5 | MAX256-5 | 1 | BurnerLoansPayout_AmountOverflow(5,MAX256-4) | Original obligations unchanged | Covered: [test_givenPendingReserve_whenCombinedCreditOverflows_reverts][test_givenPendingReserve_whenCombinedCreditOverflows_reverts]; [test_givenExistingReserve_whenTotalOverflows_thenExactError][test_givenExistingReserve_whenTotalOverflows_thenExactError] |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-L05 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |
| BLCU-CREDIT-SEIZURE-L06 | Non-Core caller | true | false | Otherwise valid credit | NotEnabled before the immutable Core caller check | Unchanged; no committed logs | Covered: [test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins][test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins] |

[test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins]: ./creditSeizure.t.sol#L445
[test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts]: ./creditSeizure.t.sol#L335
[test_givenBothBlocked_whenCredited_thenBothBucketsDeferred]: ./creditSeizure.t.sol#L312
[test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce]: ./creditSeizureCallback.t.sol#L12
[test_givenEachTransferPhase_whenCaughtCallback_thenBothPaidOnce]: ./creditSeizureCallback.t.sol#L106
[test_givenExistingBuckets_whenNewRewardZero_thenBothOldBucketsRetried]: ./creditSeizure.t.sol#L359
[test_givenExistingBuckets_whenNewSeizureZero_thenBothOldBucketsRetried]: ./creditSeizure.t.sol#L370
[test_givenExistingReserve_whenTotalOverflows_thenExactError]: ./creditSeizure.t.sol#L405
[test_givenInactivePayout_whenCredited_reverts]: ./creditSeizure.t.sol#L219
[test_givenKeeperBlocked_whenCredited_thenOnlyRewardDeferred]: ./creditSeizure.t.sol#L288
[test_givenKeeperCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred]: ./creditSeizureCallback.t.sol#L38
[test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried]: ./creditSeizure.t.sol#L254
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./creditSeizure.t.sol#L432
[test_givenPendingFees_whenSeizureReceiptIsShort_reverts]: ./creditSeizure.t.sol#L172
[test_givenPendingReserve_whenCombinedCreditOverflows_reverts]: ./creditSeizure.t.sol#L194
[test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain]: ./creditSeizure.t.sol#L233
[test_givenSharedRecipient_whenBothAccept_thenBothBucketsPaidOnce]: ./creditSeizure.t.sol#L324
[test_givenTreasuryBlocked_whenCredited_thenOnlySeizureDeferred]: ./creditSeizure.t.sol#L300
[test_givenTreasuryCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred]: ./creditSeizureCallback.t.sol#L72
[test_whenAllocationSumOverflows_thenExactError]: ./creditSeizure.t.sol#L381
[test_whenBothRecipientsAccept_thenBothBucketsPaid]: ./creditSeizure.t.sol#L275
[test_whenCallerIsNotCore_reverts]: ./creditSeizure.t.sol#L210
[test_whenRewardAndRemainderOverflow_reverts]: ./creditSeizure.t.sol#L157
[test_whenKeeperEqualsPayout_reverts]: ./creditSeizure.t.sol#L99
[test_whenSelfKeeperBoundarySeeds_reverts]: ./creditSeizure.t.sol#L119
[test_givenTreasuryEqualsPayout_whenSeizureCredited_reverts]: ./creditSeizure.t.sol#L137
[test_whenKeeperEqualsPayout_whenRewardZero]: ./creditSeizure.t.sol#L126
[test_givenOverlappingEntitlements_whenKeeperRewardRead]: ./creditSeizure.t.sol#L57
[test_whenKeeperIsZero_whenRewardPositive_reverts]: creditSeizure.t.sol#L19
[test_whenZeroKeeperRewardBoundarySeeds_reverts]: creditSeizure.t.sol#L43
[test_whenKeeperIsZero_whenRewardZero]: creditSeizure.t.sol#L50
