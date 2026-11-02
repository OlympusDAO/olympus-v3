# setConfigOperator scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: inherited immediate RD operator rotation and configOperator getter.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin only; zero revokes, arbitrary nonzero EOA or contract can become operator. Local disablement does not gate rotation. RD must be Kernel-active, including revocation and same-value attempts. Old operator loses delegated configuration; admin retains direct authority.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: ConfigOperatorSet(operator) exactly once; getter follows requested value; routes, debts and custody unchanged.

## Authorization

| ID | Caller | Local active | Local enabled | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-A01 | Any non-admin, fuzz | true | true | Fuzz zero/nonzero | Fuzz zero, current, changed EOA, changed contract | ConfigOperator_Unauthorized(caller) before unchanged checks while Kernel-active | Unchanged | Covered: [test][test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-A02 | Any non-admin, fuzz | true | false | Fuzz zero/nonzero | Fuzz zero, current, changed EOA, changed contract | ConfigOperator_Unauthorized(caller) before unchanged checks while Kernel-active | Unchanged | Covered: [test][test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-A03 | Any non-admin, fuzz | false | true | Fuzz zero/nonzero | Fuzz zero, current, changed EOA, changed contract | RevenueDistributor_PolicyNotActive(RD) before caller and unchanged checks | Unchanged | Covered: [test][test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-A04 | Any non-admin, fuzz | false | false | Fuzz zero/nonzero | Fuzz zero, current, changed EOA, changed contract | RevenueDistributor_PolicyNotActive(RD) before caller and unchanged checks | Unchanged | Covered: [test][test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |

## Behavior

| ID | Caller | Local active | Local enabled | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-P01 | ADMIN_ROLE holder | true | true | Fuzz zero/nonzero | Changed nonzero EOA or contract | Success | New operator controls setters; old operator rejected; direct admin still works; pointer/event change only | Covered: [test][test_givenFundedActivePolicy_whenAdminChangesOperator], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-P02 | ADMIN_ROLE holder | true | false | Fuzz zero/nonzero | Changed nonzero EOA or contract | Success | New operator controls setters; old operator rejected; direct admin still works; pointer/event change only | Covered: [test][test_givenFundedActivePolicy_whenAdminChangesOperator], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-P04 | ADMIN_ROLE holder | true | true | Nonzero | Zero | Success | Operator becomes zero; old operator rejected; direct admin still works; exact event; configuration, debt and custody unchanged | Covered: [test][test_givenFundedActivePolicy_whenAdminChangesOperator], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-P05 | ADMIN_ROLE holder | true | false | Nonzero | Zero | Success | Operator becomes zero; old operator rejected; direct admin still works; exact event; configuration, debt and custody unchanged | Covered: [test][test_givenFundedActivePolicy_whenAdminChangesOperator], [test][test_givenOperatorLifecycleAndIdentitySeeds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-L01 | ADMIN_ROLE holder | false | true | Fuzz zero/nonzero | Fuzz zero, changed nonzero, current | RevenueDistributor_PolicyNotActive(RD) before unchanged-value validation | Existing operator/configuration/custody retained; no event | Covered: [test][test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-L02 | ADMIN_ROLE holder | false | false | Fuzz zero/nonzero | Fuzz zero, changed nonzero, current | RevenueDistributor_PolicyNotActive(RD) before unchanged-value validation | Existing operator/configuration/custody retained; no event | Covered: [test][test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |

## Invalid inputs

`ConfigOperatorSingleStep` defines a same-value rotation as an error for every inheriting contract.
RevenueDistributor therefore preserves that shared behavior instead of introducing a local no-op.

| ID | Caller | Local active | Local enabled | Current operator | `configOperator_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OP-I01 | ADMIN_ROLE holder | true | true | Fuzz zero/nonzero | Equal to current | ConfigOperator_Unchanged() from the shared abstract contract | Unchanged; no event | Covered: [test][test_givenFundedPolicy_whenAdminRepeatsOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |
| OP-I02 | ADMIN_ROLE holder | true | false | Fuzz zero/nonzero | Equal to current | ConfigOperator_Unchanged() from the shared abstract contract | Unchanged; no event | Covered: [test][test_givenFundedPolicy_whenAdminRepeatsOperator_reverts], [test][test_givenOperatorLifecycleAndIdentitySeeds] |

[test_givenPolicyActiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts]: ./setConfigOperator.t.sol#L15

[test_givenPolicyInactive_whenAdminSetsAnyOperator_reverts]: ./setConfigOperator.t.sol#L220

[test_givenOperatorLifecycleAndIdentitySeeds]: ./setConfigOperator.t.sol#L384

[test_givenFundedActivePolicy_whenAdminChangesOperator]: ./setConfigOperator.t.sol#L303

[test_givenFundedPolicy_whenAdminRepeatsOperator_reverts]: ./setConfigOperator.t.sol#L357

[test_givenPolicyInactiveAndOperatorState_whenNonAdminSetsAnyOperator_reverts]: ./setConfigOperator.t.sol#L61

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OP-L03 | Fixed `alice`, lacking admin authority | false | true | Enabled distributor, then Kernel-deactivated; Requested config operator=`alice` | `RevenueDistributor_PolicyNotActive(RD)` before config-operator authorization | Revert; no effects of the attempted action commit. | Covered: [test][test_givenPolicyInactive_whenNonAdminSetsOperator_revertsActivityFirst] |

[test_givenPolicyInactive_whenNonAdminSetsOperator_revertsActivityFirst]: ./setConfigOperator.t.sol#L258
