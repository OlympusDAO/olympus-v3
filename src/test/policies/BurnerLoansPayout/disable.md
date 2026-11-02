# BurnerLoansPayout.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol); product hooks in [Payout](../../../policies/burnerloans/BurnerLoansPayout.sol).

Scenario scope: `BLCU-DISABLE`. Cached ROLES is initialized by Kernel activation. Core is idle and its lifecycle is independent. New credits require Payout active/enabled; claims, route repair and recovery stay available after pause.

## Authorization

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-DISABLE-A01 | Fuzz caller excluding every ADMIN and EMERGENCY holder | true | true | NotAuthorised() | Unchanged | Covered: [test_whenCallerLacksPauseRoles_reverts](./disable.t.sol#L46) |

## Lifecycle

Data is empty. Other dependencies do not gate a pause; enable requires own Kernel activity without depending on upstream Core readiness.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCU-DISABLE-L01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | true | true | Success | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenPermittedCaller_whenDisabled_thenExactTransition](./disable.t.sol#L23); [test_givenEachPauseRole_whenDisabled_thenExactTransition](./disable.t.sol#L94) |
| BLCU-DISABLE-L02 | Fuzz ADMIN-only, EMERGENCY-only and overlap | false | true | Success | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenPermittedCaller_whenDisabled_thenExactTransition](./disable.t.sol#L23); [test_givenEachPauseRole_whenDisabled_thenExactTransition](./disable.t.sol#L94) |
| BLCU-DISABLE-L03 | Fuzz ADMIN-only, EMERGENCY-only and overlap | true | false | NotEnabled() | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenAlreadyPaused_whenDisabled_reverts](./disable.t.sol#L56) |
| BLCU-DISABLE-L04 | Fuzz ADMIN-only, EMERGENCY-only and overlap | false | false | NotEnabled() | On success only isEnabled/lastTransitionAt and transition events change; otherwise unchanged | Covered: [test_givenAlreadyPaused_whenDisabled_reverts](./disable.t.sol#L56) |

## Invalid inputs

| ID | Caller | Data | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-DISABLE-I01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | Fuzz nonempty bytes length 1..256; seed 0x00 and ABI-encoded zero | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test_whenNonemptyData_reverts](./disable.t.sol#L68); [test_whenNonemptyDataAtBoundaries_reverts](./disable.t.sol#L84) |

## Settlement safety

| ID | Caller | Guard | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCU-DISABLE-C01 | Fuzz ADMIN-only, EMERGENCY-only and overlap | Payout outgoing token callback | ReentrancyGuardReentrantCall() | No lifecycle change during payout | Covered: [test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects](./disableCallback.t.sol#L16); [test_givenEachPauseRole_whenOutgoingCallbackTransitions_thenRejected](./disableCallback.t.sol#L55) |
| BLCU-DISABLE-C02 | Fuzz ADMIN-only, EMERGENCY-only and overlap | Core incoming transfer or settlement | ReentrancyGuardReentrantCall() | No lifecycle change during settlement | Covered: [test_givenCoreBusy_whenDisabled_reverts](./disable.t.sol#L122); [test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects](./disableCallback.t.sol#L37); [test_givenEachPauseRole_whenIncomingCallbackTransitions_thenRejected](./disableCallback.t.sol#L65) |
