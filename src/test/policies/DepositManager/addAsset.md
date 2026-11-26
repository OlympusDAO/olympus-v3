# DepositManager.addAsset guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-ADD-ASSET-L01 | Fixed `ADMIN`, holding `admin` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; V1.1 overload: same asset/vault/cap/minimum; fuzz `requiresShareWithdrawal_` across both booleans | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenShareWithdrawalRequirementIsSpecified_reverts_ActivityFirst] |
| DM-ADD-ASSET-L02 | Fixed `ADMIN`, holding `admin` | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Legacy overload: fixture asset/vault, cap=`type(uint256).max`, minimum=0 | `DepositManager_PolicyInactive()` before local enablement, caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_reverts_ActivityFirst] |

[test_givenInactiveAndDisabled_whenShareWithdrawalRequirementIsSpecified_reverts_ActivityFirst]: ./addAsset.t.sol#L1012

[test_givenInactiveAndDisabled_reverts_ActivityFirst]: ./addAsset.t.sol#L1000
