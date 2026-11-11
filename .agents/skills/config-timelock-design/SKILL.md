---
name: config-timelock-design
description: Design, implement or review Olympus configuration timelocks and their target integration, including lifecycle admission, ConfigOperator authority, conflict keys, state commitments and Foundry coverage.
---

# Configuration timelocks

Use for a product Policy built on the repository's configuration queue, or its target-side integration. Preserve the requested planning, review or implementation boundary. Do not standardize existing timelocks or change their authority merely because a new default is preferable.

## Purpose and governance boundary

This pattern allows an operational multisig to manage a bounded configuration surface outside OCG, with a timelock protecting that delegated authority. OCG retains the target's ADMIN role and its direct governance path, which already has a timelock. The configuration timelock supplies the notice period for the separate multisig path.

The intended flow is: the operational multisig holds a product proposer role; it queues a visible operation; the notice period gives the emergency multisig time to inspect and cancel a dangerous operation; after the delay, anyone may execute an uncancelled operation within its execution window. The target grants delegated authority to the configuration timelock as its config operator, not directly to the proposing multisig. Verify actual role/operator wiring; granting that multisig direct operator or ADMIN authority would bypass this protection for the affected setters.

The intervention window matters if the operational multisig is compromised or an exploit enables a harmful configuration proposal. The emergency multisig uses EMERGENCY cancellation authority to remove the pending intent before execution. Cancellation can also occur after the notice period while the action is still pending. It cannot undo an executed action, and cancelling one action does not itself revoke a compromised proposer's authority.

Queue-time validation rejects operations that are currently invalid; state commitments reject changed assumptions. Neither proves that an otherwise valid configuration is safe governance intent. Monitoring queued operations and retaining a usable emergency cancellation path are part of the protection. Describe these actors as intended role holders, and verify deployment-specific assignments rather than assuming every proposer or ADMIN address is a particular multisig or OCG contract.

Apply [policy-lifecycle](../policy-lifecycle/SKILL.md) for Policy compatibility, readiness, transitions and error ownership. Use [solidity-test-scenarios](../solidity-test-scenarios/SKILL.md) for acceptance matrices and coverage mappings. This skill adds queue-specific decisions.

## Establish the contract

Inspect the concrete queue, target setters/previews, inherited hooks and deployment wiring. For each admitted operation, record: proposer roles; target and selector; payload; target lifecycle requirements; configuration read/write domains; live execution constraints; conflict keys; committed pre-state; dispatch and cancellation behavior. Separate current behavior from recommendations for new code. When changing a shared convention, inspect every product timelock that follows it.

Read [existing precedents](references/precedents.md) before selecting a model. Read [testing guidance](references/testing.md) when specifying or implementing coverage. The [shared queue documentation](../../../documentation/config_timelock_batch_queue.md) owns detailed mechanics; inspect its source when documentation and implementation differ.

## Compose the existing abstractions

| Responsibility | Preferred building block |
| --- | --- |
| Atomic batches, IDs, timestamps, terminal state and queue events | [TimelockBatchQueue](../../../src/policies/utils/TimelockBatchQueue.sol), inherited through the config base |
| Destination-scoped reservations, pre-state commitments and cleanup | [ConfigTimelockBatchQueue](../../../src/policies/utils/ConfigTimelockBatchQueue.sol) |
| Consistent key scoping in off-path queries/tests | [ConfigTimelockKeyLib](../../../src/policies/utils/ConfigTimelockKeyLib.sol) |
| Target-side delegated configuration and immediate rotation/revocation | [ConfigOperatorSingleStep](../../../src/policies/utils/ConfigOperatorSingleStep.sol) and `IConfigOperator` |
| Kernel membership and role dependency | `Policy`, ROLES and the product's existing authorization mix-ins |
| Independently pausable Policy | `PolicyEnablerV2`; add `ReEnablerGracePeriod` only when bounded fast re-enablement is required |
| Policy Kernel/readiness validation | `PolicyDependency`; bounded metadata helpers for other consumed getters |

Derive a configuration timelock from `ConfigTimelockBatchQueue`, not a second handwritten queue. Implement its product hooks: `_validateConfigQueue`, `_validateConfigSubAction`, `_configDestination`, `_configKeys`, `_currentConfigStateHash`, `_executeConfigSubAction`, and optional `_validateConfigBatch`. Add the remaining parent hooks for execution, cancellation, delay bounds and execution window. Override the aggregate key limit only when bounded composite actions need it.

Let the shared base own bookkeeping. It already checks destinations, key ownership and hashes before each dispatch and releases reservations after whole-batch success or cancellation. Do not bypass these paths or release keys early. Advertise the product/shared ERC165 interfaces through `super.supportsInterface` and the target's `IConfigOperator` capability where applicable.

