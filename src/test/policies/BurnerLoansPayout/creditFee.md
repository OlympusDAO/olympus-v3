# BurnerLoansPayout.creditFee coverage plan

> Referral scenarios supplement the retained baseline. Their mappings identify the assertions for the extended API.

Source: [creditFee](../../../policies/burnerloans/BurnerLoansPayout.sol#L303). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-CREDIT-FEE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansPayout; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansPayout)` before body/input/idempotent work. Apply own Kernel activity before required local enablement and caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only immutable Core, with Payout active and its local guard. Core supplies token, protocolFee, referrer and referralFee; Payout resolves the fee destination from its own sendFeesToDistributor/revenueDistributor and Kernel Treasury, with the same helper used for later retry and entitlement reads. amount=protocolFee+referralFee:uint256 already received; backing requirement balance>=old totalPending+amount, even when amount=0.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits check own Kernel activity, then local enablement, then the immutable Core caller. Inactivity reports BurnerLoans_PolicyNotActive(Payout), a local pause reports NotEnabled(), and an operational Payout rejects non-Core callers with NotAuthorised(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(). During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingProtocolFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; pendingReferralFees R[recipient]; totalPendingKeeperRewards Kt=sum(K); totalPendingReferralFees Rt=sum(R); totalPending T=F+S+Kt+Rt. Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper; R follows original referrer. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Lifecycle

Core is the caller, local reentrancy guard is idle, valid backed input. There is no Core selection callback.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-L01 | Immutable Core | false | true | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCoreCredits_reverts][test_givenInactivePayout_whenCoreCredits_reverts] |
| BLCU-CREDIT-FEE-L02 | Immutable Core | true | false | NotEnabled() | Unchanged | Covered: [test_givenPausedPayout_whenCoreCredits_reverts][test_givenPausedPayout_whenCoreCredits_reverts] |
| BLCU-CREDIT-FEE-L03 | Immutable Core | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenInactivePayout_whenCoreCredits_reverts][test_givenInactivePayout_whenCoreCredits_reverts] |
| BLCU-CREDIT-FEE-L04 | Immutable Core | true | true | Success, including after enable following a pause | Exact fee accounting/attempted payout | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery][test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery] |

## Invalid inputs

Fixed for this table: Accounting / events: No new fee liability or transfer.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-I01 | Selected Core | balance=oldTotalPending+amount-1; amount>0 | BurnerLoansPayout_InsufficientBalance(token,balance,oldT+amount) | Covered: [test_givenInsufficientReceipt_whenFeeCredited_reverts][test_givenInsufficientReceipt_whenFeeCredited_reverts]; [test_givenReceiptOneUnitShort_whenCredited_reverts][test_givenReceiptOneUnitShort_whenCredited_reverts] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-N01 | Selected Core | P=R=0; referrer zero/nonzero; existing fee/referral pending or absent | Backing checked; no credit or retry at zero | No event/accounting changes | Covered: [test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry][test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry]; [test_givenPendingAndEmptyFeeSeeds_whenZeroCredited_thenNoRetry][test_givenPendingAndEmptyFeeSeeds_whenZeroCredited_thenNoRetry]; [test_givenPendingReferral_whenZeroAllocationCredited][test_givenPendingReferral_whenZeroAllocationCredited] |
| BLCU-CREDIT-FEE-N02 | Selected Core | amount1..MAX256 fitting aggregate; outgoing succeeds | Credit and attempt entire accumulated fee | Balance−oldF−amount; F cleared; T reduces paid sum; PayoutTransferred | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery][test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery]; [test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery][test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery]; [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery][test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery] |
| BLCU-CREDIT-FEE-N03 | Selected Core | oldTotalPending+amount>MAX256 | BurnerLoansPayout_AmountOverflow(oldT,amount) | No new fee liability or transfer | Covered: [test_givenPendingFees_whenAggregateOverflows_reverts][test_givenPendingFees_whenAggregateOverflows_reverts]; [test_givenPendingFees_whenNewAmountOverflows_thenExactError][test_givenPendingFees_whenNewAmountOverflows_thenExactError] |

## Successful execution

