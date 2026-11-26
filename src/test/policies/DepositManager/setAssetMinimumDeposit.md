# DepositManager.setAssetMinimumDeposit guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-SET-ASSET-MINIMUM-DEPOSIT-L01 | Fixed `ADMIN`, holding `admin` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Fixture asset, minimum=`1e18` | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: ./setAssetMinimumDeposit.t.sol#L117
