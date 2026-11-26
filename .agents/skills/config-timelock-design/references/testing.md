# Testing a product configuration timelock

Use the repository's [test-writing guidance](../../../../.claude/skills/test-write/SKILL.md), [scenario skill](../../solidity-test-scenarios/SKILL.md) and [policy lifecycle skill](../../policy-lifecycle/SKILL.md). Write acceptance scenarios and failing behavior tests before implementation. Keep one function document/test file per action and preserve existing IDs when moving an action.

## Separate proof ownership

The shared-base suites own generic ID handling, bounded batch storage, duplicate/zero key validation, reservation ownership, cleanup and execution order mechanics. Product tests own their actual selector/payload surface, target binding and lifecycle, keys/hashes, dispatch, economic effects and interactions. Add shared-base tests only when changing those mechanics; do not reproduce every unchanged base scenario for every wrapper.

Use both unit and real-target integration tests. A mock proves exact target/selector/arguments and error propagation; it cannot prove actual operator authorization or target economic checks. For getters/previews, verify exact state and admission without borrowing execution authorization assumptions.

## Function-level acceptance matrix

| Dimension | Product evidence |
| --- | --- |
| Proposers | Fuzz every permitted exclusive role and overlap; fuzz unauthorized callers excluding all accepted identities. Queue role alone must not authorize direct target writes. |
| Target ADMIN path | For delegated setters, ADMIN works with zero, selected or different operator; selected non-ADMIN works; former operator and domain-admin-only callers fail. Separately prove ADMIN-only setters reject an operator without ADMIN. Test authorized no-ops and competing unauthorized no-ops. |
| Operator rotation | Authorized immediate selection/revocation, unchanged-address rejection after authorization, paused repair if specified, no upstream lifecycle probes. Prove startup without circular activation. |
| Own lifecycle | Active/enabled, inactive/enabled, active/disabled, inactive/disabled; successful reEnable/reactivation; appropriate framework/getter exceptions. |
| Target lifecycle | Both activation routes require compatible interfaces, matching Kernel, active target and selected operator, with target enabled/disabled both accepted and no target isEnabled read. At queue/execution test all four independent target pairs: inactive targets always reject; active/disabled targets succeed only for selectors that deliberately permit local pause. Cover drift after activation and separate paused-capable from enabled-only mutations. Do not encode inactive-target admission as an accepted precedent. |
| Interface parity | Enumerate the consumed interface IDs and prove constructor, enable and reEnable reject each missing interface with the owned invalid-target error. Guarantee each ID with explicit seeds. Reuse the interface predicate so an activation-only check cannot drift from construction. |
| Kernel binding | At construction and both activation routes, a canonical foreign Kernel gives PolicyDependency_KernelMismatch(target,expected,reported). A reverted, empty, short, oversized or noncanonical address response from kernel() gives PolicyDependency_InvalidDependency(target). Check binding before readiness. A same-Kernel inactive target constructs successfully but cannot activate the queue. |
| Construction readiness independence | Deployment succeeds in all four target activity/enablement pairs, before this queue is selected as operator, and with target status, membership and operator reads reverting. Assert exact defaults and no target mutations. Construction must not probe unused runtime metadata, including through readEnabled. Activation separately requires authoritative target membership and selected operator, without reading target enablement. |
| Other metadata/binding | Cover wrong system bindings and failed/short/trailing/noncanonical consumed getters with exact owned errors; revalidate reachable mutable compatibility metadata. |
| Payload surface | Wrong target/selector, empty/short/trailing encodings, dirty bool/address/narrow integers, every semantic boundary and type maximum; dynamic canonical encoding/length bounds if applicable. |
| Queue result | Exact action metadata/payloads/events, independently encoded scoped keys and expected pre-state hashes; no target mutation, economic transfer or authorization side effect. |
| Admission preflight | Well-encoded but currently invalid operations reject before recording intent: invalid resulting configuration, unavailable target, lost delegation, exceeded live cap/amount, forbidden destination or unchanged pointer where relevant. Assert target validator/preview use and matching product errors; no ID/key/payload leak. Record any checks that genuinely require dispatch. |
| Numeric limits | Zero/one/exact semantic caps, adjacent values and type maxima; empty/single/maximum batch and aggregate key counts. Match documented error versus existing shared overflow behavior honestly. |

