# DepositManager.deposit guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-DEPOSIT-L01 | Fixed `ADMIN`, holding `admin` and lacking `deposit_operator` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Fixture asset/period/depositor; amount=`1e18`, unwrapped receipts | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: ./deposit.t.sol#L1294