Resolve only required modules and permissions. A queue that calls authorized target setters usually needs ROLES but no module-write permissions; keep writes with their existing owner. Existing one-day notice, three-day inclusive window and 15-action limit are precedents, not universal product requirements. Delay validation runs during base construction and must not depend on later-initialized subclass storage. Do not add a public delay setter without a requirement.

## Target authority

Target setters within the operator's delegated scope should normally accept direct ADMIN **or** the current nonzero config operator. ADMIN is itself timelocked, so preserve its direct target path without imposing another configuration queue. This does not grant the operator every setter: explicitly inventory delegated selectors and retain ADMIN-only control for other setters, including operator rotation where specified. Any exception to ADMIN/operator access for a delegated setter needs explicit product justification and tests. A proposer role on the queue does not itself grant direct setter authority. At dispatch the queue is the caller; it does not inherit the proposing user's role.

The operator starts unset. Rotation is immediate, zero revokes delegation, and an unchanged address reverts after authorization. Override `_authorizeSetConfigOperator`; its default denies everyone. Prefer ADMIN-only rotation on an active target, allowed while locally paused for repair, unless the product specifies otherwise. Identity selection must not query the upstream queue's lifecycle or reverse binding.

Prefer an immutable directly bound target when replacements should require a new queue and fresh notice.

For mutable target discovery, define which address owns the logical configuration namespace and which rotations invalidate intent. Never silently redirect an old queued action to a replacement target.

## Lifecycle contract

Treat queue membership, queue enablement, target membership and target enablement independently. An enabled queue does not prove that its target is still usable.

| Operation | Queue active | Queue enabled | Target requirement |
| --- | --- | --- | --- |
| Construct queue | Not yet active | Starts disabled | Full consumed interface set and same-Kernel binding; no target activity, enabled-state or operator-selection reads |
| Queue configuration | Yes | Yes | Compatible, same Kernel, target Kernel-active, queue selected as operator; local enablement matches the target selector |
| Execute ordinary configuration | Yes | Yes | Revalidate current readiness and delegated authority; no proposer-role requirement on the executor |
| Enable / reEnable queue | Yes | Transition prerequisites | Consumed interfaces compatible, same Kernel, target Policy active, queue selected as operator; target may be paused. reEnable also checks initialization/history/grace |
| Disable queue | Either | Must currently be enabled | No target reads; preserve pending actions and keys |
| Cancel action | Yes | Either | No target or operator reads; require EMERGENCY |
| Framework hooks / queue getters | Follow framework/read semantics | Follow framework/read semantics | No blanket operational-target gate |

### Binding, activation and startup

Reuse one consumed-interface predicate in the constructor and both enable/reEnable paths. Check the complete interface set, including `IConfigOperator` and `IEnabler` where consumed. Compare all three boundaries side by side; adding an activation interface check requires the matching constructor check and tests.

Validate canonical Kernel binding at construction with `PolicyDependency.requireSameKernel(target, address(kernel_))`. At activation, use `PolicyDependency.requireActive(target, address(kernel))` to recheck that binding and authoritative membership. A matching reported Kernel alone does not prove active Policy membership. Follow policy-lifecycle's exact Kernel-mismatch and invalid-metadata errors.

Construction must not read target activity, local enablement or current operator selection, including through `readEnabled`/`isEnabled` or membership probes. Both activation routes require current operator selection and the other target checks in the table, without reading target enablement. Revalidate these prerequisites on each activation; a paused target must not prevent queue repair.

A valid startup order is: deploy compatible target and queue; activate/configure the target; enable it if its operator setter requires that; select its queue; activate/enable the queue. Adapt this order to real binding prerequisites and prove it has no activation cycle.

### Mutation and cancellation admission

Require target Kernel activity for every admitted configuration or recovery selector, both at queue time and execution. Do not accept inactive-target mutations as a precedent, even if an existing target entry point lacks its own activity check; flag that omission for correction.

Local target enablement is operation-specific. Ordinary configuration respects the operational pause; explicit recovery exceptions can preserve custody/claim repair without reopening ordinary operations. Inspect each target selector's modifiers and internal checks, document why it requires enablement or permits pause, and use matching queue-time validators/previews. Keep authoritative checks at execution. See the [precedents table](references/precedents.md#shared-lifecycle-and-selector-specific-target-requirements) for product examples.

EMERGENCY cancellation requires own Kernel activity and remains available while locally disabled, with no target or operator reads. Cancellation removes intent and releases locks without executing it. Expiry alone retains keys, and a broken target may prevent queue re-enablement; neither should strand the emergency cancellation path. Own Policy inactivity still blocks cancellation. ADMIN alone is not a cancellation role.

Apply ordinary admission before input validation/no-ops where the product uses that convention. Preserve the shared queue's earlier nonexistent/terminal/time errors and inherited lifecycle transition ordering. Own inactivity, own pause, incompatible target, unavailable target and lost operator selection are separate failures; choose errors from the actual interfaces and policy-lifecycle conventions.