Guarantee boundary values with deterministic seeds; fuzz the compatible interior independently. Use exact selectors/arguments and descriptive assertions. Do not change expected behavior to match a failing implementation or call a production-failing scenario Covered.

## Conflicts and queue-to-execute drift

For every domain pair, establish whether it conflicts, is independent, or is intentionally admitted with a later stale-state outcome.

- Same setting via identical or different selectors conflicts within one batch and across pending batches. Per-entity operations conflict only where the underlying domains overlap.
- Independent domains queue and execute in both orders. With three domains, cover queue and execution permutations as in the Risk tests. Do not stop at proving simultaneous queue success.
- Direct ADMIN changes to every committed field cause the expected stale error. Unrelated settings and excluded live balances/debt do not stale the action. Assert stored commitments are unchanged during the delay.
- Operator revocation/replacement, target rotation and Kernel/readiness drift follow the documented error precedence. Restore state and retry within the **original** window; verify the agreed current-state versus historical-epoch behavior.
- A queue-time preview can pass and a target live cap/amount/solvency check can later fail. Assert the target error and full rollback, with keys and intent retained for a valid retry or cancellation.
- An expired/stale unresolved action does not block unrelated keys. A conflicting replacement stays blocked until cancellation releases the key, then queues with a fresh ID and notice period.

Read the stored `queuedAt`, `executableAt` and `expiresAt`. Fuzz the complete permitted execution interval and seed E-1, E, X and X+1 when representable. Execution is permissionless: fuzz the executor independently of proposer/governance identities. Changing a configured delay, if supported, must not silently change existing stored deadlines.

## Atomicity, cancellation and callbacks

Queue failure leaves no leaked ID increment, stored payload, commitment, key or committed event. Execution failure after an earlier successful sub-action restores target configuration, custody/accounting, action flags, payloads and every reservation. Successful execution/cancellation releases every owned key and guard; repeated terminal calls do not dispatch again.

For cancellation, vary own activity and enablement independently, notice/live/expired time, and cancellation caller roles. Make target metadata reads revert and rotate/revoke the operator; cancellation must not read either. Active paused cancellation succeeds for EMERGENCY; own inactivity still rejects. Cancellation changes queue state, not target configuration or balances.

Exercise a representative authorized target/token callback, both caught and propagated where outcomes differ. Assert same-action replay is blocked and an in-flight batch retains every key, including keys for later sub-actions. For a nested independent action, assert the actual product/target guard behavior; the generic base does not by itself forbid all nested execution. After propagated failure, reconcile both outer and nested actions and target effects.

Use one real multi-action integration test for the full proposer -> queue -> selected-operator target path. Assert authoritative resulting configuration, relevant balances/obligations and exact target call counts where delegation is the property. Admission failures should prove there were no prohibited target mutations or token calls.

## Stateful model and validation

For new multi-domain queues, maintain an independent model of pending action ownership and relevant settings. Exercise queue, time advancement, direct ADMIN changes, lifecycle/operator drift, execute and cancel. Assert that unresolved owners retain exactly their keys; terminal actions own none; no action executes twice; failed dispatch is atomic; independent domains remain live. Include deterministic drivers for rare boundary/repair sequences rather than relying on random discovery.

Map implemented functions/seed drivers with reciprocal `Scenarios:` IDs. Mark partial proof honestly and keep test execution status separate. Run affected files and meaningful integration/invariant campaigns, then required formatting/lint and deployment-profile bytecode size checks for Solidity changes. Follow the repository's approval gates for full suites. Documentation-only skill changes need link/format/skill validation, not a new full Solidity run.