Fixed for this table: Accounting / events: Pending fee cleared; reserve reduced exactly once.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P01 | Selected Core | Final fee transfer returns no data and exact tokens are delivered | Credit succeeds; PayoutTransferred | Covered: [test_givenTokenReturnsNoData_whenCredited_thenDelivered][test_givenTokenReturnsNoData_whenCredited_thenDelivered] |

## Fee routing

Payout owns destination selection and outgoing delivery. Debt tests verify the exact Risk-returned fee reaches Payout and creditFee is called; they do not repeat these routing cases. Use positive new credit A and preexisting backed pending fee F in 0..MAX256-A, with a representable reserve and successful outgoing token. Guarantee F=0 and F>0 where representable. Other payout obligations remain unchanged.

| ID | Caller | sendFeesToDistributor | Selected distributor | Resolved recipient | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P03 | Selected Core | false | Valid configured distributor, ignored by this route | Kernel Treasury | Credit A and pay F+A once to Treasury; distributor unchanged; fee bucket cleared, reserve reduced by F+A; PayoutTransferred(Fee,F+A) | Covered: [test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery][test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery]; [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery][test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery] |
| BLCU-CREDIT-FEE-P04 | Selected Core | true | Valid configured distributor | Selected RevenueDistributor | Credit A and pay F+A once to distributor; Treasury unchanged; fee bucket cleared, reserve reduced by F+A; PayoutTransferred(Fee,F+A) | Covered: [test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery][test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery]; [test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery][test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery] |

N01 covers zero credit leaving existing fees untouched. D01/D02 cover payout failure remaining backed and pending; these are Payout assertions, independent of how the fee was calculated.

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-D01 | Selected Core | Final fee transfer reverts; preexisting fee allowed | Credit succeeds; PayoutDeferred | Fee/total reserve includes new amount; no recipient payment | Covered: [test_givenBlockedRecipient_whenCredited_thenCompleteFeeDeferred][test_givenBlockedRecipient_whenCredited_thenCompleteFeeDeferred] |
| BLCU-CREDIT-FEE-D02 | Selected Core | Final fee transfer returns false | Credit succeeds; PayoutDeferred | Fee remains fully reserved | Covered: [test_givenTransferReturnsFalse_whenCredited_thenFeeDeferred][test_givenTransferReturnsFalse_whenCredited_thenFeeDeferred] |

## Shared assertions

Test current and retired selection, caller spoofing, caller with operation role but not Core. Catch authorized nested same-Payout recovery at outgoing callback; propagation becomes fail-soft transfer failure, leaving backed pending obligation. Accepted token success may underpay destination for unsupported taxed tokens: do not claim outgoing exact-receipt guarantee.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-C01 | Immutable selected Core | Outgoing optional fee payout | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; delivery clears only its bucket once | Covered: [test_givenCaughtRecoveryCallback_whenFeeCredited_thenSingleDelivery][test_givenCaughtRecoveryCallback_whenFeeCredited_thenSingleDelivery] |
| BLCU-CREDIT-FEE-C02 | Immutable selected Core | Outgoing optional fee payout | Authorized nested Payout recovery or another credit via Core reaching Payout local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | New receipts stay fully reserved until delivery; unrelated tokens, keepers and retired/new Payout contracts isolated; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test_givenPropagatedRecoveryCallback_whenFeeCredited_thenDeferredAndRetryable][test_givenPropagatedRecoveryCallback_whenFeeCredited_thenDeferredAndRetryable] |

## Core selection independence

| ID | Caller | Core getter behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P07 | Immutable Core | payout() reverts; Payout itself active/enabled | Credit succeeds without reading Core selection | Exact credit/payout only | Covered: [test_givenCoreSelectionGetterRejects_whenCredited_thenNoSelectionRead][test_givenCoreSelectionGetterRejects_whenCredited_thenNoSelectionRead] |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-L05 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |
| BLCU-CREDIT-FEE-L06 | Non-Core caller | true | false | Otherwise valid credit | NotEnabled before the immutable Core caller check | Unchanged; no committed logs | Covered: [test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins][test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins] |

## Referral fee sharing: review draft

