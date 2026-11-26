# ERC7726OracleFactory.enableCreation guard-precedence scenarios

Source: [ERC7726OracleFactory](../../../../policies/price/ERC7726OracleFactory.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ERC7726-ENABLE-CREATION-L01 | Any address, fuzz, without authorization exclusions | false | Fuzz false/true | Kernel-deactivated after optional local enablement; creation is enabled; No arguments; creation already enabled | `ERC7726OracleFactory_PolicyNotActive()` before local enablement, caller and action checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst] |

[test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst]: ./enableCreation.t.sol#L73
