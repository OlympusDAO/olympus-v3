# BurnerLoansPayoutConfigTimelock.requestPermissions coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L100).

## Domains and notation

Scenario scope: `BLCUCT-PERMISSIONS`. Permissionless pure framework hook; local/dependency state is irrelevant.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Permission declaration

No ADMIN grant on the timelock; Payout authorizes it by stored address.

| ID | Caller | Input / state | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-PERMISSIONS-V01 | Fuzz all callers | Fresh/active/disabled/inactive independently | Empty Permissions array | No dependency calls or dynamic authority grants | Covered: [test][test_whenPermissionsRead_thenEmpty], [test][test_givenEachLifecyclePair_whenRead_thenIndependent], [test][test_givenFreshPolicy_whenRead_thenIndependent] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenEachLifecyclePair_whenRead_thenIndependent]: ./requestPermissions.t.sol#L41
[test_givenFreshPolicy_whenRead_thenIndependent]: ./requestPermissions.t.sol#L59
[test_whenPermissionsRead_thenEmpty]: ./requestPermissions.t.sol#L17
