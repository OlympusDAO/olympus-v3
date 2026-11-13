# Timelock metadata scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol`. The fixture uses real Kernel
activation, ROLES and operator selection. Metadata methods have no local lifecycle
gate and do not require target readiness. No backing or intent is mutated.

| ID | Case | Expected result | Test |
| --- | --- | --- | --- |
| BO-TIMELOCK-METADATA-01 | Read version and query product/shared/enabler/version interfaces | VERSION 1.0; required IDs accepted; invalid ID rejected | Covered: [interfaces][test_whenInterfaces] |
| BO-TIMELOCK-METADATA-02 | Configure dependencies and query permissions/key cap | One ROLES dependency, no module writes, one configuration domain | Covered: [hooks][test_whenFrameworkHooks] |
| BO-TIMELOCK-METADATA-03 | ADMIN calls the removed delay-setter selector | Dispatcher rejects the call; fixed one-day notice is preserved | Covered: [absent selector][test_whenDelayChangeSelectorIsCalled] |
| BO-TIMELOCK-METADATA-04 | Read the fixed notice constant and configured delay | Both report exactly one day; no min/max range is advertised | Covered: [fixed notice][test_whenFixedNotice] |

[test_whenInterfaces]: ./metadata.t.sol#L39
[test_whenFrameworkHooks]: ./metadata.t.sol#L67
[test_whenDelayChangeSelectorIsCalled]: ./metadata.t.sol#L27
[test_whenFixedNotice]: ./metadata.t.sol#L17
