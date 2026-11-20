# DepositManager.borrowingRepay guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-BORROWING-REPAY-L01 | Fixed `DEPOSIT_OPERATOR`, holding `deposit_operator` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Fixture asset, payer=`RECIPIENT`, amount and maximum=`BORROW_AMOUNT` | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: ./borrowingRepay.t.sol#L1332