## Conflict keys and commitments

Keys answer **which pending intents must exclude each other**. Hashes answer **which changed assumptions invalidate this intent**. They are complementary: reservations cannot stop direct ADMIN changes or normal target activity.

- Derive nonzero local keys from stable domain constants and validated payload identities. Use the same key for add/remove of one member, competing setters for the same setting, or alternate ways to dispose of the same resource. Separate independent assets/settings. A composite operation must reserve all affected domains; no duplicate keys, even within one batch.
- Scope with the destination through the base/library. `BatchAction.target` is the call recipient; destination owns the guarded namespace. They usually coincide, but adapters/discovery require an explicit choice. Reservations are local to each queue instance, not a cross-contract global lock.
- Do not default to one global key or selector-only keys. A selector can be sufficient for one independent global setting; different selectors can still conflict. If domains are called independent, prove queueing and execution succeed in either order, without stale hashes.
- The shared documentation recommends shared keys whenever assumptions overlap. Use that conservative default for new domains. A product may explicitly admit a dependency-only interaction with separate keys and later stale-state rejection, as Payout does for routing versus pending recovery. Record and test that exception; do not call the pair independent or promise both execution orders.
- Use `_currentConfigStateHash` for one canonical encoding of the **current pre-state**, at queue time and immediately before dispatch. Include the target's current config operator by default in every domain, alongside relevant settings and binding/routing identities. Live authority checks complement this commitment; they do not replace the default. For multiple keys, hash the state for the supplied local key. Do not hash the proposed value instead of the assumed current value.
- Exclude unrelated settings and deliberately volatile debt, balances, pending amounts and prices. Validate live affordability, solvency, caps and payout availability at the target when executing. A queue-time preview establishes admission, not an execution guarantee or a frozen amount.

Document a drift table for each operation:

| Change during notice | Expected handling |
| --- | --- |
| Relevant ADMIN setter changes committed configuration | Reject mismatched pre-state; retain pending intent/keys |
| Unrelated setting or normal accounting changes | Remain executable, subject to target's live checks |
| Queue or target loses required readiness | Reject now; permit retry after restoration within the original window |
| Queue loses operator selection | Reject; no fallback to the proposer's ADMIN role |
| Operator/configuration changes away and back | Current-state commitments may match again; no historical epoch invalidation unless explicitly designed |
| Destination changes | Reject mismatch; reissue for a replacement with fresh notice |
| Action expires | Reject execution; retain keys until authorized cancellation |

No FIFO ordering exists across actions: an unrelated stale or expired action must not block a valid action with different keys. An atomic batch orders sub-actions, but does not waive duplicate-key rejection or queue-time pre-state checks. If a later operation needs the state produced by an earlier conflicting operation, queue it after that operation executes unless the product explicitly supports a safe composite action.

## Dispatch and handoff

Aim to reject an operation at admission if it would fail under current conditions. Validate target readiness and delegated authority, the target/selector allowlist, exact ABI shape, canonical narrow integers/addresses/booleans, collection bounds and the complete resulting configuration. A well-encoded payload is not sufficient evidence of executability.

Prefer the target's read-only validator/preview, sharing its actual execution validation and product errors, rather than implementing a second economic rule set in the queue. Include applicable live caps, solvency, available/rescuable amounts, destination restrictions and unchanged-pointer rules. If a prerequisite cannot be validated on-chain before dispatch, record that limitation and its execution-time check. Do not probe a state-changing setter with `staticcall` as a substitute: a valid setter can fail simply because it writes storage. Queue-time validation must not execute the mutation or transfer funds.

Preflight is current-state validation, not a promise about future execution. Balances, configuration, authority and lifecycle can change during the delay; target execution must recheck them, with failures rolling back atomically and preserving the pending intent. Keep deliberately live quantities out of commitments unless the product requires a frozen assumption. Preserve deliberate product errors for invalid input and malformed metadata.

Revalidate execution-time authority and target conditions at the appropriate boundary. Do not insert another state-changing external call between the base's state check and intended dispatch. Use the existing bounded-call/revert handling pattern when the target boundary needs it; specify the cap and distinguish preserved errors from wrapped empty/oversized failures.

Test the real callback boundary. The base marks an action executed before dispatch and retains all batch keys in flight; this prevents same-action replay and conflicting requeue, but is not a universal ban on nested independent actions. A product or target may impose an additional settlement guard. Preserve that actual contract rather than assuming every nested call must fail.

Deliver the operation/lifecycle matrix, key and hash definitions, drift behavior and scenario-to-test evidence. Report actual validation and remaining gaps. Skill use authorizes no deployment, role assignment, history rewrite or publication.
