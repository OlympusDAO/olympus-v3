# BurnerLoansInventoryConfigTimelock.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L61).

## Scope and fixtures

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Invalid targets

Failed deployment commits no contract/logs.

| ID | Caller | Target fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CONSTRUCTOR-I01 | Fuzz deployer | I=0 | InvalidInventory(0) | No deployment | Covered: [test][test_whenInventoryZero_reverts] |
| BLINCT-CONSTRUCTOR-I02 | Fuzz deployer | I=EOA | InvalidInventory(I) | No deployment | Covered: [test][test_whenInventoryEOA_reverts] |
| BLINCT-CONSTRUCTOR-I03 | Fuzz deployer | Missing Inventory interface | InvalidInventory(I) | No deployment | Covered: [test][test_givenRequiredInterfaceMissing_whenDeployed_reverts], [seeds][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I04 | Fuzz deployer | Missing IEnabler interface | InvalidInventory(I) | No deployment | Covered: [test][test_givenRequiredInterfaceMissing_whenDeployed_reverts], [seeds][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I05 | Fuzz deployer | Other Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | No deployment | Covered: [test][test_givenInventoryOnOtherKernel_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I06 | Fuzz deployer | ERC165 supportsInterface reverts | InvalidInventory(I) | No deployment | Covered: [test][test_givenERC165Reverts_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I07 | Fuzz deployer | ERC165 returns malformed short data | InvalidInventory(I) | No deployment | Covered: [test][test_givenERC165Malformed_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I08 | Fuzz deployer | All three consumed interfaces supported; kernel() reverts with typed error | PolicyDependency_InvalidDependency(Inventory) | No deployment | Covered: [test][test_givenKernelViewReverts_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I09 | Fuzz deployer | All three consumed interfaces supported; kernel() returns empty data | PolicyDependency_InvalidDependency(Inventory) | No deployment | Covered: [test][test_givenKernelViewEmpty_whenDeployed_reverts] |
| BLINCT-CONSTRUCTOR-I10 | Fuzz deployer | Missing IConfigOperator interface | InvalidInventory(I) | No deployment | Covered: [test][test_givenRequiredInterfaceMissing_whenDeployed_reverts], [test][test_givenEachRequiredInterfaceMissing_whenDeployed_reverts] |

## Successful construction

Binding is verified without requiring target lifecycle or reverse selection. Defaults: immutable I, disabled TL, nextActionId=1, delay=1day, execution window=3days, grace=7days, lastTransitionAt=0. Constructor emits `GracePeriodSet(7 days)` then `TimelockDelaySet(1 days)`; no role grants, transfers or module writes.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-CONSTRUCTOR-P01 | Fuzz deployer | true | true | Success | Exact defaults; no grants/funds | Covered: [test][test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults]; [test][test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults] |
| BLINCT-CONSTRUCTOR-P02 | Fuzz deployer | true | false | Success | Same defaults | Covered: [test][test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults]; [test][test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults] |
| BLINCT-CONSTRUCTOR-P03 | Fuzz deployer | false | true | Success | Same defaults | Covered: [test][test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults]; [test][test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults] |
| BLINCT-CONSTRUCTOR-P04 | Fuzz deployer | false | false | Success | Same defaults | Covered: [test][test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults]; [test][test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

## Construction without runtime readiness

The constructor validates the same consumed interface set as enable/reEnable and the same-Kernel binding. It does not read target activity, enabled state or selected configOperator.

| ID | Caller | Target condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CONSTRUCTOR-P05 | Fuzz deployer | Target activity, isEnabled and configOperator reads revert; consumed interfaces and Kernel binding valid | Success | No readiness/selection reads; target bound; queue disabled | Covered: [test][test_givenRuntimeReadinessGettersRevert_whenConstructed] |

[test_whenInventoryZero_reverts]: ./constructor.t.sol#L31
[test_whenInventoryEOA_reverts]: ./constructor.t.sol#L36
[test_givenRequiredInterfaceMissing_whenDeployed_reverts]: ./constructor.t.sol#L42
[test_givenInventoryOnOtherKernel_whenDeployed_reverts]: ./constructor.t.sol#L61
[test_givenERC165Reverts_whenDeployed_reverts]: ./constructor.t.sol#L77
[test_givenERC165Malformed_whenDeployed_reverts]: ./constructor.t.sol#L90
[test_givenKernelViewReverts_whenDeployed_reverts]: ./constructor.t.sol#L103
[test_givenKernelViewEmpty_whenDeployed_reverts]: ./constructor.t.sol#L120
[test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults]: ./constructor.t.sol#L133
[test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults]: ./constructor.t.sol#L216
[test_givenEachRequiredInterfaceMissing_whenDeployed_reverts]: ./constructor.t.sol#L168
[test_givenRuntimeReadinessGettersRevert_whenConstructed]: ./constructor.t.sol#L177
