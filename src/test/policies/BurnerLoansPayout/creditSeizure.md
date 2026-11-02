# BurnerLoansPayout.creditSeizure coverage plan

Source: [creditSeizure](../../../policies/burnerloans/BurnerLoansPayout.sol#L320). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CREDIT-SEIZURE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansPayout; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansPayout)` before body/input/idempotent work. Apply own Kernel activity before required local enablement and caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only immutable Core, local guard; reward,remainder:uint256 already received. Validate backing for reward+remainder before any payment; reward then Treasury attempts.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits check own Kernel activity, then local enablement, then the immutable Core caller. Inactivity reports BurnerLoans_PolicyNotActive(Payout), a local pause reports NotEnabled(), and an operational Payout rejects non-Core callers with NotAuthorised(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(). During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; totalPending T=F+S+sum(K). Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Authorization

Payout is active and enabled; the local guard is idle. On rejection there is no credit, token transfer or committed log.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-P02 | Fuzz caller excluding immutable Core | Caller is not immutable Core | NotAuthorised() | Covered: [test_whenCallerIsNotCore_reverts](./creditSeizure.t.sol#L72) |

## Lifecycle

Valid backed allocations; other prerequisites ready.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-L01 | Immutable Core | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCredited_reverts](./creditSeizure.t.sol#L81) |
| BLCU-CREDIT-SEIZURE-L02 | Immutable Core | true | false | NotEnabled() | Unchanged | Covered: [test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain](./creditSeizure.t.sol#L95) |
| BLCU-CREDIT-SEIZURE-L03 | Immutable Core | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCredited_reverts](./creditSeizure.t.sol#L81) |
| BLCU-CREDIT-SEIZURE-L04 | Immutable Core | true | true | Success | Exact keeper/Treasury allocation | Covered: [test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried](./creditSeizure.t.sol#L116); [test_whenBothRecipientsAccept_thenBothBucketsPaid](./creditSeizure.t.sol#L137); [test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts](./creditSeizure.t.sol#L197) |

## Zero allocations

Fixed for this table: Accounting / events: Per-kind transfer/defer events only if pending positive.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-I01 | Selected Core | reward/remainder=0/nonzero independently; preexisting keeper and seizure buckets | Zero new allocation still retries old bucket | Covered: [test_givenOldBuckets_whenZeroAllocationsCredited_thenOldBucketsRetried](./creditSeizure.t.sol#L116); [test_whenBothRecipientsAccept_thenBothBucketsPaid](./creditSeizure.t.sol#L137); [test_givenAllocationBoundarySeeds_whenCredited_thenExactAmounts](./creditSeizure.t.sol#L197); [test_givenExistingBuckets_whenNewRewardZero_thenBothOldBucketsRetried](./creditSeizure.t.sol#L221); [test_givenExistingBuckets_whenNewSeizureZero_thenBothOldBucketsRetried](./creditSeizure.t.sol#L232) |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Both buckets and prior payments rollback.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-N01 | Immutable Core | oldT=5; reward=4; remainder=3; balance=11; all sums representable | BurnerLoansPayout_InsufficientBalance(token,11,12) | Unchanged; neither payout attempted | Covered: [test_givenPendingFees_whenSeizureReceiptIsShort_reverts](./creditSeizure.t.sol#L34) |

## Configuration transitions

Fixed for this table: Accounting / events: No credit.

| ID | Caller | Prior configuration / update | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-P01 | Immutable Core | Old Payout disabled after Core selects its replacement | NotEnabled() | No new credit; old pending payouts remain recoverable | Covered: [test_givenReplacedAndPausedPayout_whenCredited_revertsButClaimsRemain](./creditSeizure.t.sol#L95) |

## Transfers and dependency failures

Fixed for this table: Accounting / events: T=sum residual obligations; no merged overlap debit; balance/reserve correct.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-D01 | Selected Core | Keeper and Treasury transfer success/failure independently; addresses equal/distinct | Allocation retained or paid separately | Covered: [test_whenBothRecipientsAccept_thenBothBucketsPaid](./creditSeizure.t.sol#L137); [test_givenKeeperBlocked_whenCredited_thenOnlyRewardDeferred](./creditSeizure.t.sol#L150); [test_givenTreasuryBlocked_whenCredited_thenOnlySeizureDeferred](./creditSeizure.t.sol#L162); [test_givenBothBlocked_whenCredited_thenBothBucketsDeferred](./creditSeizure.t.sol#L174); [test_givenSharedRecipient_whenBothAccept_thenBothBucketsPaidOnce](./creditSeizure.t.sol#L186) |

## Shared assertions

Recipient/token enumeration must agree with underlying keeper membership and all buckets. Record callback reads: obligations can be transient during outgoing token call; guard protects mutations, not a final read oracle. No migration when replacement selected.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-C01 | Immutable selected Core | Outgoing optional keeper and Treasury payouts; independently trigger each | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; delivery clears only its bucket once | Covered: [test_givenCaughtCallback_whenKeeperOrTreasuryPaid_thenBothAllocationsOnce](./creditSeizureCallback.t.sol#L12); [test_givenEachTransferPhase_whenCaughtCallback_thenBothPaidOnce](./creditSeizureCallback.t.sol#L106) |
| BLCU-CREDIT-SEIZURE-C02 | Immutable selected Core | Outgoing optional keeper and Treasury payouts; independently trigger each | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test_givenKeeperCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred](./creditSeizureCallback.t.sol#L38); [test_givenTreasuryCallbackPropagates_whenCredited_thenOnlyItsBucketDeferred](./creditSeizureCallback.t.sol#L72) |

## Allocation overflow

| ID | Caller | Existing reserve | Reward | Remainder | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-N02 | Immutable Core | 0 | MAX256 | 1 | BurnerLoansPayout_AmountOverflow(MAX256,1) | No credit or payout | Covered: [test_whenRewardAndRemainderOverflow_reverts](./creditSeizure.t.sol#L19); [test_whenAllocationSumOverflows_thenExactError](./creditSeizure.t.sol#L243) |
| BLCU-CREDIT-SEIZURE-N03 | Immutable Core | 5 | MAX256-5 | 1 | BurnerLoansPayout_AmountOverflow(5,MAX256-4) | Original obligations unchanged | Covered: [test_givenPendingReserve_whenCombinedCreditOverflows_reverts](./creditSeizure.t.sol#L56); [test_givenExistingReserve_whenTotalOverflows_thenExactError](./creditSeizure.t.sol#L267) |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-SEIZURE-L05 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins](./creditSeizure.t.sol#L294) |
| BLCU-CREDIT-SEIZURE-L06 | Non-Core caller | true | false | Otherwise valid credit | NotEnabled before the immutable Core caller check | Unchanged; no committed logs | Covered: [test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins](./creditSeizure.t.sol#L307) |
