# BurnerLoansPayout.transferPendingPayout coverage plan

> Referral scenarios supplement the retained baseline. Their mappings identify the assertions for the extended API.

Source: [transferPendingPayout](../../../policies/burnerloans/BurnerLoansPayout.sol#L370). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope `BLCUTRY`: BurnerLoansPayout.transferPendingPayout.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

Permissionless in current or previous Payout, outside Core settlement. recipient may equal fee route/Treasury/keeper in all combinations. Buckets payable now: F only for current fee route, S only current Treasury, K only the original keeper, and R only the original referrer.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits require the immutable Core caller, own Kernel activity and local enablement. Inactive Payout fails BurnerLoans_PolicyNotActive(Payout) before caller authorization; active non-Core caller fails NotAuthorised(); paused Payout fails NotEnabled(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(), followed by own activity before authority, inputs or token work. During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingProtocolFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; pendingReferralFees R[recipient]; totalPendingKeeperRewards Kt=sum(K); totalPendingReferralFees Rt=sum(R); totalPending T=F+S+Kt+Rt. Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper; R follows original referrer. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Successful execution

| ID | Caller | Recipient entitlement | Outgoing behavior | Execution / return | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P01 | Fuzz all callers | None or all buckets zero | No calls | Return0 | No debit/event | Covered: [test_givenNoEntitlement_whenRetried_thenNoCallsOrEvents][test_givenNoEntitlement_whenRetried_thenNoCallsOrEvents] |
| BLCUTRY-P02 | Fuzz all callers | F=10 only; recipient=current fee route | Success | Return 10 | Clear F and T; remove token index | Covered: [test_givenFeeOnly_whenRetried_thenExactEligibleBuckets][test_givenFeeOnly_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-T01 | Fuzz all callers | Eligible subset with unrelated recipients/tokens also owed | Revert/false for each bucket independently | Return only successful amounts; no outer revert on ordinary payout failure | Failed buckets stay pending with PayoutDeferred; others pay once | Covered: [test_givenFirstSharedBucketFails_whenRetried_thenLaterBucketsStillPaid][test_givenFirstSharedBucketFails_whenRetried_thenLaterBucketsStillPaid]; [test_givenSecondSharedBucketReturnsFalse_whenRetried_thenOnlySeizureRetained][test_givenSecondSharedBucketReturnsFalse_whenRetried_thenOnlySeizureRetained]; [test_givenLastSharedBucketFails_whenRetried_thenOnlyKeeperRetained][test_givenLastSharedBucketFails_whenRetried_thenOnlyKeeperRetained] |
| BLCUTRY-P03 | Fuzz all callers | Fee/Treasury routes changed; recipient=old route or current route | Success | Old route pays only its K; current receives generic F/S | K entitlement never follows route change | Covered: [test_givenTreasuryReplacement_whenRetried_thenGenericBucketsFollowLiveModule][test_givenTreasuryReplacement_whenRetried_thenGenericBucketsFollowLiveModule]; [test_givenFeeFlagRotation_whenRetried_thenFeeMovesAndKeeperStays][test_givenFeeFlagRotation_whenRetried_thenFeeMovesAndKeeperStays] |

## Shared assertions

Test token failure with reverted callback (pending retained) versus caught callback (payment once). Pending enumeration/default reads may run inside callback but do not authorize another payment. A previous Payout retry may touch a new Payout during an outgoing callback: independent ledger domains must remain separately conserved.

Co-located API assertions: `pendingRecipientAmount`, `pendingAmounts`, `pendingKeeperReward`, `pendingReferralFee`, `getPendingPayoutTokens`, `getPendingPayoutRecipients`, `getPendingKeepers`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Port fee flag/distributor/Treasury rotation with former route still originalkeeper, overlapping three buckets paid once in order, selected bucket failure preserving only failed remainder, transfer requiring more than former gas cap, short/empty token returndata, and keeper reward pending during Heart execution (no automatic payout sweep).

## Callbacks and reentrancy

| ID | Caller | Guard entered / route | Error propagation | Nested execution | Outer effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-C01 | Callback token contract | Core settles through an authorized action; incoming token callback calls this permissionless retry | Callback catches nested error | Nested ReentrancyGuardReentrantCall() | One outer settlement; no premature payout credit/debit | Covered: [test_givenCaughtIncomingCallback_whenCoreSettles_thenNoPrematureRecovery][test_givenCaughtIncomingCallback_whenCoreSettles_thenNoPrematureRecovery] |
| BLCUTRY-C02 | Callback token contract | Core settles through an authorized action; incoming token callback calls this permissionless retry | Callback propagates nested error | Nested ReentrancyGuardReentrantCall() | Outer Core transaction fully reverts | Covered: [test_givenPropagatedIncomingCallback_whenCoreSettles_thenOuterRollback][test_givenPropagatedIncomingCallback_whenCoreSettles_thenOuterRollback] |
| BLCUTRY-C03 | Callback token contract | Same Payout is paying a pending bucket; outgoing token callback calls this permissionless retry | Callback catches nested error | Nested ReentrancyGuardReentrantCall() | One outer bucket payment; no second debit | Covered: [test_givenCaughtNestedRetry_whenRetried_thenOnePayment][test_givenCaughtNestedRetry_whenRetried_thenOnePayment] |
| BLCUTRY-C04 | Callback token contract | Same Payout is paying a pending bucket; outgoing token callback calls this permissionless retry | Callback propagates nested error | Nested ReentrancyGuardReentrantCall() | Outer payout attempt defers selected bucket; pending remains owed | Covered: [test_givenPropagatedNestedRetry_whenRetried_thenPendingRetained][test_givenPropagatedNestedRetry_whenRetried_thenPendingRetained] |

## Distinct bucket combinations

Raw token units: fee F=10, Treasury seizure S=20, original keeper K=30. Only listed positive buckets exist, except where another recipient is stated. Each case has an actual permitted recipient overlap rather than a fuzzed allocation formula.

| ID | Caller | F | S | K | Recipient identity | Returned amount | Accounting and effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P04 | Fuzz all callers | 0 | 20 | 0 | Treasury | 20 | S=T=0; remove token | Covered: [test_givenSeizureOnly_whenRetried_thenExactEligibleBuckets][test_givenSeizureOnly_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P05 | Fuzz all callers | 0 | 0 | 30 | Original keeper | 30 | K=T=0; remove keeper/token | Covered: [test_givenKeeperOnly_whenRetried_thenExactEligibleBuckets][test_givenKeeperOnly_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P06 | Fuzz all callers | 10 | 20 | 0 | Fee route=Treasury | 30 | One debit per bucket; T=0 | Covered: [test_givenFeeAndSeizureOverlap_whenRetried_thenExactEligibleBuckets][test_givenFeeAndSeizureOverlap_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P07 | Fuzz all callers | 10 | 0 | 30 | Fee route=original keeper | 40 | F,K,T=0; remove keeper/token | Covered: [test_givenFeeAndKeeperOverlap_whenRetried_thenExactEligibleBuckets][test_givenFeeAndKeeperOverlap_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P08 | Fuzz all callers | 0 | 20 | 30 | Treasury=original keeper | 50 | S,K,T=0; remove keeper/token | Covered: [test_givenSeizureAndKeeperOverlap_whenRetried_thenExactEligibleBuckets][test_givenSeizureAndKeeperOverlap_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P09 | Fuzz all callers | 10 | 20 | 30 | Fee route=Treasury=original keeper | 60 | F→S→K each once; all reserves/indexes cleared | Covered: [test_givenAllBucketsOverlap_whenRetiredPausedPayoutClaims_thenEveryBucketPaidOnce][test_givenAllBucketsOverlap_whenRetiredPausedPayoutClaims_thenEveryBucketPaidOnce]; [test_givenAllBucketsOverlap_whenRetried_thenExactEligibleBuckets][test_givenAllBucketsOverlap_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P10 | Fuzz all callers | 10 | 20 | 30 | All routes distinct; retry only keeper | 30 | F=10,S=20,T=30; token remains, keeper removed | Covered: [test_givenAllRoutesDistinct_whenRetried_thenExactEligibleBuckets][test_givenAllRoutesDistinct_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P11 | Fuzz all callers | 10 | 20 | 30 | Unrelated recipient | 0 | No transfers/debits/index changes | Covered: [test_givenUnrelatedRecipient_whenRetried_thenExactEligibleBuckets][test_givenUnrelatedRecipient_whenRetried_thenExactEligibleBuckets] |
| BLCUTRY-P12 | Fuzz all callers | 10 | 20 | 30 | All equal; second keeper separately owed 7 | 60 | Other K=7 and T=7 retained; token/other keeper remain indexed | Covered: [test_givenSharedRecipientAndOtherKeeper_whenRetried_thenOnlySelectedClaimsPaid][test_givenSharedRecipientAndOtherKeeper_whenRetried_thenOnlySelectedClaimsPaid] |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-L02 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-L01 | Fuzz all callers | false | Fuzz true/false | BurnerLoans_PolicyNotActive(Payout) | All entitlements and balances unchanged | Covered: [test_givenPayoutInactive_whenRetried_reverts][test_givenPayoutInactive_whenRetried_reverts] |

## Referral fee sharing: review draft

The stateful handler keeps Payout Kernel-active while varying local pause, selection, routes and accounting. Credit-fee scenario L07 separately covers inactive and reactivated getter behavior.

R11-R14,R18,R20; AE14-AE17,AE19,AE21. Extend existing permissionless retry and pendingRecipientAmount getter with fixed-original referral entitlements `Rf[token][recipient]`. No whitelist or Risk percentage read occurs on retry, even after removal or replacement of Risk/Payout. Raw reserve and recipient/token enumeration must include referral obligations. Existing lifecycle remains: local guard, Core.requireNotReentrant(), own Kernel activity; no local enabled or current-selection requirement.

Default caller fuzzes every address including borrower, referrer and unrelated EOA/contract. Core outside settlement; balance backs total T=fees+seized+sum(keeper)+sum(referral). Fixed ownership applies to referral and keeper buckets; protocol fees/seized collateral retain existing current-route semantics. New rows do not redefine pre-existing bucket routing. Preserve the existing retry order Fee→Seizure→SeizureReward, then append Referral; exact kind/event order must match. Getter reads are permissionless and do not consume an entitlement.

Retained L01/L02, P01 and C01/C02 own inactivity, empty entitlements and the Core-settlement guard. Referral-kind delivery, ownership, category overlap and index changes remain new cases below.

The referral-specific rows below map their named test proof. Existing scenario IDs and baseline expectations are retained; execution results are reported separately.

### Referral retries and fixed ownership

Funded Rf[a]=25 unless stated. Unchanged includes exact bucket components and aggregate T, recipient and token sets, balances and events.

| ID | Caller | Referrer eligibility now | Payout active | Payout enabled | Core selected Payout | Delivery | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P13 | Fuzz every caller | Removed; bps changed to0 | true | Fuzz false/true; seed both | This or replacement; seed both | Accepts | Return25; a +25; old Payout -25; Rf[a] cleared; reserve -25; indexes remove only if empty | Covered: [test_givenReferralPending_whenRetriedAfterPauseAndReplacement][test_givenReferralPending_whenRetriedAfterPauseAndReplacement] |
| BLCUTRY-T02 | Fuzz every caller | Removed | true | Fuzz false/true | Either | Refuses | Return0; PayoutDeferred(kind Referral,25); exact original reserve/index remains | Covered: [test_givenReferralPending_whenRetriedAfterPauseAndReplacement][test_givenReferralPending_whenRetriedAfterPauseAndReplacement] |
| BLCUTRY-P14 | Fuzz every caller | Removed | true | true after re-enable/reactivation | Either | Accepts on second call | Failure then success then retry returns0; paid once with immutable token/recipient/amount; retry emits only delivery/defer events and no loan-origination event | Covered: [test_givenReferralPending_whenRetriedAfterPauseAndReplacement][test_givenReferralPending_whenRetriedAfterPauseAndReplacement], [test_givenFailedReferral_whenPayoutReEnabledAndReactivated][test_givenFailedReferral_whenPayoutReEnabledAndReactivated] |
| BLCUTRY-P15 | Fuzz every caller | R1 removed; R2 approved | true | true | Either | R2 accepts | Retry R2 cannot consume Rf[R1]; pendingRecipientAmount(R1) includes original reward; R2 gets only its own bucket | Covered: [test_givenTwoReferrers_whenOtherIdentityRetries][test_givenTwoReferrers_whenOtherIdentityRetries] |
| BLCUTRY-N01 | Fuzz every caller | Removed | true | true | Either | Accepts; Rf=1 or MAX256 and fully backed | Return exact Rf; no overflow; all reserves/indexes reconcile | Covered: [test_givenReferralMaximum_whenRetried][test_givenReferralMaximum_whenRetried], [test_givenOneReferralUnit_whenRetried][test_givenOneReferralUnit_whenRetried] |

### Overlapping categories and callback safety

R=40,K=10,protocol F=20,seized S=30, all independently reserved and funded. Guarantee each equality partition and all-distinct recipients; do not infer category clears from one filtered getter.

| ID | Caller | Recipient equality | Eligible amounts | Delivery | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P17 | Fuzz every caller | Referral recipient equals keeper only | R+K=50 | Accepts | Return50; R/K zero; F/S unchanged; T drops50; both recipient indexes correct | Covered: [test_givenReferralAndKeeperOverlap_whenRetried][test_givenReferralAndKeeperOverlap_whenRetried] |
| BLCUTRY-P18 | Fuzz every caller | Referral recipient equals fee route only | R+F=60 | Accepts | Return60; R/F zero; K/S unchanged; T drops60 | Covered: [test_givenReferralAndFeeOverlap_whenRetried][test_givenReferralAndFeeOverlap_whenRetried] |
| BLCUTRY-P19 | Fuzz every caller | Referral recipient equals Treasury only | R+S=70 | Accepts | Return70; R/S zero; F/K unchanged; T drops70 | Covered: [test_givenReferralAndTreasuryOverlap_whenRetried][test_givenReferralAndTreasuryOverlap_whenRetried] |
| BLCUTRY-P20 | Fuzz every caller | All four categories resolve to a | R+K+F+S=100 | Accepts | Return100; all raw buckets cleared once; token and appropriate recipient indexes removed | Covered: [test_givenAllCategoriesAndReferralOverlap_whenRetried][test_givenAllCategoriesAndReferralOverlap_whenRetried] |
| BLCUTRY-T03 | Fuzz every caller | All equal | R+K+F+S=100 | Token transfer attempts1/3 succeed,2/4 fail, matching fixed retry order | Return30=fee20+keeper10; raw F/K zero,S30/R40 remain; T70 and token/referral indexes retained; paid/deferred event kinds and amounts exact | Covered: [test_givenAllCategoriesAndAlternatingFailures_whenRetried][test_givenAllCategoriesAndAlternatingFailures_whenRetried] |
| BLCUTRY-C05 | Fuzz every caller | Referral-only a | 25 | Callback invokes otherwise-valid nested retry; catches guard rejection | Nested ReentrancyGuardReentrantCall(); outer return25; Rf=0,T=0, recipient/token indexes removed; one paid event | Covered: [test_givenReferralPending_whenCaughtCallbackRetries][test_givenReferralPending_whenCaughtCallbackRetries] |
| BLCUTRY-C07 | Fuzz every caller | Referral-only a | 25 | Same valid nested retry; token propagates Payout guard rejection | Outer return0; original Rf25/T25 and indexes retained; deferred Referral25, no paid event | Covered: [test_givenReferralPending_whenPropagatedCallbackRetries][test_givenReferralPending_whenPropagatedCallbackRetries] |

### Stateful properties

Add handler coverage alongside this action, not a new catch-all scenario file. Actor sequences may credit fees or seizures, retry, route/change bps, add/remove whitelist, pause/re-enable, replace selected Payout, and rescue existing surplus; constrain actions to their real authority and token support.

| ID | Caller / handler actors | Sequence domain | Invariant / effects | Test |
| --- | --- | --- | --- | --- |
| BLCUTRY-P21 | Authorized credit caller and fuzz retry callers | Two tokens, at least two referrers, failed/successful delivery, independently overlapping recipient classes | balance(Payout)≥T; T=all raw buckets; stored keeper/referral aggregates equal their per-recipient sums; token index iff T>0; referral-recipient index iff amount>0; each cumulative referral credit=paid+pending+authorized rescue; retries never pay another identity; settings never reprice earned amounts. Explicitly seed referral-only reserves, combined old-kind/new-kind reserves, balance=T and balance=T+1, plus MAX256 referral-only backing; explicit pending-payout rescue consumes only the approved original entitlement; seizure credits and surplus rescues must preserve the referral bucket and may not remove its live token index | Covered: [test_givenReferralOnly_whenModelRescuesBoundarySeeds][test_givenReferralOnly_whenModelRescuesBoundarySeeds], [invariant_backingBucketsIndexesAndRoutes][invariant_backingBucketsIndexesAndRoutes], [test_givenReferralOnlyAndMixedBuckets_whenModelBoundarySeeds][test_givenReferralOnlyAndMixedBuckets_whenModelBoundarySeeds], [test_givenMaximumReferralOnly_whenModelBoundarySeed][test_givenMaximumReferralOnly_whenModelBoundarySeed] |
| BLCUTRY-P22 | ADMIN/BLA/O plus unrelated callers | Configuration and lifecycle drift interleaved with real borrow/top-up/extend and deferred delivery | Only authorized mutations occur; unauthorized/lifecycle-rejected calls change nothing; gross receipts=protocol allocation+referral allocation and funded liabilities remain conserved | Covered: [invariant_referralReceiptsAndFixedFeesConserved][invariant_referralReceiptsAndFixedFeesConserved] |

Proof boundaries: the Payout accounting campaign uses two tokens, three overlapping recipient identities, bounded random credits, real Risk share/membership changes, actual Payout replacement/restoration and independently tracked surplus. Its deterministic seeds cover referral-only and mixed reserves at balance=T/T+1 plus MAX256 referral-only backing. The separate loan campaign uses one 6-decimal market, fixed prices/time, bounded principal, real borrow/top-up/extend, ADMIN/operator writes, rejected BLA/unrelated direct mutations and independent policy lifecycle changes. BLRCT scenarios own notice periods and BLA queue forwarding.

- [x] Review the referral cases before writing tests.

## Self-destination admission

| ID | Caller and state | Input / route drift | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLCUTRY-I02 | Fuzz permissionless caller; Payout active, Core idle | Protocol10 pending, current Treasury route is injected as Payout; retry recipient=Payout | BurnerLoansPayout_InvalidRecipient(Payout) at entry; no transfer, reserve/index debit or discharge of the old obligation | Covered: [test_givenProtocolRouteBecomesPayout_whenRetried_reverts][test_givenProtocolRouteBecomesPayout_whenRetried_reverts] |
| BLCUTRY-I03 | Fuzz permissionless caller; Payout active and independently enabled/paused; Core idle | Existing keeper, protocol and seizure reserves; retry recipient=0 | BurnerLoansPayout_InvalidRecipient(0) at entry; no transfer, reserve/index debit or discharge | Covered: [test_whenRecipientIsZero_reverts][test_whenRecipientIsZero_reverts] |

[test_givenReferralPending_whenRetriedAfterPauseAndReplacement]: transferPendingPayout.t.sol#L62
[test_givenFailedReferral_whenPayoutReEnabledAndReactivated]: transferPendingPayout.t.sol#L131
[test_givenTwoReferrers_whenOtherIdentityRetries]: transferPendingPayout.t.sol#L107
[test_givenReferralMaximum_whenRetried]: transferPendingPayout.t.sol#L161
[test_givenOneReferralUnit_whenRetried]: transferPendingPayout.t.sol#L176
[test_givenReferralAndKeeperOverlap_whenRetried]: transferPendingPayout.t.sol#L191
[test_givenReferralAndFeeOverlap_whenRetried]: transferPendingPayout.t.sol#L206
[test_givenReferralAndTreasuryOverlap_whenRetried]: transferPendingPayout.t.sol#L223
[test_givenAllCategoriesAndReferralOverlap_whenRetried]: transferPendingPayout.t.sol#L239
[test_givenAllCategoriesAndAlternatingFailures_whenRetried]: transferPendingPayout.t.sol#L260
[test_givenReferralPending_whenCaughtCallbackRetries]: transferPendingPayoutCallback.t.sol#L15
[test_givenReferralPending_whenPropagatedCallbackRetries]: transferPendingPayoutCallback.t.sol#L38

[invariant_backingBucketsIndexesAndRoutes]: accounting.invariants.t.sol#L76
[test_givenReferralOnlyAndMixedBuckets_whenModelBoundarySeeds]: accounting.invariants.t.sol#L246
[test_givenMaximumReferralOnly_whenModelBoundarySeed]: accounting.invariants.t.sol#L277
[invariant_referralReceiptsAndFixedFeesConserved]: ../BurnerLoansDebt/referralFees.invariant.t.sol#L120

[test_givenAllBucketsOverlap_whenRetiredPausedPayoutClaims_thenEveryBucketPaidOnce]: ./transferPendingPayout.t.sol#L290
[test_givenAllBucketsOverlap_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L686
[test_givenAllRoutesDistinct_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L705
[test_givenCaughtIncomingCallback_whenCoreSettles_thenNoPrematureRecovery]: ./transferPendingPayoutCallback.t.sol#L111
[test_givenCaughtNestedRetry_whenRetried_thenOnePayment]: ./transferPendingPayoutCallback.t.sol#L61
[test_givenFeeAndKeeperOverlap_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L647
[test_givenFeeAndSeizureOverlap_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L628
[test_givenFeeFlagRotation_whenRetried_thenFeeMovesAndKeeperStays]: ./transferPendingPayout.t.sol#L552
[test_givenFeeOnly_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L577
[test_givenFirstSharedBucketFails_whenRetried_thenLaterBucketsStillPaid]: ./transferPendingPayout.t.sol#L449
[test_givenKeeperOnly_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L611
[test_givenLastSharedBucketFails_whenRetried_thenOnlyKeeperRetained]: ./transferPendingPayout.t.sol#L497
[test_givenNoEntitlement_whenRetried_thenNoCallsOrEvents]: ./transferPendingPayout.t.sol#L333
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./transferPendingPayout.t.sol#L810
[test_givenPayoutInactive_whenRetried_reverts]: ./transferPendingPayout.t.sol#L797
[test_givenPropagatedIncomingCallback_whenCoreSettles_thenOuterRollback]: ./transferPendingPayoutCallback.t.sol#L133
[test_givenPropagatedNestedRetry_whenRetried_thenPendingRetained]: ./transferPendingPayoutCallback.t.sol#L85
[test_givenSecondSharedBucketReturnsFalse_whenRetried_thenOnlySeizureRetained]: ./transferPendingPayout.t.sol#L476
[test_givenSeizureAndKeeperOverlap_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L667
[test_givenSeizureOnly_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L594
[test_givenSharedRecipientAndOtherKeeper_whenRetried_thenOnlySelectedClaimsPaid]: ./transferPendingPayout.t.sol#L420
[test_givenTreasuryReplacement_whenRetried_thenGenericBucketsFollowLiveModule]: ./transferPendingPayout.t.sol#L521
[test_givenUnrelatedRecipient_whenRetried_thenExactEligibleBuckets]: ./transferPendingPayout.t.sol#L725
[test_givenReferralOnly_whenModelRescuesBoundarySeeds]: ./accounting.invariants.t.sol#L61
[test_givenProtocolRouteBecomesPayout_whenRetried_reverts]: ./transferPendingPayout.t.sol#L42
[test_whenRecipientIsZero_reverts]: transferPendingPayout.t.sol#L24
