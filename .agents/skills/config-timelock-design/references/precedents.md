# Existing configuration timelock precedents

Read the named functions in the current checkout before copying a pattern. These are local source precedents, not claims about deployed configuration.

## Shared lifecycle and selector-specific target requirements

The queues below implement the [shared lifecycle contract](../SKILL.md#lifecycle-contract). Their constructors and both activation routes share interface predicates covering the domain interface, `IConfigOperator` and `IEnabler`, plus additional consumed interfaces for DepositManager and RevenueDistributor. The proof links below show how to test those boundaries without adding constructor readiness probes.

Target enablement for mutations is intentionally operation-specific:

| Queue | Target admission and execution | Reason for the target-enabled rule |
| --- | --- | --- |
| [BurnerLoansRiskConfigTimelock](../../../../src/policies/burnerloans/BurnerLoansRiskConfigTimelock.sol) | Risk active/enabled, same Kernel, selected operator; no Config/Core readiness walk | Ordinary settings respect Risk's operational configuration pause. Activation has a separate repair boundary. |
| [DepositManagerConfigTimelock](../../../../src/policies/deposits/DepositManagerConfigTimelock.sol) | Manager active/enabled with current operator authority for every admitted configuration selector | The queue admits configuration, not the target's separate disabled-capable unmanaged-token rescue API. |
| [BurnerLoansConfigTimelock](../../../../src/policies/burnerloans/BurnerLoansConfigTimelock.sol) | Config active/enabled and selected operator; action-specific downstream checks | Config's market setters and Core-rescue forwarding deliberately use its operational gate; Config retains FLOAN market writes. |
| [BurnerLoansPayoutConfigTimelock](../../../../src/policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol) | Payout previews/mutations enforce activity and permit paused/replaced-target routing and recovery | Payout can retain funded obligations after pause or replacement; routing and recovery remain available without resuming new credits. |
| [BurnerLoansInventoryConfigTimelock](../../../../src/policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol) | Inventory active; surplus rescue permits pause, burning requires enablement | Rescue preserves the excess-funds recovery path while the operational burn path remains paused; live surplus checks protect required backing. |
| [RevenueDistributorConfigTimelock](../../../../src/policies/RevenueDistributorConfigTimelock.sol) | Route/recipient configuration requires active/enabled Distributor; rescue requires activity but permits pause | Configuration respects the operational pause; recovery of available surplus or pending obligations remains usable. |

Payout routing setters permit a local pause and require activity through `onlyConfigOrAdmin`; their queue enforces activity at admission as well. Only local enablement varies by selector; inactive-target admission is not an accepted precedent.

Do not infer that `_validateConfigQueue` or `_validateExecution` alone contains every gate. Follow wrappers, per-action validators, previews and target setters. The shared documentation's key-design section states a conservative independence rule; Payout's routing/pending-recovery interaction is an explicit product exception with stale-state rejection, not proof that those operations commute.

## Keys, hashes and rotation

- **Risk:** `_configKeys` separates percentage, cache age and each referrer's membership. `_currentConfigStateHash` includes selected operator and only that setting's typed value. This is the compact independent-setting example.
- **Inventory:** burn and rescue share one surplus-disposal key despite different selectors. The hash commits the controller, not the surplus balance; Inventory computes the live available amount at dispatch.
- **Payout:** independent fee/yield routing flags use separate keys; surplus recovery is keyed per token; pending recovery per token/recipient. Relevant routing/controller identities enter hashes, while liability amounts remain live. Pending recovery can be invalidated by a routing change even though its key differs: not every admitted pair is order-independent.
- **DepositManager:** asset-limit selectors share a domain; each hash includes the selected config operator plus only the consumed configuration, route state and relevant operator-role membership. A route operator is distinct from the target's delegated config operator.
- **RevenueDistributor:** asset-scoped route/recovery domains and a separate global yield recipient. Every hash includes the current operator alongside existing distribution, recipient or asset-listing state. Selection is also checked live; away-and-back restoration is still current-state matching, not an epoch.
- **Config forwarding:** hashes include Config's selected queue alongside facility identity and the relevant setting. Core-rescue commitments also retain Core's selected Config identity; those two delegation levels must not be confused. Inspect `_configDestination` and per-action binding checks when deciding whether a replacement creates a new namespace or invalidates intent in a stable namespace.

## Useful proof locations

| Concern | Source/test example |
| --- | --- |
| Constructor/activation interface parity | [Inventory constructor](../../../../src/test/policies/BurnerLoansInventoryConfigTimelock/constructor.t.sol), [enable](../../../../src/test/policies/BurnerLoansInventoryConfigTimelock/enable.t.sol) and [reEnable](../../../../src/test/policies/BurnerLoansInventoryConfigTimelock/reEnable.t.sol); [Payout constructor](../../../../src/test/policies/BurnerLoansPayoutConfigTimelock/constructor.t.sol) |
| Canonical Kernel binding and no constructor status reads | [RevenueDistributor constructor](../../../../src/test/policies/RevenueDistributorConfigTimelock/constructor.t.sol); [Risk constructor startup](../../../../src/test/policies/BurnerLoansRiskConfigTimelock/constructor.t.sol) |
| Independent settings, permutations, drift and batch rollback | [Risk execute tests](../../../../src/test/policies/BurnerLoansRiskConfigTimelock/executeQueuedAction.t.sol) and [batch tests](../../../../src/test/policies/BurnerLoansRiskConfigTimelock/queueBatch.t.sol) |
| Paused cancellation with broken target metadata | [Risk cancellation](../../../../src/test/policies/BurnerLoansRiskConfigTimelock/cancelQueuedAction.t.sol), `test_givenPending_whenEmergencyCancels` |
| Paused cancellation and target independence | [Inventory cancellation](../../../../src/test/policies/BurnerLoansInventoryConfigTimelock/cancelQueuedAction.t.sol) |
| Restored operator/current-state semantics | [Inventory execution](../../../../src/test/policies/BurnerLoansInventoryConfigTimelock/executeQueuedAction.t.sol) |
| Caught/propagated callbacks and target settlement guards | [Payout execution](../../../../src/test/policies/BurnerLoansPayoutConfigTimelock/executeQueuedAction.t.sol) and [RevenueDistributor callbacks](../../../../src/test/policies/RevenueDistributorConfigTimelock/executeQueuedActionCallback.t.sol) |
| Product key ownership model across arbitrary calls | [Risk queue invariant](../../../../src/test/policies/BurnerLoansRiskConfigTimelock/executeQueuedAction.invariants.t.sol) |
| Base mechanics and deliberately injected corruption | [ConfigTimelockBatchQueue tests](../../../../src/test/policies/utils/ConfigTimelockBatchQueue) and [TimelockBatchQueue tests](../../../../src/test/policies/utils/TimelockBatchQueue) |

These links identify reusable proof shapes, not passing execution evidence for a future change.
