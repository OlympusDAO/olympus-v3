# DepositManager.addAssetPeriod guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-ADD-ASSET-PERIOD-L01 | Fixed `ADMIN`, holding `admin` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Fixture asset, `DEPOSIT_PERIOD`, `DEPOSIT_OPERATOR` | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenOrdinaryAction_revertsActivityFirst]: ./addAssetPeriod.t.sol#L686
