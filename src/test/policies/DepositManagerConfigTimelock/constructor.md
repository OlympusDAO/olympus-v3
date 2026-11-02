# DepositManagerConfigTimelock.constructor coverage plan

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-CONSTRUCTOR`.

Deployment is permissionless and binds one immutable DM. Compatibility is checked at construction;
target readiness and selection of DMCT as configOperator are deferred to activation/queueing.
The constructor requires the five consumed interfaces and a matching reported Kernel.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Invalid targets

| ID | Caller | Target | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-CONSTRUCTOR-I01 | Deployer | Zero | DepositManagerConfigTimelock_ZeroAddress() | Covered: [test][test_whenDepositManagerIsZero_reverts] |
| DMCT-CONSTRUCTOR-I02 | Deployer | Non-contract address | DepositManagerConfigTimelock_InvalidDepositManager(target) | Covered: [test][test_whenDepositManagerDoesNotSupportRequiredInterfaces_reverts] |
| DMCT-CONSTRUCTOR-I03 | Deployer | Each missing IDepositManager, IDepositManagerV1_1, IAssetManagerV1_1, IConfigOperator or IEnabler separately | DepositManagerConfigTimelock_InvalidDepositManager(target) | Covered: [test][test_whenDepositManagerOnlySupportsV1_reverts], [test][test_whenManagerInterfaceMissing_reverts], [test][test_whenManagerV11InterfaceMissing_reverts], [test][test_whenAssetV11InterfaceMissing_reverts], [test][test_whenOperatorInterfaceMissing_reverts], [test][test_whenEnablerInterfaceMissing_reverts] |
| DMCT-CONSTRUCTOR-I04 | Deployer | Valid interfaces, foreign Kernel | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Covered: [test][test_givenDepositManagerUsesDifferentKernel_reverts] |

## Initialization and deployment order

| ID | Caller | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-CONSTRUCTOR-P01 | Fuzz all deployers | true | true | Exact Kernel/DM; disabled, inactive, transition=0, next ID=1, grace=7 days, delay=1 day, batch key cap=15 | Covered: [test][test_whenAnyDeployerConstructs] |
| DMCT-CONSTRUCTOR-P02 | Deployer | true | true | Public immutable target and timing constants: minimum=1 day, maximum=30 days, execution window=3 days | Covered: [test][test_givenValidParameters_setsImmutableConfiguration] |
| DMCT-CONSTRUCTOR-L01 | Deployer | false | false | Construction succeeds without readiness; subject remains disabled | Covered: [test][test_givenTargetPausedInactive_whenConstructed] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_whenDepositManagerIsZero_reverts]: constructor.t.sol#L27
[test_whenDepositManagerDoesNotSupportRequiredInterfaces_reverts]: constructor.t.sol#L35
[test_whenDepositManagerOnlySupportsV1_reverts]: constructor.t.sol#L50
[test_whenManagerInterfaceMissing_reverts]: constructor.t.sol#L127
[test_whenManagerV11InterfaceMissing_reverts]: constructor.t.sol#L132
[test_whenAssetV11InterfaceMissing_reverts]: constructor.t.sol#L137
[test_whenOperatorInterfaceMissing_reverts]: constructor.t.sol#L142
[test_whenEnablerInterfaceMissing_reverts]: constructor.t.sol#L147
[test_givenDepositManagerUsesDifferentKernel_reverts]: constructor.t.sol#L55
[test_whenAnyDeployerConstructs]: constructor.t.sol#L89
[test_givenValidParameters_setsImmutableConfiguration]: constructor.t.sol#L75
[test_givenTargetPausedInactive_whenConstructed]: constructor.t.sol#L111
