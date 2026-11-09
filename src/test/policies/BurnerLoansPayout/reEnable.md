# BurnerLoansPayout.reEnable coverage plan

Source: [ReEnabler](../../../bases/ReEnabler.sol), [grace](../../../bases/ReEnablerGracePeriod.sol)
and [Payout hooks](../../../policies/burnerloans/BurnerLoansPayout.sol).

Scope: `BLCU-REENABLE`. Time is uint48 seconds; G is uint32 seconds, L is lastTransitionAt,
D=L+G widened before narrowing. Authorized classes are ADMIN only, burner_loans_admin only and
their overlap. Other roles and configOperator alone confer no re-enable authority.
Unless varied, Payout is active, initialized, disabled, inside grace and both guards idle.
Unchanged means history, enabled flag, grace, routes, operator, Core selection, custody, all four
liability buckets and token/recipient indexes. Success changes only history/flag and emits exactly
Enabled plus Transition(caller,true,empty,now) from Payout. No numeric/address/collection action inputs,
preview, token movement or rounding apply. Core is an authority/guard reference; distributor readiness
is not an activation prerequisite, matching ordinary enable.

## Authorization and lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-REENABLE-A01 | Fuzz excluding every ADMIN and burner_loans_admin holder, including zero, emergency and configOperator seeds | true | false | NotAuthorised before grace/guards | Unchanged | Covered: [test_givenUnauthorized_whenReEnabled_reverts][test_givenUnauthorized_whenReEnabled_reverts]; [test_whenUnauthorizedClassesSeeded_reverts][test_whenUnauthorizedClassesSeeded_reverts] |
| BLCU-REENABLE-A02 | Each exclusive role and overlap; fuzz caller | true | false | Success independent of Core active/enabled | Exact transition; ledger/configuration preserved | Covered: [test_givenPermittedRole_whenReEnabled][test_givenPermittedRole_whenReEnabled]; [test_whenExclusiveRolesAndOverlapSeeded][test_whenExclusiveRolesAndOverlapSeeded] |
| BLCU-REENABLE-L01 | ADMIN | Fuzz false/true | true | NotDisabled before authorization | Unchanged | Covered: [test_givenEnabled_whenReEnabled_reverts][test_givenEnabled_whenReEnabled_reverts]; [test_whenLifecycleStateSeeds_reverts][test_whenLifecycleStateSeeds_reverts] |
| BLCU-REENABLE-L02 | ADMIN | false | false | BurnerLoans_PolicyNotActive(Payout) | Unchanged; retry after Kernel reactivation succeeds | Covered: [test_givenPolicyInactive_whenReEnabled_revertsThenRestored][test_givenPolicyInactive_whenReEnabled_revertsThenRestored] |
| BLCU-REENABLE-L03 | Fuzz caller | Fuzz false/true | false; never initialized | NeverEnabled before authority/grace/guard | Unchanged | Covered: [test_givenNeverInitialized_whenReEnabled_reverts][test_givenNeverInitialized_whenReEnabled_reverts]; [test_whenLifecycleStateSeeds_reverts][test_whenLifecycleStateSeeds_reverts] |
| BLCU-REENABLE-L04 | ADMIN | true | false; re-enabled then paused again | Success at new grace endpoint | Fresh transition restarts window | Covered: [test_givenReEnabled_whenPausedAgain_thenWindowRestarts][test_givenReEnabled_whenPausedAgain_thenWindowRestarts] |

## Time boundaries

| ID | Caller | L | G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-REENABLE-N01 | ADMIN | Fuzz 1..MAX48-G | Fuzz 1..MAX32 | Fuzz L..D; seeds L,D-1,D and maximal nonoverflow D | Success | Exact transition, Unchanged ledger | Covered: [test_whenWithinGrace][test_whenWithinGrace]; [test_whenInclusiveBoundarySeeds][test_whenInclusiveBoundarySeeds] |
| BLCU-REENABLE-N02 | ADMIN | Fuzz 1..MAX48-G-1 | Fuzz 1..MAX32 | Fuzz D+1..MAX48; seeds D+1,MAX48 | GracePeriod_Expired(D) before activation guards | Unchanged; ordinary ADMIN enable still available | Covered: [test_whenGraceExpired_reverts][test_whenGraceExpired_reverts]; [test_whenExpiredBoundarySeeds_reverts][test_whenExpiredBoundarySeeds_reverts] |
| BLCU-REENABLE-N03 | ADMIN | Fuzz MAX48-G+1..MAX48 | Fuzz 1..MAX32 | L | SafeCastOverflowedUintDowncast(48,D); seeds first overflow and MAX48 | Unchanged | Covered: [test_whenDeadlineOverflows_reverts][test_whenDeadlineOverflows_reverts]; [test_whenOverflowBoundarySeeds_reverts][test_whenOverflowBoundarySeeds_reverts] |

