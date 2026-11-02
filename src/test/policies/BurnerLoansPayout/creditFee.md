# BurnerLoansPayout.creditFee coverage plan

Source: [creditFee](../../../policies/burnerloans/BurnerLoansPayout.sol#L300). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CREDIT-FEE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansPayout; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansPayout)` before body/input/idempotent work. Apply own Kernel activity before required local enablement and caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only immutable Core, with Payout active and its local guard. Core supplies token/amount only; Payout resolves the fee destination from its own sendFeesToDistributor/revenueDistributor and Kernel Treasury, with the same helper used for later retry and entitlement reads. amount:uint256 already received; backing requirement balance>=old totalPending+amount, even when amount=0.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits check own Kernel activity, then local enablement, then the immutable Core caller. Inactivity reports BurnerLoans_PolicyNotActive(Payout), a local pause reports NotEnabled(), and an operational Payout rejects non-Core callers with NotAuthorised(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(). During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; totalPending T=F+S+sum(K). Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Lifecycle

Core is the caller, local reentrancy guard is idle, valid backed input. There is no Core selection callback.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-L01 | Immutable Core | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCoreCredits_reverts](./creditFee.t.sol#L56) |
| BLCU-CREDIT-FEE-L02 | Immutable Core | true | false | NotEnabled() | Unchanged | Covered: [test_givenPausedPayout_whenCoreCredits_reverts](./creditFee.t.sol#L71) |
| BLCU-CREDIT-FEE-L03 | Immutable Core | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCoreCredits_reverts](./creditFee.t.sol#L56) |
| BLCU-CREDIT-FEE-L04 | Immutable Core | true | true | Success, including after enable following a pause | Exact fee accounting/attempted payout | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery](./creditFee.t.sol#L90) |

## Invalid inputs

Fixed for this table: Accounting / events: No new fee liability or transfer.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-I01 | Selected Core | balance=oldTotalPending+amount-1; amount>0 | BurnerLoansPayout_InsufficientBalance(token,balance,oldT+amount) | Covered: [test_givenInsufficientReceipt_whenFeeCredited_reverts](./creditFee.t.sol#L21); [test_givenReceiptOneUnitShort_whenCredited_reverts](./creditFee.t.sol#L190) |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-N01 | Selected Core | amount=0, existing fee pending/nonpending | Backing checked; no credit or retry at zero | No event/accounting changes | Covered: [test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry](./creditFee.t.sol#L168); [test_givenPendingAndEmptyFeeSeeds_whenZeroCredited_thenNoRetry](./creditFee.t.sol#L182) |
| BLCU-CREDIT-FEE-N02 | Selected Core | amount1..MAX256 fitting aggregate; outgoing succeeds | Credit and attempt entire accumulated fee | Balance−oldF−amount; F cleared; T reduces paid sum; PayoutTransferred | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery](./creditFee.t.sol#L90); [test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery](./creditFee.t.sol#L116); [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery](./creditFee.t.sol#L143) |
| BLCU-CREDIT-FEE-N03 | Selected Core | oldTotalPending+amount>MAX256 | BurnerLoansPayout_AmountOverflow(oldT,amount) | No new fee liability or transfer | Covered: [test_givenPendingFees_whenAggregateOverflows_reverts](./creditFee.t.sol#L39); [test_givenPendingFees_whenNewAmountOverflows_thenExactError](./creditFee.t.sol#L289) |

## Successful execution

Fixed for this table: Accounting / events: Pending fee cleared; reserve reduced exactly once.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P01 | Selected Core | Final fee transfer returns no data and exact tokens are delivered | Credit succeeds; PayoutTransferred | Covered: [test_givenTokenReturnsNoData_whenCredited_thenDelivered](./creditFee.t.sol#L247) |

## Fee routing

Payout owns destination selection and outgoing delivery. Debt tests verify the exact Risk-returned fee reaches Payout and creditFee is called; they do not repeat these routing cases. Use positive new credit A and preexisting backed pending fee F in 0..MAX256-A, with a representable reserve and successful outgoing token. Guarantee F=0 and F>0 where representable. Other payout obligations remain unchanged.

| ID | Caller | sendFeesToDistributor | Selected distributor | Resolved recipient | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P03 | Selected Core | false | Valid configured distributor, ignored by this route | Kernel Treasury | Credit A and pay F+A once to Treasury; distributor unchanged; fee bucket cleared, reserve reduced by F+A; PayoutTransferred(Fee,F+A) | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery](./creditFee.t.sol#L90); [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery](./creditFee.t.sol#L143) |
| BLCU-CREDIT-FEE-P04 | Selected Core | true | Valid configured distributor | Selected RevenueDistributor | Credit A and pay F+A once to distributor; Treasury unchanged; fee bucket cleared, reserve reduced by F+A; PayoutTransferred(Fee,F+A) | Covered: [test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery](./creditFee.t.sol#L116); [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery](./creditFee.t.sol#L143) |

N01 covers zero credit leaving existing fees untouched. D01/D02 cover payout failure remaining backed and pending; these are Payout assertions, independent of how the fee was calculated.

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-D01 | Selected Core | Final fee transfer reverts; preexisting fee allowed | Credit succeeds; PayoutDeferred | Fee/total reserve includes new amount; no recipient payment | Covered: [test_givenBlockedRecipient_whenCredited_thenCompleteFeeDeferred](./creditFee.t.sol#L211) |
| BLCU-CREDIT-FEE-D02 | Selected Core | Final fee transfer returns false | Credit succeeds; PayoutDeferred | Fee remains fully reserved | Covered: [test_givenTransferReturnsFalse_whenCredited_thenFeeDeferred](./creditFee.t.sol#L232) |

## Shared assertions

Test current and retired selection, caller spoofing, caller with operation role but not Core. Catch authorized nested same-Payout recovery at outgoing callback; propagation becomes fail-soft transfer failure, leaving backed pending obligation. Accepted token success may underpay destination for unsupported taxed tokens: do not claim outgoing exact-receipt guarantee.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-C01 | Immutable selected Core | Outgoing optional fee payout | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; delivery clears only its bucket once | Covered: [test_givenCaughtRecoveryCallback_whenFeeCredited_thenSingleDelivery](./creditFeeCallback.t.sol#L15) |
| BLCU-CREDIT-FEE-C02 | Immutable selected Core | Outgoing optional fee payout | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test_givenPropagatedRecoveryCallback_whenFeeCredited_thenDeferredAndRetryable](./creditFeeCallback.t.sol#L39) |

## Core selection independence

| ID | Caller | Core getter behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P07 | Immutable Core | payout() reverts; Payout itself active/enabled | Credit succeeds without reading Core selection | Exact credit/payout only | Covered: [test_givenCoreSelectionGetterRejects_whenCredited_thenNoSelectionRead](./creditFee.t.sol#L262) |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-L05 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins](./creditFee.t.sol#L308) |
| BLCU-CREDIT-FEE-L06 | Non-Core caller | true | false | Otherwise valid credit | NotEnabled before the immutable Core caller check | Unchanged; no committed logs | Covered: [test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins](./creditFee.t.sol#L321) |