R10-R14,R18; AE1-AE8,AE13-AE19. creditFee(asset,protocolFee,referrer,referralFee) receives two separate allocations P and R, already funded by a combined receipt C=P+R. The uint256 amount named protocolFee is P, not the total collected. Payout does not calculate a percentage or subtract a reward from an overloaded fee argument, and does not call Risk or re-check its whitelist. Core supplies the exact components approved by Risk and passed through Debt. Getters pendingReferralFee(token,recipient) and getPendingReferralRecipients(token) expose the fixed bucket and its nonzero owners; pendingAmounts returns (protocolFee, referralFee, seized, keeperReward, total), where referralFee and keeperReward each sum their original recipients, and the four component reserves sum to total. Structural rule: referrer=0 requires referralFee=0; referrer≠0 permits referralFee=0. Reject referrer=0 with R>0 using the existing BurnerLoansCore_InvalidSettlement() error. Use existing BurnerLoansPayout_AmountOverflow(P,R) if the two components cannot be summed in uint256. There is no separate total-fee input against which to compare R. Reserve BOTH new allocations before either outgoing attempt. Keep protocol routing and old protocol-pending sweep behavior; referral ownership remains fixed by address. Append Referral to PayoutKind without renumbering existing values. Use only existing PayoutDeferred/PayoutTransferred with kind Referral; Debt owns per-origination attribution in Borrowed/Extended. Payout accepts no borrower/owner argument.

Per-token authoritative buckets: protocol fees Fp, seized collateral S, keeper K[a], referral Rf[a]; total T=Fp+S+sum(K)+sum(Rf). Pending token membership iff T>0; referral-recipient membership iff Rf[a]>0. P,R,C are uint256 raw collateral units, with C=P+R. P is added only to pendingProtocolFees; R is added only to the fixed-original recipient's referral bucket. Referrer nonzero with R=0 creates no referral index or reward event. A positive referral or protocol allocation addressed to Payout itself rejects before any liability is recorded. Zero referral allocation creates no recipient obligation. Default body rows have immutable Core caller and operational Payout. Unchanged includes bucket components/indexes, T, balances, allowances and logs.

Retain the existing immutable-Core caller test and N01 zero-credit case; adapt N01 to P=R=0 and seed referrer zero and nonzero without inventing another empty-credit matrix. The new cases below cover structural split validation and referral-specific accounting.

The referral-specific rows below map their named test proof. Existing scenario IDs and baseline expectations are retained; execution results are reported separately.

### Allocation validation

Existing reentrancy→own active→enabled→onlyCore admission remains first. Core has already transferred C when representable; otherwise the invalid call is tested directly with Core identity. Payout validates the zero-referrer rule, checked component sum, then full reserve backing. Nonzero referrer membership belongs to Risk and is not checked here; a direct Core fixture need not configure Risk. Numeric fields vary independently subject only to the row's stated sum constraint.

