# MorphoOracleFactory.enableOracle guard-precedence scenarios

Source: [MorphoOracleFactory](../../../../policies/price/BaseOracleFactory.sol).

Scope: the own-activity guard regression only. This document does not claim full API, input-boundary, accounting or lifecycle coverage.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MORPHO-ENABLE-ORACLE-L01 | Any address, fuzz, without authorization exclusions | false | Fuzz false/true | Kernel-deactivated after optional local enablement; creation is enabled; fixture oracle exists and is enabled; Existing enabled fixture oracle | `OracleFactory_PolicyNotActive()` before local enablement, caller and action checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst] |

[test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst]: ./enableOracle.t.sol#L251
