# BurnerLoansPayout.transferPendingPayout coverage plan

Source: [transferPendingPayout](../../../policies/burnerloans/BurnerLoansPayout.sol#L343). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope `BLCUTRY`: BurnerLoansPayout.transferPendingPayout.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

Permissionless in current or previous Payout, outside Core settlement. recipient may equal fee route/Treasury/keeper in all combinations. Buckets payable now: F only for current fee route, S only current Treasury, K only that original recipient.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits require the immutable Core caller, own Kernel activity and local enablement. Inactive Payout fails BurnerLoans_PolicyNotActive(Payout) before caller authorization; active non-Core caller fails NotAuthorised(); paused Payout fails NotEnabled(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(), followed by own activity before authority, inputs or token work. During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; totalPending T=F+S+sum(K). Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Successful execution

| ID | Caller | Recipient entitlement | Outgoing behavior | Execution / return | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P01 | Fuzz all callers | None or all buckets zero | No calls | Return0 | No debit/event | Covered: [test_givenNoEntitlement_whenRetried_thenNoCallsOrEvents](./transferPendingPayout.t.sol#L67) |
| BLCUTRY-P02 | Fuzz all callers | F=10 only; recipient=current fee route | Success | Return 10 | Clear F and T; remove token index | Covered: [test_givenFeeOnly_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L311) |
| BLCUTRY-T01 | Fuzz all callers | Eligible subset with unrelated recipients/tokens also owed | Revert/false for each bucket independently | Return only successful amounts; no outer revert on ordinary payout failure | Failed buckets stay pending with PayoutDeferred; others pay once | Covered: [test_givenFirstSharedBucketFails_whenRetried_thenLaterBucketsStillPaid](./transferPendingPayout.t.sol#L183); [test_givenSecondSharedBucketReturnsFalse_whenRetried_thenOnlySeizureRetained](./transferPendingPayout.t.sol#L210); [test_givenLastSharedBucketFails_whenRetried_thenOnlyKeeperRetained](./transferPendingPayout.t.sol#L231) |
| BLCUTRY-P03 | Fuzz all callers | Fee/Treasury routes changed; recipient=old route or current route | Success | Old route pays only its K; current receives generic F/S | K entitlement never follows route change | Covered: [test_givenTreasuryReplacement_whenRetried_thenGenericBucketsFollowLiveModule](./transferPendingPayout.t.sol#L255); [test_givenFeeFlagRotation_whenRetried_thenFeeMovesAndKeeperStays](./transferPendingPayout.t.sol#L286) |

## Shared assertions

Test token failure with reverted callback (pending retained) versus caught callback (payment once). Pending enumeration/default reads may run inside callback but do not authorize another payment. A previous Payout retry may touch a new Payout during an outgoing callback: independent ledger domains must remain separately conserved.

Co-located API assertions: `pendingPayout`, `payoutReserves`, `getPendingPayoutTokens`, `getPendingPayoutRecipients`, `getPendingKeepers`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Port fee flag/distributor/Treasury rotation with former route still originalkeeper, overlapping three buckets paid once in order, selected bucket failure preserving only failed remainder, transfer requiring more than former gas cap, short/empty token returndata, and keeper reward pending during Heart execution (no automatic payout sweep).

## Callbacks and reentrancy

| ID | Caller | Guard entered / route | Error propagation | Nested execution | Outer effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-C01 | Callback token contract | Core settles through an authorized action; incoming token callback calls this permissionless retry | Callback catches nested error | Nested ReentrancyGuardReentrantCall() | One outer settlement; no premature payout credit/debit | Covered: [test_givenCaughtIncomingCallback_whenCoreSettles_thenNoPrematureRecovery](./transferPendingPayoutCallback.t.sol#L65) |
| BLCUTRY-C02 | Callback token contract | Core settles through an authorized action; incoming token callback calls this permissionless retry | Callback propagates nested error | Nested ReentrancyGuardReentrantCall() | Outer Core transaction fully reverts | Covered: [test_givenPropagatedIncomingCallback_whenCoreSettles_thenOuterRollback](./transferPendingPayoutCallback.t.sol#L87) |
| BLCUTRY-C03 | Callback token contract | Same Payout is paying a pending bucket; outgoing token callback calls this permissionless retry | Callback catches nested error | Nested ReentrancyGuardReentrantCall() | One outer bucket payment; no second debit | Covered: [test_givenCaughtNestedRetry_whenRetried_thenOnePayment](./transferPendingPayoutCallback.t.sol#L15) |
| BLCUTRY-C04 | Callback token contract | Same Payout is paying a pending bucket; outgoing token callback calls this permissionless retry | Callback propagates nested error | Nested ReentrancyGuardReentrantCall() | Outer payout attempt defers selected bucket; pending remains owed | Covered: [test_givenPropagatedNestedRetry_whenRetried_thenPendingRetained](./transferPendingPayoutCallback.t.sol#L39) |

## Distinct bucket combinations

Raw token units: fee F=10, Treasury seizure S=20, original keeper K=30. Only listed positive buckets exist, except where another recipient is stated. Each case has an actual permitted recipient overlap rather than a fuzzed allocation formula.

| ID | Caller | F | S | K | Recipient identity | Returned amount | Accounting and effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-P04 | Fuzz all callers | 0 | 20 | 0 | Treasury | 20 | S=T=0; remove token | Covered: [test_givenSeizureOnly_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L328) |
| BLCUTRY-P05 | Fuzz all callers | 0 | 0 | 30 | Original keeper | 30 | K=T=0; remove keeper/token | Covered: [test_givenKeeperOnly_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L345) |
| BLCUTRY-P06 | Fuzz all callers | 10 | 20 | 0 | Fee route=Treasury | 30 | One debit per bucket; T=0 | Covered: [test_givenFeeAndSeizureOverlap_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L362) |
| BLCUTRY-P07 | Fuzz all callers | 10 | 0 | 30 | Fee route=original keeper | 40 | F,K,T=0; remove keeper/token | Covered: [test_givenFeeAndKeeperOverlap_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L381) |
| BLCUTRY-P08 | Fuzz all callers | 0 | 20 | 30 | Treasury=original keeper | 50 | S,K,T=0; remove keeper/token | Covered: [test_givenSeizureAndKeeperOverlap_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L401) |
| BLCUTRY-P09 | Fuzz all callers | 10 | 20 | 30 | Fee route=Treasury=original keeper | 60 | F→S→K each once; all reserves/indexes cleared | Covered: [test_givenAllBucketsOverlap_whenRetiredPausedPayoutClaims_thenEveryBucketPaidOnce](./transferPendingPayout.t.sol#L24); [test_givenAllBucketsOverlap_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L420) |
| BLCUTRY-P10 | Fuzz all callers | 10 | 20 | 30 | All routes distinct; retry only keeper | 30 | F=10,S=20,T=30; token remains, keeper removed | Covered: [test_givenAllRoutesDistinct_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L439) |
| BLCUTRY-P11 | Fuzz all callers | 10 | 20 | 30 | Unrelated recipient | 0 | No transfers/debits/index changes | Covered: [test_givenUnrelatedRecipient_whenRetried_thenExactEligibleBuckets](./transferPendingPayout.t.sol#L459) |
| BLCUTRY-P12 | Fuzz all callers | 10 | 20 | 30 | All equal; second keeper separately owed 7 | 60 | Other K=7 and T=7 retained; token/other keeper remain indexed | Covered: [test_givenSharedRecipientAndOtherKeeper_whenRetried_thenOnlySelectedClaimsPaid](./transferPendingPayout.t.sol#L154) |

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-L02 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins](./transferPendingPayout.t.sol#L544) |

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUTRY-L01 | Fuzz all callers | false | Fuzz true/false | BurnerLoans_PolicyNotActive(Payout) | All entitlements and balances unchanged | Covered: [test_givenPayoutInactive_whenRetried_reverts](./transferPendingPayout.t.sol#L531) |
