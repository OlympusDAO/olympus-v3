# BurnerLoansInventoryConfigTimelock.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Concrete behavior: [_beforeEnable](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L316).

## Scope and fixtures

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Dependency validation contract

The immutable Inventory target must be compatible and Kernel-active, but may be locally disabled so rescue remains available. Burn-specific queue/execute paths additionally require enabled Inventory. Controller selection is separate authorization; Core is an upstream identity whose activity/enablement does not gate recovery.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Inventory → `BurnerLoansInventoryTimelock_InvalidInventory(I)`.

## Authorization

Local disabled, own active, cached ROLES; I is bound/active and selects TL. Payload=0x.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-ENABLE-A01 | ADMIN | Permitted | Success | enabled=true; timestamp=now; Enabled then Transition(caller,true,empty,now) | Covered: [test][test_givenReadyTarget_whenActivated_thenExactTransition] |
| BLINCT-ENABLE-A02 | Fuzz outside ADMIN | Unauthorized | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenActivated_reverts] |

## Lifecycle

Use ADMIN. A paused I may acquire/enable its recovery queue; only the burn service needs I enabled.

| ID | Caller | Local active | Local enabled | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINCT-ENABLE-L01 | ADMIN | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenOwnPolicyInactive_whenActivated_reverts] |
| BLINCT-ENABLE-L02 | ADMIN | true | true | true | true | NotDisabled() | No second transition | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLINCT-ENABLE-L03 | ADMIN | false | true | true | true | NotDisabled() | Local transition guard wins | Covered: [test][test_givenAlreadyEnabled_whenActivated_reverts] |
| BLINCT-ENABLE-D01 | ADMIN | true | false | true | false | Success | Recovery queue enabled; I unchanged | Covered: [test][test_givenReadyTarget_whenActivated_thenExactTransition]; [test][test_givenInventoryDisabled_whenTimelockEnabled_thenRecoveryRemainsAvailable] |
| BLINCT-ENABLE-D03 | ADMIN | true | false | false | true | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInventoryInactive_whenActivated_reverts] |
| BLINCT-ENABLE-D04 | ADMIN | true | false | false | false | PolicyDependency_NotActive(I) | Unchanged | Covered: [test][test_givenInventoryInactive_whenActivated_reverts] |

## Bindings

All local and time prerequisites pass. A different Kernel is produced by reachable Kernel migration.

| ID | Caller | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-ENABLE-D02 | ADMIN | I controller is another nonzero address | NotAuthorised() | Unchanged | Covered: [test][test_givenAnotherController_whenActivated_reverts] |
| BLINCT-ENABLE-D06 | ADMIN | I controller is zero | NotAuthorised() | Unchanged | Covered: [test][test_givenClearedController_whenActivated_reverts] |
| BLINCT-ENABLE-D05 | ADMIN | I reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenTargetKernelDrift_whenActivated_reverts] |

## Payload

Unused bytes must be empty.

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-ENABLE-I01 | ADMIN | Fuzz nonempty length 1..256; seed 0x00,0x01,encoded zero | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test][test_givenNonemptyData_whenEnabled_reverts]; [test][test_givenNonemptyPayloadBoundaries_whenCalled_reverts] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

## Activation compatibility

Activation and reactivation require compatible target, ConfigOperator and Enabler interfaces, same Kernel, target Policy activity and this queue selected as configOperator. They do not read the target's enabled status. This allows queue repair while the target remains paused; each queued operation still enforces its own execution requirements. Other transition/caller/history/grace/payload guards retain their existing order.

Caller is authorized and every prerequisite not varied below is valid. An incompatible target leaves lifecycle history, pending actions, reservations, configuration and custody unchanged.

| ID | Target active | Target enabled | Input fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-ENABLE-D07 | true | Fuzz false/true | Reject each consumed interface advertisement; seed every interface | BurnerLoansInventoryTimelock_InvalidInventory(Inventory) | Unchanged | Covered: [test][test_givenMissingConsumedInterface_whenActivated_reverts] |

[test_givenReadyTarget_whenActivated_thenExactTransition]: ./enable.t.sol#L30
[test_givenUnauthorizedCaller_whenActivated_reverts]: ./enable.t.sol#L57
[test_givenOwnPolicyInactive_whenActivated_reverts]: ./enable.t.sol#L69
[test_givenAlreadyEnabled_whenActivated_reverts]: ./enable.t.sol#L81
[test_givenInventoryDisabled_whenTimelockEnabled_thenRecoveryRemainsAvailable]: ./enable.t.sol#L158
[test_givenInventoryInactive_whenActivated_reverts]: ./enable.t.sol#L90
[test_givenAnotherController_whenActivated_reverts]: ./enable.t.sol#L105
[test_givenClearedController_whenActivated_reverts]: ./enable.t.sol#L115
[test_givenTargetKernelDrift_whenActivated_reverts]: ./enable.t.sol#L125
[test_givenNonemptyData_whenEnabled_reverts]: ./enable.t.sol#L172
[test_givenNonemptyPayloadBoundaries_whenCalled_reverts]: ./enable.t.sol#L187

[test_givenMissingConsumedInterface_whenActivated_reverts]: enable.t.sol#L199
