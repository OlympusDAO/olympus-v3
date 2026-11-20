# BurnerLoansPayout.setGracePeriod coverage plan

Source: [grace base](../../../bases/ReEnablerGracePeriod.sol) and
[Payout](../../../policies/burnerloans/BurnerLoansPayout.sol). Scope: `BLCU-GRACE`.

Period is uint32 seconds, valid 1..MAX32; zero is invalid. Only ADMIN is authorized; burner_loans_admin,
emergency and configOperator alone are unauthorized. No addresses/collections, preview, token movement
or rounding apply. Default grace is seven days. Unless varied, policy is active/enabled and idle.
Unchanged means enabled flag/history, custody, obligations/indexes, routes, operator and Core selection.
Setter success changes only grace and emits exactly one GracePeriodSet(period), including same-value.
Local and Core settlement guards precede own activity, enabled state, authority and period validation.

| ID | Caller | Local active | Local enabled | Period | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCU-GRACE-A01 | Fuzz excluding every ADMIN; seeds zero, burner_loans_admin, emergency, configOperator | true | true | Fuzz uint32 | ROLES_RequireRole(ADMIN) | Unchanged grace/state/logs | Covered: [test_givenUnauthorized_whenPeriodSet_reverts][test_givenUnauthorized_whenPeriodSet_reverts]; [test_whenUnauthorizedClassesSeeded_reverts][test_whenUnauthorizedClassesSeeded_reverts] |
| BLCU-GRACE-P01 | Fuzz ADMIN; exclusive and overlapping loan-admin | true | true | Fuzz 1..MAX32; seeds 1,MAX32,same | Success; getter agrees | One exact event per call; Unchanged otherwise | Covered: [test_whenPeriodSet_thenExactStorageAndSameValueEvent][test_whenPeriodSet_thenExactStorageAndSameValueEvent]; [test_whenPeriodBoundarySeeds][test_whenPeriodBoundarySeeds] |
| BLCU-GRACE-N01 | ADMIN | true | true | 0 | GracePeriod_ZeroPeriod | Unchanged | Covered: [test_whenPeriodZero_reverts][test_whenPeriodZero_reverts] |
| BLCU-GRACE-L01 | Fuzz caller | true | false | Fuzz uint32 | NotEnabled before authority/period | Unchanged | Covered: [test_givenDisabled_whenPeriodSet_reverts][test_givenDisabled_whenPeriodSet_reverts]; [test_whenLifecycleStateSeeds_reverts][test_whenLifecycleStateSeeds_reverts] |
| BLCU-GRACE-L02 | Fuzz caller; broken ROLES | false | Fuzz false/true | Fuzz uint32 | BurnerLoans_PolicyNotActive(Payout) | Unchanged | Covered: [test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts][test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts]; [test_whenLifecycleStateSeeds_reverts][test_whenLifecycleStateSeeds_reverts] |
| BLCU-GRACE-L03 | ADMIN | Reactivated | Re-enabled | MAX32 | Success | History unchanged; future disable uses new period | Covered: [test_givenPolicyReactivated_givenReEnabled_whenPeriodSet][test_givenPolicyReactivated_givenReEnabled_whenPeriodSet] |
| BLCU-GRACE-C01 | ADMIN token | true | true | 1 | Outgoing callback: local ReentrancyGuardReentrantCall | Outer optional credit succeeds once; grace unchanged | Covered: [test_givenOutgoingCallback_whenGraceSet_thenGuardRejects][test_givenOutgoingCallback_whenGraceSet_thenGuardRejects] |
| BLCU-GRACE-C02 | ADMIN token | true | true | 1 | Incoming callback: Core ReentrancyGuardReentrantCall | Outer deposit succeeds once; grace unchanged | Covered: [test_givenIncomingCallback_whenGraceSet_thenCoreGuardRejects][test_givenIncomingCallback_whenGraceSet_thenCoreGuardRejects] |

[test_givenDisabled_whenPeriodSet_reverts]: ./setGracePeriod.t.sol#L107
[test_givenIncomingCallback_whenGraceSet_thenCoreGuardRejects]: ./setGracePeriodCallback.t.sol#L38
[test_givenOutgoingCallback_whenGraceSet_thenGuardRejects]: ./setGracePeriodCallback.t.sol#L18
[test_givenPolicyInactive_givenBrokenRoles_whenPeriodSet_reverts]: ./setGracePeriod.t.sol#L116
[test_givenPolicyReactivated_givenReEnabled_whenPeriodSet]: ./setGracePeriod.t.sol#L134
[test_givenUnauthorized_whenPeriodSet_reverts]: ./setGracePeriod.t.sol#L71
[test_whenLifecycleStateSeeds_reverts]: ./setGracePeriod.t.sol#L149
[test_whenPeriodBoundarySeeds]: ./setGracePeriod.t.sol#L56
[test_whenPeriodSet_thenExactStorageAndSameValueEvent]: ./setGracePeriod.t.sol#L22
[test_whenPeriodZero_reverts]: ./setGracePeriod.t.sol#L98
[test_whenUnauthorizedClassesSeeded_reverts]: ./setGracePeriod.t.sol#L84
