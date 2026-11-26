# DepositManager.claimYield guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-CLAIM-YIELD-L01 | Fixed `DEPOSIT_OPERATOR`, holding `deposit_operator` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Legacy overload: fixture asset, recipient=`ADMIN`, amount=1 | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |
| DM-CLAIM-YIELD-L02 | Fixed `DEPOSIT_OPERATOR`, holding `deposit_operator` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; V1.1 overload: fixture asset, recipient=`RECIPIENT`, amount=1, share output | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst_V1_1] |

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: ./claimYield.t.sol#L509

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst_V1_1]: ./claimYieldV1_1.t.sol#L712