## Settlement safety

The nested token caller holds ADMIN and reaches the guard with valid history/grace. No new Core
lifecycle or distributor activation checks are introduced.

| ID | Caller | Payout guard | Core guard | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-REENABLE-C01 | ADMIN token | Entered during recovery | Idle | ReentrancyGuardReentrantCall before own activity | Caught: outer recovery pays once, no transition | Covered: [test_givenOutgoingCallback_whenReEnableCaught][test_givenOutgoingCallback_whenReEnableCaught] |
| BLCU-REENABLE-C02 | ADMIN token | Entered during recovery | Idle | ReentrancyGuardReentrantCall | Propagated: mandatory recovery rolls back custody/ledger | Covered: [test_givenOutgoingCallback_whenReEnablePropagated_reverts][test_givenOutgoingCallback_whenReEnablePropagated_reverts] |
| BLCU-REENABLE-C03 | ADMIN token | Idle | Entered during incoming receipt | ReentrancyGuardReentrantCall | Caught: outer deposit credits once, no transition | Covered: [test_givenIncomingCallback_whenReEnableCaught][test_givenIncomingCallback_whenReEnableCaught] |
| BLCU-REENABLE-C04 | ADMIN token | Idle | Entered during incoming receipt | ReentrancyGuardReentrantCall | Propagated: incoming transfer/accounting roll back | Covered: [test_givenIncomingCallback_whenReEnablePropagated_reverts][test_givenIncomingCallback_whenReEnablePropagated_reverts] |
| BLCU-REENABLE-C05 | ADMIN | Idle | Reverting guard read; own policy also inactive | Exact guard error before own inactivity | Unchanged; restoration then reactivation/retry succeeds | Covered: [test_givenCoreBusyAndPolicyInactive_whenReEnabled_revertsThenRestored][test_givenCoreBusyAndPolicyInactive_whenReEnabled_revertsThenRestored] |
| BLCU-REENABLE-V01 | ADMIN handler | Idle | Idle | Arbitrary credit/recovery/route/pause/re-enable sequences | Independent accounting model, custody/indexes and lifecycle history hold | Covered: [invariant_backingBucketsIndexesAndRoutes][invariant_backingBucketsIndexesAndRoutes] |

[invariant_backingBucketsIndexesAndRoutes]: ./accounting.invariants.t.sol#L77
[test_givenCoreBusyAndPolicyInactive_whenReEnabled_revertsThenRestored]: ./reEnable.t.sol#L247
[test_givenEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L98
[test_givenIncomingCallback_whenReEnableCaught]: ./reEnableCallback.t.sol#L72
[test_givenIncomingCallback_whenReEnablePropagated_reverts]: ./reEnableCallback.t.sol#L92
[test_givenNeverInitialized_whenReEnabled_reverts]: ./reEnable.t.sol#L125
[test_givenOutgoingCallback_whenReEnableCaught]: ./reEnableCallback.t.sol#L25
[test_givenOutgoingCallback_whenReEnablePropagated_reverts]: ./reEnableCallback.t.sol#L47
[test_givenPermittedRole_whenReEnabled]: ./reEnable.t.sol#L43
[test_givenPolicyInactive_whenReEnabled_revertsThenRestored]: ./reEnable.t.sol#L107
[test_givenReEnabled_whenPausedAgain_thenWindowRestarts]: ./reEnable.t.sol#L233
[test_givenUnauthorized_whenReEnabled_reverts]: ./reEnable.t.sol#L75
[test_whenDeadlineOverflows_reverts]: ./reEnable.t.sol#L202
[test_whenExclusiveRolesAndOverlapSeeded]: ./reEnable.t.sol#L63
[test_whenExpiredBoundarySeeds_reverts]: ./reEnable.t.sol#L194
[test_whenGraceExpired_reverts]: ./reEnable.t.sol#L170
[test_whenInclusiveBoundarySeeds]: ./reEnable.t.sol#L154
[test_whenLifecycleStateSeeds_reverts]: ./reEnable.t.sol#L268
[test_whenOverflowBoundarySeeds_reverts]: ./reEnable.t.sol#L222
[test_whenUnauthorizedClassesSeeded_reverts]: ./reEnable.t.sol#L87
[test_whenWithinGrace]: ./reEnable.t.sol#L139
