# BurnerLoansPayoutConfigTimelock.setGracePeriod coverage plan

The concrete setter requires own Kernel activity before inherited local enablement, ADMIN authorization and nonzero-period validation. Same valid periods retain the inherited single-event behavior and do not alter lifecycle history.

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [setGracePeriod](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol).

## Domains and notation

Scenario scope: `BLCUCT-GRACE`. Inherited uint32 duration setter; ADMIN only. Same valid value succeeds and emits GracePeriodSet. Do not change the shared ReEnabler implementation.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Authorization

Local enabled=true and cached ROLES initialized. Require the exact inherited ROLES error.

| ID | Caller | Period | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-GRACE-A01 | Fuzz outside every ADMIN holder | Valid/invalid period | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_givenUnauthorizedCaller_whenPeriodSet_reverts](setGracePeriod.t.sol#L46) |

## Period bounds

The future disable timestamp is unknown. Overflow is tested at reEnable, not by restricting a currently valid duration.

| ID | Caller | Period | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-GRACE-N01 | Fuzz ADMIN holder | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [test_whenPeriodZero_reverts](setGracePeriod.t.sol#L59) |
| BLCUCT-GRACE-N02 | Fuzz ADMIN holder | Fuzz1..MAX32; seed1/MAX32; same and different old value | Success; one GracePeriodSet | Period stores exact value; lastTransitionAt/enabled state unchanged | Covered: [test_whenPeriodSet_thenExactStorageAndSameValueEvent](setGracePeriod.t.sol#L17), [test_whenPeriodBoundarySeedsUsed](setGracePeriod.t.sol#L115) |

## Policy admission

Own-policy admission belongs in the concrete timelock hook, not shared ReEnabler code.

| ID | Caller | Local active | Local enabled | Required result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-GRACE-L01 | Fuzz ADMIN holder | true | true | Success | Period/event only | Covered: [test_whenPeriodSet_thenExactStorageAndSameValueEvent](setGracePeriod.t.sol#L17), [test_whenPeriodBoundarySeedsUsed](setGracePeriod.t.sol#L115) |
| BLCUCT-GRACE-L02 | Fuzz all callers | true | false | NotEnabled() before authority/input checks | Unchanged | Covered: [test_givenActiveDisabled_whenPeriodSet_reverts](setGracePeriod.t.sol#L69) |
| BLCUCT-GRACE-L03 | Fuzz ADMIN holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansPayoutConfigTimelock) before period validation | Unchanged; no period/event/transition changes | Covered: [test_givenInactiveEnabled_whenPeriodSet_reverts](setGracePeriod.t.sol#L98), [test_whenPeriodBoundarySeedsUsed](setGracePeriod.t.sol#L115) |
| BLCUCT-GRACE-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test_givenInactiveDisabled_whenPeriodSet_reverts](setGracePeriod.t.sol#L82) |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCUCT-GRACE-L05 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; fuzz full uint32 period | BurnerLoans_PolicyNotActive(TL) | Period, enabled flag, transition timestamp and preserved state unchanged | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts] |

[test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L128