| ID | Caller | Protocol fee P | Referrer | Referral fee R | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-I03 | Core | Fuzz0..MAX256-R; seed P=0 and sum endpoint | Zero | Fuzz1..MAX256; seed1,MAX256 with representable C | BurnerLoansCore_InvalidSettlement() | Unchanged; reject the structural address/amount mismatch before delivery | Covered: [test_whenZeroReferrerHasPositiveReferralFee_reverts][test_whenZeroReferrerHasPositiveReferralFee_reverts], [test_whenZeroReferrerBoundarySeeds_reverts][test_whenZeroReferrerBoundarySeeds_reverts] |
| BLCU-CREDIT-FEE-N04 | Core | 0 | Nonzero | MAX256; old reserve0 | Success when backed | Only referral allocation MAX256; protocol increment0; no sum overflow | Covered: [test_whenReferralUsesFullUint256][test_whenReferralUsesFullUint256], [test_whenFullWidthAllocationsRemainPending][test_whenFullWidthAllocationsRemainPending] |
| BLCU-CREDIT-FEE-N05 | Core | Fuzz1..MAX256; seed1,MAX256 | Nonzero | 0 | Success when backed | Only protocol allocation P; r may be nonzero without a reward; no referral bucket/index/event or Risk lookup | Covered: [test_whenNonzeroReferrerHasZeroReferralFee][test_whenNonzeroReferrerHasZeroReferralFee], [test_whenNonzeroReferrerHasMaximumProtocolFee][test_whenNonzeroReferrerHasMaximumProtocolFee], [test_whenFullWidthAllocationsRemainPending][test_whenFullWidthAllocationsRemainPending] |
| BLCU-CREDIT-FEE-P11 | Core | Fuzz1..MAX256; seed1,MAX256 | Zero | 0 | Success when backed | Only protocol allocation P; exact creditFee(asset,P,zero,0) shape accepted | Covered: [test_whenNonzeroReferrerHasZeroReferralFee][test_whenNonzeroReferrerHasZeroReferralFee] |
| BLCU-CREDIT-FEE-N08 | Core | Fuzz1..MAX256; seed1,MAX256 | Nonzero | Fuzz(MAX256-P+1)..MAX256; seed first overflow,MAX256 | BurnerLoansPayout_AmountOverflow(P,R) | Unchanged; no backing read, partial reservation or outgoing transfer | Covered: [test_whenComponentsOverflow_reverts][test_whenComponentsOverflow_reverts], [test_whenComponentOverflowBoundarySeeds_reverts][test_whenComponentOverflowBoundarySeeds_reverts] |

### Attribution boundary

Debt's Borrowed/Extended events identify the borrower, referrer and new protocol/referral allocations. Payout receives no borrower or position metadata and emits only delivery/defer events, which may include earlier pending fees. Debt scenarios own per-operation event attribution; the Payout cases below prove token/referrer isolation and delivery amounts.

### Delivery outcomes

The call is creditFee(asset,76,referrer,25); combined token receipt C=101. Neither amount is interpreted as a gross-fee argument. No old buckets unless stated. All figures literal raw token units. Attempt outcome may be a normal revert or false token return, using existing optional-transfer helper semantics.

| ID | Caller | Referral delivery | Protocol delivery | Prior reserves | Execution | Balances / buckets / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P08 | Core | Succeeds | Succeeds | 0 | Success | Recipient +25; protocol +76; Payout -101; no new pending; Exactly one protocol and one referral PayoutTransferred event from Payout, carrying 76 and 25 respectively | Covered: [test_whenProtocolAndReferralBothDelivered][test_whenProtocolAndReferralBothDelivered], [test_whenFirstTransferObservesBothReservedComponents][test_whenFirstTransferObservesBothReservedComponents] |
| BLCU-CREDIT-FEE-T01 | Core | Fails | Succeeds | 0 | Success | Rf[original]=25,T=25; Payout retains 25; protocol receives76; PayoutTransferred(Fee,76) and PayoutDeferred(Referral,25) | Covered: [test_givenReferralDeliveryBlocked_whenFeeCredited][test_givenReferralDeliveryBlocked_whenFeeCredited] |
| BLCU-CREDIT-FEE-T02 | Core | Succeeds | Fails | 0 | Success | Rf=0; Fp=76,T=76; referrer +25; protocol unchanged | Covered: [test_givenProtocolDeliveryBlocked_whenFeeCredited][test_givenProtocolDeliveryBlocked_whenFeeCredited] |
| BLCU-CREDIT-FEE-T03 | Core | Fails | Fails | 0 | Success | Rf=25,Fp=76,T=101; both reserves funded and independently observable | Covered: [test_givenBothDeliveriesBlocked_whenFeeCredited][test_givenBothDeliveriesBlocked_whenFeeCredited], [test_whenFullWidthAllocationsRemainPending][test_whenFullWidthAllocationsRemainPending] |
| BLCU-CREDIT-FEE-P09 | Core | Same address as protocol; both succeed | Same recipient | K[a]=10,S=20,old Fp=30,old Rf[a]=40; all backed | Success | New receipt101 + old reserve100=201; protocol sweep106 and referral sweep65 pay171 to a; remaining K10+S20 gives T30. Distinct paid-kind events record protocol106 and referral65; per-origination new amounts are recorded only by Debt loan events. Rf/Fp cleared, unrelated K/S unchanged. | Covered: [test_givenOverlappingOldBuckets_whenNewReferralFeeAccrues][test_givenOverlappingOldBuckets_whenNewReferralFeeAccrues] |
| BLCU-CREDIT-FEE-T04 | Core | Positive referral1..MAX256, with representable protocol+referral sum | Referrer=Payout | No old buckets | BurnerLoansPayout_InvalidRecipient(Payout) before backing reads or delivery | No credit, indexes or outgoing transfer | Covered: [test_whenReferrerEqualsPayout_reverts][test_whenReferrerEqualsPayout_reverts], [test_whenSelfReferrerBoundarySeeds_reverts][test_whenSelfReferrerBoundarySeeds_reverts] |
| BLCU-CREDIT-FEE-P14 | Core | Zero referral allocation | Referrer=Payout | 0 | Success | Protocol76 is paid normally; no referral obligation is created | Covered: [test_whenReferrerEqualsPayout_whenReferralFeeZero][test_whenReferrerEqualsPayout_whenReferralFeeZero] |
| BLCU-CREDIT-FEE-T06 | Core | No referral allocation | Current protocol route=Payout, injected as malformed Kernel routing; positive protocol1..MAX256 is fully funded; seed1,MAX256 | 0 | BurnerLoansPayout_InvalidRecipient(Payout) | No credit or outgoing transfer | Covered: [test_givenProtocolRouteEqualsPayout_whenFeeBoundarySeeds_reverts][test_givenProtocolRouteEqualsPayout_whenFeeBoundarySeeds_reverts], [test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts][test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts] |

