# BurnerLoansPayout.rescue coverage plan

Source: [rescue](../../../policies/burnerloans/BurnerLoansPayout.sol#L402). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCU-RESCUE` identifies this contract/function.

Payout business actions, recovery and routing/authority changes require own Kernel activity before caller authorization. Local pause or Core replacement does not block existing claims or recovery while Payout remains active. Core lifecycle is independent; framework hooks, ordinary accounting getters and disable retain their documented behavior.

ADMIN or stored nonzero controller, current/previous Payout, outside settlement; Core itself is forbidden destination before helper token validation. Other exclusions: zero,this Payout,token,current Config,Core Kernel. balance B and reserved T independent.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Payout is a Kernel Policy with IEnabler. New credits require the immutable Core caller, own Kernel activity and local enablement. Inactive Payout fails BurnerLoans_PolicyNotActive(Payout) before caller authorization; active non-Core caller fails NotAuthorised(); paused Payout fails NotEnabled(). There is no retired state or reverse Core-selection check. Core selects its future settlement target; disabling a previous Payout pauses new credits without affecting claims. Core lifecycle is an authority reference, not a downstream dependency. Local reentrancy guard runs first; credit is allowed inside the outer Core settlement.

Recovery `transferPendingPayout/rescue/rescuePendingPayout` uses local guard then Core.requireNotReentrant(), followed by own activity before authority, inputs or token work. During Core incoming receipt before credit, recovery rejects Core's `ReentrancyGuardReentrantCall()`. Outside settlement, current/previous Payout recovery works with Core enabled/disabled and active/inactive. Retry is permissionless. Rescue authority is ADMIN from Payout's Kernel or the locally stored nonzero configOperator address. The controller is upstream: Payout does not inspect its activity, enablement, Kernel or interface. Another non-ADMIN fails `NotAuthorised()`.

State per token: pendingProtocolFees F; pendingSeizedCollateral S; pendingKeeperRewards K[recipient]; pendingReferralFees R[recipient]; totalPendingKeeperRewards Kt=sum(K); totalPendingReferralFees Rt=sum(R); totalPending T=F+S+Kt+Rt. Fee bucket follows Payout's local fee routing flags; S follows Payout Kernel's current Treasury; K follows original keeper; R follows original referrer. Independent recipient equalities: fee=Treasury, keeper=fee, keeper=Treasury, all equal, all distinct, unrelated recipient, zero route. Incoming funds are already in Payout when credited; no Core→Payout forwarding. Retired/new Payout contracts have separate buckets and balances.

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-RESCUE-I01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | token=0; destination valid | BurnerLoans_InvalidAsset(token) | Covered: [test_givenZeroToken_whenRecovered_reverts][test_givenZeroToken_whenRecovered_reverts]; [test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts][test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | token is EOA; destination valid | BurnerLoans_InvalidAsset(token) | Covered: [test_givenEoaToken_whenRecovered_reverts][test_givenEoaToken_whenRecovered_reverts]; [test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts][test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I03 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=0 | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenZeroDestination_whenRecovered_reverts][test_givenZeroDestination_whenRecovered_reverts]; [test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I04 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenCoreDestination_whenRecovered_reverts][test_givenCoreDestination_whenRecovered_reverts]; [test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I05 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Payout | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenSelfDestination_whenRecovered_reverts][test_givenSelfDestination_whenRecovered_reverts]; [test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I06 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Config | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenControllerDestination_whenRecovered_reverts][test_givenControllerDestination_whenRecovered_reverts]; [test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I07 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenKernelDestination_whenRecovered_reverts][test_givenKernelDestination_whenRecovered_reverts]; [test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts] |
| BLCU-RESCUE-I08 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Token deployed; destination=token | BurnerLoans_InvalidRescueDestination(destination) | Covered: [test_givenTokenDestination_whenRecovered_reverts][test_givenTokenDestination_whenRecovered_reverts]; [test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts][test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts] |

## Successful execution

Fixed for this table: Accounting / events: Transfer only surplus; AssetRescued; obligations unchanged.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCU-RESCUE-P01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Balance>totalPending; transfer succeeds | Success | Covered: [test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves][test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves]; [test_givenBackedReserves_givenEachRecoveryRole_whenSurplusRescued_thenOnlyExcessMoves][test_givenBackedReserves_givenEachRecoveryRole_whenSurplusRescued_thenOnlyExcessMoves]; [test_givenSurplusAndReserveAtTypeBoundaries_whenRescued_thenOnlyExcessMoves][test_givenSurplusAndReserveAtTypeBoundaries_whenRescued_thenOnlyExcessMoves] |

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-D01 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Balance<=totalPending | Success | Zero surplus; no transfer/event; all reserves untouched | Covered: [test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer][test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer]; [test_givenDeficitOrExactBacking_givenEachRecoveryRole_whenRescued_thenNoTransfer][test_givenDeficitOrExactBacking_givenEachRecoveryRole_whenRescued_thenNoTransfer]; [test_givenNoSurplusAtTypeBoundaries_whenRescued_thenNoTransfer][test_givenNoSurplusAtTypeBoundaries_whenRescued_thenNoTransfer] |
| BLCU-RESCUE-D02 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Positive surplus; transfer reverts | Exact configured token error | Full rollback | Covered: [test_givenBlockedTransfer_whenSurplusRescued_reverts][test_givenBlockedTransfer_whenSurplusRescued_reverts]; [test_givenBlockedTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts][test_givenBlockedTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts] |
| BLCU-RESCUE-D03 | Fuzz permitted recovery caller (ADMIN-only, stored controller-only, overlap seeds) | Positive surplus; transfer returns false | SafeERC20FailedOperation(token) | Full rollback | Covered: [test_givenFalseTransfer_whenSurplusRescued_reverts][test_givenFalseTransfer_whenSurplusRescued_reverts]; [test_givenFalseTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts][test_givenFalseTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts] |

## Shared assertions

PreviewRescue must share action address/surplus rules, recovery authorization and settlement-busy rejection. Deficit preview returns0, not fictitious solvency. ADMIN rescue of an active previous Payout while Core is inactive/disabled must succeed. Constructor rejects zero/invalid Core; do not fabricate a zero-Core ordinary recovery fixture.

Co-located API assertions: `previewRescue`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Recovery authorization

Core idle; positive surplus; valid token/destination. Exclude all ADMIN holders and stored nonzero controller from unauthorized fuzzing.

| ID | Caller | Request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-A01 | Fuzz outside permitted set; seed former controller without ADMIN | Valid recovery | NotAuthorised() | No reserve, token, index or event change | Partial: [test_givenUnauthorizedCaller_whenRescued_reverts][test_givenUnauthorizedCaller_whenRescued_reverts]; [test_givenFormerController_whenRescued_reverts][test_givenFormerController_whenRescued_reverts]; execution authorization covered; preview authority and settlement-idle requirements remain pending the API decision |

## Active recovery

Seed ADMIN-only, controller-only and overlap callers. Local Payout enablement does not gate recovery; Core must be idle. Controller lifecycle/Kernel getters may reject; they must not be read.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-L01 | Fuzz equivalent permitted recovery callers | true | Fuzz true/false | Fuzz true/false | Fuzz true/false | Transfer positive surplus | Only this instance surplus moves; reserves/other Payout contracts unchanged | Covered: [test_givenPayoutActive_whenRescued_thenRecoveryAvailable][test_givenPayoutActive_whenRescued_thenRecoveryAvailable]; [test_givenPayoutActive_givenEachRecoveryRole_whenRescued_thenRecoveryAvailable][test_givenPayoutActive_givenEachRecoveryRole_whenRescued_thenRecoveryAvailable]; [test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable][test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable] |

## Inactive Payout rejection

Seed ADMIN-only, controller-only and overlap callers. Local Payout enablement does not gate recovery; Core must be idle. Controller lifecycle/Kernel getters may reject; they must not be read.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-L02 | Fuzz equivalent permitted recovery callers | false | Fuzz true/false | Fuzz true/false | Fuzz true/false | BurnerLoans_PolicyNotActive(Payout) | Unchanged; no committed logs | Covered: [test_givenPayoutInactive_whenCalled_reverts][test_givenPayoutInactive_whenCalled_reverts] |

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-C01 | ADMIN-only, stored controller-only or overlap; fuzz equivalent callers | Payout→recovery destination strict ERC20 transfer | Authorized nested recovery or permissionless retry reaching Payout local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One recovery transfer; only surplus moves; every pending obligation unchanged | Covered: [test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce][test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce]; [test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce][test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce] |
| BLCU-RESCUE-C02 | ADMIN-only, stored controller-only or overlap; fuzz equivalent callers | Payout→recovery destination strict ERC20 transfer | Authorized nested recovery or permissionless retry reaching Payout local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback][test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback]; [test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback][test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback] |

- [ ] Resolve the preview API decision: current previews do not enforce the authority and settlement-idle requirements above. Four isolated requirement tests reproduce the gap; production behavior is unchanged.

## Own activity precedence

| ID | Caller | Local active | Local enabled | Competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-RESCUE-L04 | Fuzz unauthorized callers; excludes stored operator and ADMIN identities | false | Fuzz true/false | ROLES calls revert; otherwise valid action | BurnerLoans_PolicyNotActive(Payout) before caller/role reads | Unchanged; no committed logs | Covered: [test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins][test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins] |

[test_givenBackedReserves_givenEachRecoveryRole_whenSurplusRescued_thenOnlyExcessMoves]: ./rescue.t.sol#L346
[test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves]: ./rescue.t.sol#L24
[test_givenBlockedTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts]: ./rescue.t.sol#L401
[test_givenBlockedTransfer_whenSurplusRescued_reverts]: ./rescue.t.sol#L105
[test_givenCaughtNestedRetry_givenEachRecoveryRole_whenRecovered_thenAppliedOnce]: ./rescueCallback.t.sol#L69
[test_givenCaughtNestedRetry_whenRecovered_thenAppliedOnce]: ./rescueCallback.t.sol#L13
[test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L499
[test_givenControllerDestination_whenRecovered_reverts]: ./rescue.t.sol#L292
[test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L471
[test_givenCoreDestination_whenRecovered_reverts]: ./rescue.t.sol#L256
[test_givenDeficitOrExactBacking_givenEachRecoveryRole_whenRescued_thenNoTransfer]: ./rescue.t.sol#L364
[test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer]: ./rescue.t.sol#L40
[test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L443
[test_givenEoaToken_whenRecovered_reverts]: ./rescue.t.sol#L220
[test_givenFalseTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts]: ./rescue.t.sol#L415
[test_givenFalseTransfer_whenSurplusRescued_reverts]: ./rescue.t.sol#L123
[test_givenFormerController_whenRescued_reverts]: ./rescue.t.sol#L98
[test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L513
[test_givenKernelDestination_whenRecovered_reverts]: ./rescue.t.sol#L310
[test_givenNoSurplusAtTypeBoundaries_whenRescued_thenNoTransfer]: ./rescue.t.sol#L569
[test_givenPayoutActive_givenEachRecoveryRole_whenRescued_thenRecoveryAvailable]: ./rescue.t.sol#L382
[test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable]: ./rescue.t.sol#L597
[test_givenPayoutActive_whenRescued_thenRecoveryAvailable]: ./rescue.t.sol#L68
[test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins]: ./rescue.t.sol#L638
[test_givenPayoutInactive_whenCalled_reverts]: ./rescue.t.sol#L618
[test_givenPropagatedNestedRetry_givenEachRecoveryRole_whenRecovered_thenCompleteRollback]: ./rescueCallback.t.sol#L82
[test_givenPropagatedNestedRetry_whenRecovered_thenCompleteRollback]: ./rescueCallback.t.sol#L39
[test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L485
[test_givenSelfDestination_whenRecovered_reverts]: ./rescue.t.sol#L274
[test_givenSurplusAndReserveAtTypeBoundaries_whenRescued_thenOnlyExcessMoves]: ./rescue.t.sol#L541
[test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L527
[test_givenTokenDestination_whenRecovered_reverts]: ./rescue.t.sol#L328
[test_givenUnauthorizedCaller_whenRescued_reverts]: ./rescue.t.sol#L85
[test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L457
[test_givenZeroDestination_whenRecovered_reverts]: ./rescue.t.sol#L238
[test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts]: ./rescue.t.sol#L429
[test_givenZeroToken_whenRecovered_reverts]: ./rescue.t.sol#L202
