# BurnerLoansPayoutConfigTimelock.VERSION coverage plan

Coverage records implemented domains and assertions independently of pass/fail status.

Source: [VERSION](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L556).

## Domains and notation

Scenario scope: `BLCUCT-VERSION`. Permissionless pure interface version.

Unchanged means authoritative state, balances, allowances and committed logs applicable to this function remain unchanged. Faults are isolated with all other prerequisites satisfied. Use [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md); preserve independent lifecycle columns and guaranteed numeric boundary seeds.

## Version value

No state-specific numbered suffixes.

| ID | Caller | State | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCUCT-VERSION-V01 | Fuzz all callers | Fresh and all reachable local/target lifecycle states | (1,0) | No reads, writes or logs | Covered: [test][test_whenVersionRead_thenConstant], [test][test_givenEachLifecyclePair_whenRead_thenIndependent], [test][test_givenFreshPolicy_whenRead_thenIndependent] |

- [x] Derive concrete acceptance criteria from the implemented call path.
- [x] Implement focused tests and map exact domains/effects; execution results are tracked separately.

[test_givenEachLifecyclePair_whenRead_thenIndependent]: ./VERSION.t.sol#L39
[test_givenFreshPolicy_whenRead_thenIndependent]: ./VERSION.t.sol#L57
[test_whenVersionRead_thenConstant]: ./VERSION.t.sol#L14
