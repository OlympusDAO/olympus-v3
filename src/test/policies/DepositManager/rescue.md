# DepositManager.rescue guard-precedence scenarios

Source: [DepositManager](../../../policies/deposits/DepositManager.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DM-RESCUE-L01 | Any address, fuzz, without authorization exclusions | false | false | Default locally disabled policy, then Kernel-deactivated; asset not configured on DepositManager; Token=`address(0)` | `DepositManager_PolicyInactive()` before rescue authority and token checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenUnauthorizedCallerRescues_revertsActivityFirst]: ./rescue.t.sol#L340
