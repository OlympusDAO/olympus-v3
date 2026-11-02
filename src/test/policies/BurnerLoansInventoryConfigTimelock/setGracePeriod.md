# BurnerLoansInventoryConfigTimelock.setGracePeriod coverage plan

The concrete setter requires own Kernel activity before inherited local enablement, ADMIN authorization and nonzero-period validation. Same valid periods retain the inherited single-event behavior and do not alter lifecycle history.

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Concrete behavior: [_authorizeSetGracePeriod](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L347).

## Scope and fixtures

`MAXn` denotes `2**n-1`; time is measured in seconds.

TL is this timelock, with cached ROLES and ADMIN_ROLE authorization. Unchanged means no grace, transition timestamp, lifecycle, queue, token or loan-state writes and no committed event. Inventory/Core readiness and controller selection do not gate this setter. Periods are uint32 seconds; timestamps are uint48 seconds.

## Authorization

Local active/enabled; nonzero period.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-GRACE-A01 | ADMIN | Accepted role | Success | Store period; GracePeriodSet; no transition timestamp change | Covered: [test][test_whenPeriodSet_thenExactStorageAndRepeatedEvent]; [test][test_whenPeriodAtTypeBounds_thenExactStorageAndEvents] |
| BLINCT-GRACE-A02 | Fuzz outside ADMIN holders | Include BL-admin-only | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_whenUnauthorizedSetter_reverts]; [test][test_givenBurnerLoansAdminOnly_whenPeriodSet_reverts] |

## Lifecycle

Use ADMIN only.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-GRACE-L01 | ADMIN | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabledTimelock_whenGraceSet_reverts] |
| BLINCT-GRACE-L02 | ADMIN | false | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveTimelock_whenGraceSet_reverts] |
| BLINCT-GRACE-L03 | ADMIN | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabledTimelock_whenGraceSet_reverts] |

## Numeric inputs

Preserve inherited setter behavior, including equal-value emission.

| ID | Caller | Period | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-GRACE-I01 | ADMIN | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [test][test_whenPeriodZero_reverts] |
| BLINCT-GRACE-N01 | ADMIN | Fuzz 1..MAX32; seed 1,MAX32 | Success | Exact stored period/event | Covered: [test][test_whenPeriodSet_thenExactStorageAndRepeatedEvent]; [test][test_whenPeriodAtTypeBounds_thenExactStorageAndEvents] |
| BLINCT-GRACE-P01 | ADMIN | Exactly current valid period | Success; not a no-op | Emit GracePeriodSet once; no timestamp transition | Covered: [test][test_whenPeriodSet_thenExactStorageAndRepeatedEvent]; [test][test_whenPeriodAtTypeBounds_thenExactStorageAndEvents] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-GRACE-L04 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; fuzz full uint32 period | BurnerLoans_PolicyNotActive(TL) | Period, enabled flag, transition timestamp and preserved state unchanged | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts] |

[test_whenPeriodSet_thenExactStorageAndRepeatedEvent]: ./setGracePeriod.t.sol#L25
[test_whenPeriodAtTypeBounds_thenExactStorageAndEvents]: ./setGracePeriod.t.sol#L123
[test_whenUnauthorizedSetter_reverts]: ./setGracePeriod.t.sol#L49
[test_givenBurnerLoansAdminOnly_whenPeriodSet_reverts]: ./setGracePeriod.t.sol#L131
[test_givenActiveDisabledTimelock_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L62
[test_givenInactiveTimelock_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L85
[test_whenPeriodZero_reverts]: ./setGracePeriod.t.sol#L98
[test_givenInactiveDisabledTimelock_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L70
[test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L136