### Backing, overflow and callbacks

Only Core; defaults otherwise operational. New backing test includes old referral reserve even when other payout kinds are zero. Balance must cover old T plus C=P+R before optional transfers. Both P and R are reserved before either delivery attempt; a pre-existing balance cannot replace a missing new receipt.

| ID | Caller | Pre-state / fault | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-CREDIT-FEE-T05 | Core | Old Rf=25; C=P+R>0 representable; balance=25+C-1 | BurnerLoansPayout_InsufficientBalance(token,balance,25+C) | Unchanged; no allocation paid from old referral reserve | Covered: [test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts][test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts], [test_givenReferralReserve_whenShortReceiptBoundarySeeds_reverts][test_givenReferralReserve_whenShortReceiptBoundarySeeds_reverts] |
| BLCU-CREDIT-FEE-N07 | Core | Old referral-only reserve Rf=oldT>0; C=P+R representable but C>MAX256-oldT; seed Rf=1,P=0,R=MAX256 | BurnerLoansPayout_AmountOverflow(oldT,C) | Unchanged before transfers | Covered: [test_givenReferralReserve_whenCombinedReserveOverflows_reverts][test_givenReferralReserve_whenCombinedReserveOverflows_reverts], [test_givenReferralReserve_whenAggregateOverflowBoundarySeeds_reverts][test_givenReferralReserve_whenAggregateOverflowBoundarySeeds_reverts] |
| BLCU-CREDIT-FEE-P10 | Core | Repeated credits to repeated/distinct referrers R1/R2 and two assets; outgoing transfers deliberately defer | Success with funded pending referral fees | Liabilities aggregate only by asset/referrer; getters/indexes/total reconcile, and another asset or referrer cannot reassign an existing entitlement. | Covered: [test_givenDifferentRecipientsAndAssets_whenReferralFeesAccrue][test_givenDifferentRecipientsAndAssets_whenReferralFeesAccrue] |
| BLCU-CREDIT-FEE-C03 | Core | Referral transfer calls permissionless retry for same backed entitlement; catches exact Payout guard error | Outer credit succeeds | Nested ReentrancyGuardReentrantCall(); one credit/delivery; bucket, reserve and index not duplicated | Covered: [test_givenCaughtReferralCallback_whenFeeCredited][test_givenCaughtReferralCallback_whenFeeCredited] |
| BLCU-CREDIT-FEE-C04 | Core | Same otherwise-valid callback propagates nested error through token transfer | Outer credit succeeds with deferred referral | Optional transfer rolls back its subcall; full original R remains backed and pending | Covered: [test_givenPropagatedReferralCallback_whenFeeCredited][test_givenPropagatedReferralCallback_whenFeeCredited] |

