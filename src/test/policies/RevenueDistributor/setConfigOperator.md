# setConfigOperator scenario plan

Scope: inherited immediate RD operator rotation and configOperator getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only; zero revokes, arbitrary nonzero EOA or contract can become operator. Local disablement does not gate rotation. RD must be Kernel-active, including revocation and same-value attempts. Old operator loses delegated configuration; admin retains direct authority.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: ConfigOperatorSet(operator) exactly once; getter follows requested value; routes, debts and custody unchanged.

## Authorization

| ID | Caller | RD Kernel | RD local | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-A01 | Any non-admin, fuzz | Active/inactive | Fuzz enabled/disabled | Fuzz zero/nonzero | Fuzz zero, current, changed EOA, changed contract | ConfigOperator_Unauthorized(caller) before lifecycle and unchanged checks | Unchanged | Covered: [full matrix][test_givenAnyLifecycleAndOperatorState_whenNonAdminSetsAnyOperator_reverts], [active seed][test_whenNonAdminSetsOperator_reverts], [inactive precedence seed][test_givenPolicyInactive_whenNonAdminSetsOperator_revertsUnauthorizedFirst] |

## Behavior

| ID | Caller | RD Kernel | RD local | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-P01 | Admin | Active | Fuzz enabled/disabled | Fuzz zero/nonzero | Changed nonzero EOA or contract | Success | New operator controls setters; old operator rejected; direct admin still works; pointer/event change only | Covered: [EOA and authority transfer][test_whenAdminSetsEOAOperator_thenEOACanConfigureDistribution], [contract][test_givenClearedOperator_whenAdminRestoresTimelock_restoresConfiguration], [locally disabled][test_givenLocallyDisabled_whenAdminSetsOperator_succeeds] |
| OP-P04 | Admin | Active | Fuzz enabled/disabled | Nonzero | Zero | Success | Operator becomes zero; old operator rejected; direct admin still works; exact event; configuration, debt and custody unchanged | Covered: [authority revocation][test_givenSelectedOperator_whenAdminClearsOperator_revokesConfiguration], [local-state and isolation matrix][test_givenSelectedOperator_whenAdminClearsOperator_preservesConfiguration] |

## Lifecycle

| ID | Caller | RD Kernel | RD local | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-L01 | Admin with role retained | Inactive | Fuzz enabled/disabled | Fuzz zero/nonzero | Fuzz zero, changed nonzero, current | RevenueDistributor_PolicyInactive() before unchanged-value validation | Existing operator/configuration/custody retained; no event | Covered: [full matrix][test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts], [changed seed][test_givenPolicyInactive_whenAdminSetsChangedOperator_reverts] |

## Invalid inputs

`ConfigOperatorSingleStep` defines a same-value rotation as an error for every inheriting contract.
RevenueDistributor therefore preserves that shared behavior instead of introducing a local no-op.

| ID | Caller | RD state | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OP-I01 | Admin | Active; fuzz enabled/disabled | Fuzz zero/nonzero | Equal to current | ConfigOperator_Unchanged() from the shared abstract contract | Unchanged; no event | Covered: [nonzero][test_givenSelectedOperator_whenAdminSetsSameOperator_reverts], [zero][test_givenClearedOperator_whenAdminSetsZeroAgain_reverts] |

[test_whenNonAdminSetsOperator_reverts]: ./setConfigOperator.t.sol#L125
[test_givenPolicyInactive_whenNonAdminSetsOperator_revertsUnauthorizedFirst]: ./setConfigOperator.t.sol#L215
[test_givenSelectedOperator_whenAdminClearsOperator_revokesConfiguration]: ./setConfigOperator.t.sol#L59
[test_whenAdminSetsEOAOperator_thenEOACanConfigureDistribution]: ./setConfigOperator.t.sol#L240
[test_givenClearedOperator_whenAdminRestoresTimelock_restoresConfiguration]: ./setConfigOperator.t.sol#L111
[test_givenSelectedOperator_whenAdminSetsSameOperator_reverts]: ./setConfigOperator.t.sol#L140
[test_givenClearedOperator_whenAdminSetsZeroAgain_reverts]: ./setConfigOperator.t.sol#L149
[test_givenPolicyInactive_whenAdminSetsChangedOperator_reverts]: ./setConfigOperator.t.sol#L163
[test_givenLocallyDisabled_whenAdminSetsOperator_succeeds]: ./setConfigOperator.t.sol#L227
[test_givenAnyLifecycleAndOperatorState_whenNonAdminSetsAnyOperator_reverts]: ./setConfigOperator.t.sol#L14
[test_givenSelectedOperator_whenAdminClearsOperator_preservesConfiguration]: ./setConfigOperator.t.sol#L78
[test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts]: ./setConfigOperator.t.sol#L181
