# BurnerLoansRisk.validatePriceSupport coverage plan

Source: [validatePriceSupport](../../../policies/burnerloans/BurnerLoansRisk.sol#L526). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-VALIDATE-PRICE` identifies this contract/function.

Permissionless view resolves current PRICE from Core Kernel. No live price/backing/cache read or Core operational gate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-PRICE-L01 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-VALIDATE-PRICE-L02 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts] |
| BLRISK-VALIDATE-PRICE-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts] |
| BLRISK-VALIDATE-PRICE-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-PRICE-I01 | Fuzz all callers | PRICE does not advertise the required price-approval interface | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_whenRequiredInterfaceMissing_reverts] |
| BLRISK-VALIDATE-PRICE-I02 | Fuzz all callers | Required interface present; asset price approval=false | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_whenAssetUnapproved_reverts] |
| BLRISK-VALIDATE-PRICE-I03 | Fuzz all callers | PRICE absent/reverting interface/getter; asset zero/EOA/unregistered | Exact dependency ABI/revert when lookup cannot execute; approval determines supported asset | No invented token/market admission; module replacement observed | Covered: [test][test_givenPriceCodeAbsent_whenValidated_reverts], [test][test_whenPriceApprovalExists], [test][test_whenZeroAndEoaApproved], [test][test_givenInterfaceReadReverts_whenValidated_reverts], [test][test_givenApprovalReadReverts_whenValidated_reverts], [test][test_givenPriceReplacement_whenValidated] |

## Successful execution

Fixed for this table: Accounting / events: No writes.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-VALIDATE-PRICE-P01 | Fuzz all callers | PRICE interface supported, asset approved | Success | Covered: [test][test_whenPriceApprovalExists] |

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenApprovalReadReverts_whenValidated_reverts]: validatePriceSupport.t.sol#L111
[test_givenDisabled_whenCalled_reverts]: validatePriceSupport.t.sol#L32
[test_givenInactiveAndDisabled_whenCalled_reverts]: validatePriceSupport.t.sol#L46
[test_givenInactive_whenCalled_reverts]: validatePriceSupport.t.sol#L39
[test_givenInterfaceReadReverts_whenValidated_reverts]: validatePriceSupport.t.sol#L99
[test_givenOperational_whenCalled]: validatePriceSupport.t.sol#L26
[test_givenPriceCodeAbsent_whenValidated_reverts]: validatePriceSupport.t.sol#L17
[test_givenPriceReplacement_whenValidated]: validatePriceSupport.t.sol#L123
[test_givenReEnabled_whenCalled]: validatePriceSupport.t.sol#L55
[test_whenAssetUnapproved_reverts]: validatePriceSupport.t.sol#L73
[test_whenPriceApprovalExists]: validatePriceSupport.t.sol#L81
[test_whenRequiredInterfaceMissing_reverts]: validatePriceSupport.t.sol#L61
[test_whenZeroAndEoaApproved]: validatePriceSupport.t.sol#L89