### Reserve and recipient getter acceptance

These permissionless views remain independent of local enablement and Kernel membership. Existing lifecycle, full-width allocation, callback, retry and recovery cases retain their coverage. The new return component must reconcile after repeated/distinct referrers, independent tokens, failed delivery, successful retry and rescue of other buckets; the stateful accounting invariant checks it against the independent model.

| ID | Established state | Expected view | Test |
| --- | --- | --- | --- |
| BLCU-CREDIT-FEE-P12 | Protocol11, referral13+17, seized7, keeper5 remain pending | pendingAmounts=(11,30,7,5,53); every bucket is explicit and their sum equals total | Covered: [test_givenAllBucketsPending_whenReservesRead][test_givenAllBucketsPending_whenReservesRead] |
| BLCU-CREDIT-FEE-P13 | Two keepers; one overlaps referral, another referral distinct; fee route equals Treasury | Each of four owed addresses appears exactly once, in keeper/referrer/protocol order; pendingRecipientAmount includes all eligible buckets; empty token has no recipients | Covered: [test_givenOverlappingRecipientSets_whenRecipientsRead][test_givenOverlappingRecipientSets_whenRecipientsRead] |
| BLCU-CREDIT-FEE-L07 | Protocol11, referral25, seized13 and keeper7 pending; fuzz viewer and independent active/enabled booleans; deterministic caller0/MAX160 with all four state pairs | Every stored component and total56, keeper/referrer32, protocol recipient24, keeper bucket7 and deduplicated recipients remain readable before and after reactivation/re-enablement; claims and backing unchanged | Covered: [test_givenPendingReferral_whenReadUnderLifecycleStates][test_givenPendingReferral_whenReadUnderLifecycleStates], [test_givenPendingClaims_whenLifecycleBoundaryStates][test_givenPendingClaims_whenLifecycleBoundaryStates] |
| BLCU-CREDIT-FEE-P15 | Fuzz viewer, token and recipient addresses with no pending claims; explicit all-zero and MAX160 address seeds | pendingAmounts returns five zeros; pendingRecipientAmount, pendingKeeperReward and pendingReferralFee return0; recipient enumeration is empty; no ERC-20 call or lifecycle requirement | Covered: [test_whenPendingGettersReadForEmptyToken][test_whenPendingGettersReadForEmptyToken], [test_whenEmptyGetterBoundarySeeds][test_whenEmptyGetterBoundarySeeds] |

- [x] Review the referral cases before writing tests.

[test_whenZeroReferrerHasPositiveReferralFee_reverts]: creditFee.t.sol#L212
[test_whenZeroReferrerBoundarySeeds_reverts]: creditFee.t.sol#L625
[test_whenReferralUsesFullUint256]: creditFee.t.sol#L244
[test_whenFullWidthAllocationsRemainPending]: creditFee.t.sol#L644
[test_whenNonzeroReferrerHasZeroReferralFee]: creditFee.t.sol#L257
[test_whenNonzeroReferrerHasMaximumProtocolFee]: creditFee.t.sol#L639
[test_whenComponentsOverflow_reverts]: creditFee.t.sol#L227
[test_whenComponentOverflowBoundarySeeds_reverts]: creditFee.t.sol#L632
[test_whenProtocolAndReferralBothDelivered]: creditFee.t.sol#L280
[test_whenFirstTransferObservesBothReservedComponents]: creditFeeCallback.t.sol#L17
[test_givenReferralDeliveryBlocked_whenFeeCredited]: creditFee.t.sol#L308
[test_givenProtocolDeliveryBlocked_whenFeeCredited]: creditFee.t.sol#L340
[test_givenBothDeliveriesBlocked_whenFeeCredited]: creditFee.t.sol#L372
[test_givenOverlappingOldBuckets_whenNewReferralFeeAccrues]: creditFee.t.sol#L548
[test_givenDifferentRecipientsAndAssets_whenReferralFeesAccrue]: creditFee.t.sol#L578
[test_givenCaughtReferralCallback_whenFeeCredited]: creditFeeCallback.t.sol#L52
[test_givenPropagatedReferralCallback_whenFeeCredited]: creditFeeCallback.t.sol#L78

