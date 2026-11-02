# BurnerLoansCore.requireNotReentrant coverage plan

Source: [requireNotReentrant](../../../policies/burnerloans/BurnerLoansCore.sol#L917). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-REENTRANCY` identifies this contract/function.

Permissionless view; no lifecycle/role gate. This is the Custody recovery barrier for an incoming receipt before Core credits it.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Permissionless view; Core local activity and enablement do not gate the idle-guard check.

| ID | Caller | Local active | Local enabled | Core guard entered | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-REENTRANCY-L01 | Fuzz all callers | true | true | false | Return normally | No state or events | Covered: [test][test_givenIdleCore_whenGuardQueried] |
| BLCORE-REENTRANCY-L02 | Fuzz all callers | true | false | false | Return normally | No state or events | Covered: [test][test_givenIdleCore_whenGuardQueried] |
| BLCORE-REENTRANCY-L03 | Fuzz all callers | false | true | false | Return normally | No state or events | Covered: [test][test_givenIdleCore_whenGuardQueried] |
| BLCORE-REENTRANCY-L04 | Fuzz all callers | false | false | false | Return normally | No state or events | Covered: [test][test_givenIdleCore_whenGuardQueried] |

## Callbacks and reentrancy

Fixed for this table: Accounting / events: No effects; callback catch/propagation tested at caller.

| ID | Caller | Callback / nested call | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-REENTRANCY-C01 | Authorized callback | Inside Core guarded settlement/configureDependencies/rescue | ReentrancyGuardReentrantCall | Covered: [test][test_givenBusyCore_whenGuardQueried_reverts] |

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Existing tests informing this plan

New modular entrypoint with no direct legacy counterpart. Its caller/binding/replacement cases supplement the existing settlement and lifecycle suites; do not manufacture a legacy coverage mapping.

[test_givenBusyCore_whenGuardQueried_reverts]: requireNotReentrant.t.sol#L24
[test_givenIdleCore_whenGuardQueried]: requireNotReentrant.t.sol#L11
