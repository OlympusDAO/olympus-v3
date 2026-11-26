# BurnerLoansConfig.setConfigOperator coverage plan

Source: [setConfigOperator](../../../policies/utils/ConfigOperatorSingleStep.sol#L27). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-CONFIG-OPERATOR` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

The concrete authorization hook checks Config activity, local enablement, then ADMIN. The inherited setter delegates admission to that hook. configOperator address0 removes delegation; selected operator itself is not authorized to replace delegation.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Config is Kernel-active and locally enabled; authorization dependencies are initialized. Caller and proposed pointer vary independently.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-CONFIG-OPERATOR-A01 | Fuzz caller excluding every ADMIN_ROLE holder; seed current operator without ADMIN, former operator, BL-admin-only, zero and unrelated contract | Zero, changed nonzero and unchanged pointer; earlier lifecycle guards pass | ROLES_RequireRole(ADMIN_ROLE) before pointer validation; no authority change or event | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| BLCFG-CONFIG-OPERATOR-A02 | Fuzz ADMIN_ROLE holder; independently seed ADMIN-only and ADMIN/current-operator overlap | Changed pointer; seed zero when clearing an existing operator and a distinct nonzero EOA/contract | Success; exact ConfigOperatorSet(newOperator), configOperator() equals input; old delegation revoked and all other authority/accounting unchanged | Covered: [test][test_givenAdmin_whenOperatorChanged] |

## Lifecycle

Own activity precedes enablement and ADMIN; pointer equality follows authorization. Other contracts are references, not operational dependencies of this pointer setter.

| ID | Caller | Local active | Local enabled | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-CONFIG-OPERATOR-L01 | Fuzz all callers | true | false | Valid or invalid operator | NotEnabled() before role check | Unchanged | Covered: [test][test_givenActiveDisabled_whenOperatorChanged_reverts] |
| BLCFG-CONFIG-OPERATOR-L03 | Fuzz all callers | false | true | Zero, changed nonzero and same current pointer | BurnerLoans_PolicyNotActive(BurnerLoansConfig) before enablement/role/pointer checks | No authority change or event | Covered: [test][test_givenInactiveEnabled_whenOperatorChanged_reverts] |
| BLCFG-CONFIG-OPERATOR-L04 | Fuzz ADMIN_ROLE holder | true | true | Changed valid pointer | Success | Configuration-transition effects below | Covered: [test][test_givenAdmin_whenOperatorChanged] |

## Configuration transitions

Fixed for this table: Accounting / events: No event.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-CONFIG-OPERATOR-P01 | ADMIN_ROLE holder | Same pointer including zero | ConfigOperator_Unchanged | Covered: [test][test_whenSameOperatorSelected_reverts] |

## Successful execution

Fixed for this table: Accounting / events: Old operator loses future numeric authority; no queues migrated.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-CONFIG-OPERATOR-P02 | ADMIN_ROLE holder | Existing nonzero configOperator; new operator=0 | Clear delegation; ConfigOperatorSet(0) | Covered: [test][test_whenOperatorCleared] |
| BLCFG-CONFIG-OPERATOR-P03 | ADMIN_ROLE holder | New nonzero operator differs from selected operator; fuzz address excluding zero/current | Select new delegation; ConfigOperatorSet(newOperator) | Covered: [test][test_givenAdmin_whenOperatorChanged] |

Co-located API assertions: `configOperator`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Shared assertions

Config.configOperator equals the independently chosen replacement. Former operator loses future authority; ADMIN remains authorized; overlap identities tested. This updates Config delegation only, not Risk/Custody component identity or queued actions.

## Inactive and disabled admission

Previously activated/deactivated; cached ROLES retained. Other component lifecycle is irrelevant.

| ID | Caller | Local active | Local enabled | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-CONFIG-OPERATOR-L05 | Fuzz all callers | false | false | Zero/changed/unchanged operator | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | No delegation or event change | Covered: [test][test_givenInactiveDisabled_whenOperatorChanged_reverts] |

Retired IDs: BLCFG-CONFIG-OPERATOR-L02. Replacement cases isolate supported outcomes; removed duplicates add no proof.

[test_whenCallerIsNotAdmin_reverts]: ./setConfigOperator.t.sol#L19
[test_givenAdmin_whenOperatorChanged]: ./setConfigOperator.t.sol#L29
[test_whenOperatorCleared]: ./setConfigOperator.t.sol#L42
[test_whenSameOperatorSelected_reverts]: ./setConfigOperator.t.sol#L58
[test_givenActiveDisabled_whenOperatorChanged_reverts]: ./setConfigOperator.t.sol#L73
[test_givenInactiveEnabled_whenOperatorChanged_reverts]: ./setConfigOperator.t.sol#L85
[test_givenInactiveDisabled_whenOperatorChanged_reverts]: ./setConfigOperator.t.sol#L97