[test_givenOldReferralReserve_whenNewReceiptIsOneShort_reverts]: creditFee.t.sol#L472
[test_givenReferralReserve_whenShortReceiptBoundarySeeds_reverts]: creditFee.t.sol#L530
[test_givenReferralReserve_whenCombinedReserveOverflows_reverts]: creditFee.t.sol#L505
[test_givenReferralReserve_whenAggregateOverflowBoundarySeeds_reverts]: creditFee.t.sol#L540

[test_givenActivePausedPayout_whenNonCoreCredits_thenEnablementWins]: ./creditFee.t.sol#L964
[test_givenBlockedRecipient_whenCredited_thenCompleteFeeDeferred]: ./creditFee.t.sol#L854
[test_givenCaughtRecoveryCallback_whenFeeCredited_thenSingleDelivery]: ./creditFeeCallback.t.sol#L104
[test_givenCoreSelectionGetterRejects_whenCredited_thenNoSelectionRead]: ./creditFee.t.sol#L905
[test_givenFeeBoundarySeeds_whenCredited_thenCombinedDelivery]: ./creditFee.t.sol#L786
[test_givenInactivePayout_whenCoreCredits_reverts]: ./creditFee.t.sol#L699
[test_givenInsufficientReceipt_whenFeeCredited_reverts]: ./creditFee.t.sol#L664
[test_givenPausedPayout_whenCoreCredits_reverts]: ./creditFee.t.sol#L714
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./creditFee.t.sol#L951
[test_givenPendingAndEmptyFeeSeeds_whenZeroCredited_thenNoRetry]: ./creditFee.t.sol#L825
[test_givenPendingFee_whenDistributorCreditSucceeds_thenCombinedDelivery]: ./creditFee.t.sol#L759
[test_givenPendingFee_whenTreasuryCreditSucceeds_thenCombinedDelivery]: ./creditFee.t.sol#L733
[test_givenPendingFees_whenAggregateOverflows_reverts]: ./creditFee.t.sol#L682
[test_givenPendingFees_whenNewAmountOverflows_thenExactError]: ./creditFee.t.sol#L932
[test_givenPendingOrEmptyFee_whenZeroCredited_thenNoRetry]: ./creditFee.t.sol#L811
[test_givenPendingReferral_whenZeroAllocationCredited]: ./creditFee.t.sol#L607
[test_givenPropagatedRecoveryCallback_whenFeeCredited_thenDeferredAndRetryable]: ./creditFeeCallback.t.sol#L128
[test_givenReceiptOneUnitShort_whenCredited_reverts]: ./creditFee.t.sol#L833
[test_givenTokenReturnsNoData_whenCredited_thenDelivered]: ./creditFee.t.sol#L890
[test_givenTransferReturnsFalse_whenCredited_thenFeeDeferred]: ./creditFee.t.sol#L875
[test_givenAllBucketsPending_whenReservesRead]: ./creditFee.t.sol#L23
[test_givenOverlappingRecipientSets_whenRecipientsRead]: ./creditFee.t.sol#L182
[test_givenPendingReferral_whenReadUnderLifecycleStates]: ./creditFee.t.sol#L52
[test_whenReferrerEqualsPayout_reverts]: ./creditFee.t.sol#L405
[test_whenSelfReferrerBoundarySeeds_reverts]: ./creditFee.t.sol#L425
[test_whenReferrerEqualsPayout_whenReferralFeeZero]: ./creditFee.t.sol#L432
[test_givenProtocolRouteEqualsPayout_whenFeeCredited_reverts]: ./creditFee.t.sol#L443
[test_givenPendingClaims_whenLifecycleBoundaryStates]: ./creditFee.t.sol#L68
[test_whenPendingGettersReadForEmptyToken]: ./creditFee.t.sol#L128
[test_whenEmptyGetterBoundarySeeds]: ./creditFee.t.sol#L175
[test_givenProtocolRouteEqualsPayout_whenFeeBoundarySeeds_reverts]: ./creditFee.t.sol#L464
