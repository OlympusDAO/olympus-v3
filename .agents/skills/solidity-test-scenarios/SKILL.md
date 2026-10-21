---
name: solidity-test-scenarios
description: Analyse a Solidity contract function into a concise Markdown scenario plan, implement or assess its Foundry tests and helpers, and maintain scenario-to-test coverage mappings. Use for function-level state/input coverage planning, scenario documents, missing-test comparisons, or tests driven by an agreed matrix.
---

# Solidity Test Scenarios

Produce a reviewable account of what a function must do across caller, contract-state and input combinations, then connect each scenario to tests that actually prove it. The scenario document is the acceptance criteria, not a catalogue of the current test names.

## Scope and outputs

Follow the requested phase:

- Analysis/planning: inspect code and write or review the scenario document. Do not implement tests or change contract behavior unless requested.
- Comparison: map existing tests, identify absent/partial coverage and explain the missing proof. Do not silently change the agreed expectations to match current tests.
- Implementation: use the agreed scenarios to write or fix grouped tests and necessary helpers, then update coverage mappings and validate.
- Maintenance: reconcile the document and tests after changes; retain scenario IDs when behavior is unchanged.

For a new function, place functionName.md beside functionName.t.sol, following the repository's naming. Keep one document per independently callable action, including paired boolean setters and their queue wrappers. Co-locate directly corresponding preview/getter assertions, but do not merge sibling actions' scenarios or fixtures merely because their names and behavior are similar. Use existing repository testing/ERC-20 guidance where available.

## 1. Derive the behavior and dimensions

Read the concrete implementation and its inheritance chain: ancestor contracts, inherited modifiers/storage, overrides and hooks, then internal callees, relevant getters, external dependencies and actual caller/forwarding contracts. Trace which state variables the executed path reads and writes, including inherited and external state. Interfaces and existing tests supplement this evidence. Distinguish current behavior from a proposed rule; an implementation gap is not permission to change production code.

For each candidate state dimension, identify the check, calculation, transition or observable effect it can change. Do not assume every function has enablement, policy membership, payouts or a preview. Show the inferred dimensions to the user when developing the plan, and offer to clarify intended behavior or overlooked states. Ask targeted questions when the source leaves intent, relevant history or supported combinations uncertain; continue analysis that does not depend on the answer.

Identify only dimensions that can change the outcome or required effects:

- Caller identities and permissions. Derive every permitted caller class from the function's access logic and define callers outside that complete set. Replace generic template labels with those classes in the actual document. For a permissionless function, fuzz all callers. A forwarder's own state matters only if it affects the tested call path.
- Independent state gates, if present: pause, ownership, initialization, timing, local enablement, external authorization or other relevant state. Do not conflate distinct gates or assume a particular framework.
- Parameters and semantic boundaries: zero/nonzero addresses, special destinations, numeric limits, rounding/transition points and collection sizes.
- Address relationships: distinct identities, every relevant overlap, selected recipient and unrelated identities. Random addresses almost never exercise equality; represent compatible partitions explicitly.
- Accounting/state relationships: empty/populated buckets, one/multiple eligible buckets, unrelated obligations, aggregate/custody/surplus and index membership.
- External interactions: success, a representative dependency failure, relevant callbacks/reentrancy and read visibility.

State which combinations are incompatible and why. Track history only if it changes behavior or the user/repository requires it; do not invent re-enabled/reactivated rows for an otherwise sufficient current-state matrix.

Do not add lifecycle or caller gates to framework hooks merely for consistency with ordinary policy actions. In particular, treat `configureDependencies` as permissionless across lifecycle states unless its actual implementation or inherited modifier imposes a restriction. Likewise, preserve inherited enable/disable/re-enable/grace-period behavior unless a concrete override changes it; do not propose an own-policy activity gate solely because nearby business actions use one. Model unset cached dependencies as the behavior produced by the implementation, not as a reason to propose a new gate.

Model configuration functions as transitions, not isolated snapshots. When one setting gates another, cover each valid ordering and the reverse transition: for example, selecting or clearing a dependency before and after enabling a route. Trace where already-accrued or pending obligations remain assigned when routing flags or pointers change; distinguish new accrual routing from settlement of existing obligations.

Treat a same-value setter call as its own transition case. Derive whether validation is re-run before equality is determined, and state the intended observable result explicitly. When the accepted behavior is an idempotent no-op, require no storage change and no setter event; do not describe it as an ordinary successful update.

Include only invalid dependency states that can reach the function through production calls or plausible external lifecycle drift. Do not repeat an interface-invalid stored dependency at downstream setters when the pointer setter makes that state unreachable. A selected dependency becoming Kernel-inactive or locally disabled later is reachable when the external contract controls that lifecycle, so treat those as separate live-validation dimensions when the call path checks them.

For queued or forwarded configuration, derive each validation stage separately: queue-time prerequisites, the committed action and pre-state hash, state changes after queueing, execution-time conflict detection, and live downstream validation. If queueing validates a prerequisite, test its rejection there. If a once-valid action becomes invalid later, distinguish a state conflict from a downstream revert and state whether the action/key is retained.

Derive error precedence from the actual call path. Cross callers outside the permitted set and failing state gates with invalid inputs where applicable; include competing faults where the earlier check matters. If a corresponding preview exists, derive its behavior separately: it may omit authorization, lifecycle, guard or external interaction checks.

Trace inherited custom errors to their defining dependency before renaming or simplifying them in the plan. An unfamiliar error such as a never-initialized lifecycle error may be deliberate upstream behavior rather than a new project-local choice.

## 2. Write the scenario document first

Read [scenario-format.md](references/scenario-format.md) when creating or restructuring a document. Adapt its columns and example to the function's actual state, parameters and effects.

Keep the document concise:

- Define symbols, identities, units, inclusive ranges and default state once. Distinguish state relevant to the selected entity from unrelated state when needed.
- Give each behavior group a stable ID. Each row should have one expected outcome and validation path; split cases with different errors, target validation or state effects. One row may describe a genuinely equivalent fuzzed family plus deterministic seeds; IDs are not fixture IDs or a requirement for one test per combination.
- Choose table boundaries by dimension relevance. Keep a coherent cross-product in one table when its columns all affect those cases. Split authorization, lifecycle or behavior into separate tables only when a whole group does not use some columns, and state the fixed or crossed inputs once rather than fragmenting one behavior across several tables.
- Before choosing table columns, list the independently variable facts that can change validation, routing, output representation or effects. Give each such fact its own named column in every table where it varies: for example, subject-policy Kernel activity, subject-policy local enablement, dependency-policy activity, the exact routing flag, resolved destination, asset/listing state, vault-support mode, custody/output mode, pending-bucket mask and transfer behavior. A combined state cell is acceptable only for facts that form one semantic state or are fixed for the entire table and stated immediately above it.
- Use the function's parameter and storage names consistently. Do not hide a relevant dimension behind phrases such as "state and inputs", "valid state", "flag already true", "each routing flag", "compatible recipient" or "fuzz cross-product". If a flag selects a destination, show the flag and resolved destination separately. If support can come from a direct vault, an underlying asset or neither, show that mode separately. Replace transition shorthand such as "enable from false" or "owns an action" with the exact pre-state, input and fuzz domains.
- Fuzz dimensions that do not change the row's outcome instead of enumerating every permutation, but name each domain and keep independent dimensions independent. Split values such as zero and nonzero addresses when they follow different validation paths. Use a fixed representative value when varying a dimension would add no proof.
- Include Caller explicitly. Capture preview/return values, execution/revert data, bucket/state changes, balance deltas and events where relevant. Define Unchanged once.
- Name the entity that each state column belongs to. For example, say whether an asset is supported by the caller, listed by a dependency or merely unrelated; do not imply that a fuzzed field affects the target when it only proves isolation.
- Put the fuzz range, identity partitions and exact boundary seeds in the row or its clearly referenced domain definition. Avoid a redundant generation column or verbose fixture catalogue.
- If using a BTT tree for comparison, keep all state/input dimensions and effects explicit. The tree supplements the table; it is not a second competing specification.

Resolve material disagreements about expected behavior before writing dependent tests. Continue independent analysis while clarification is pending. Existing authorization to implement an agreed plan does not require another blanket confirmation.

## 3. Map coverage honestly

Use these labels in the Test column:

- Unmapped: no test has been identified.
- Partial: name the missing combinations, boundaries, seeds or assertions.
- Covered: the linked tests implement the row's entire stated compatible domain and required effects, with focused validation passing.

Link the actual test functions, including seed drivers when they supply guaranteed combinations. Several rows may share a test; one row may need several tests. Add a Scenarios comment to each mapped test and seed wrapper, not just a shared helper.

Audit the generators and assertions, not only test names or line coverage. Inspect bounds, assumptions, selectors, early returns, fixture budgets and oracle dependencies. Check that fixture restrictions apply to the correct parameter: an address forbidden as a destination may still be a valid owner or original recipient. A passing test does not prove combinations it cannot construct. Check both directions: every planned row has proof, and every retained test has a distinct purpose.

For short table labels and maintainable links, use named Markdown references keyed by the actual test function names, as shown in the format reference. The mapping helper checks/refreshes their line anchors:

    python3 <skill-dir>/scripts/check_mapping.py path/to/functionName.md
    python3 <skill-dir>/scripts/check_mapping.py path/to/functionName.md --update

Update only when document edits are in scope. For existing inline links, retain the repository's format and refresh them directly. The helper verifies named references, function locations and reciprocal scenario IDs; it cannot certify semantic coverage or legacy inline mappings.

## 4. Implement the smallest tests that prove the plan

Keep each test focused on one behavioral outcome. Separate success from rejection, different errors, and caught from propagated callback failures. The name, setup and expected result should make the case clear without decoding a scenario selector. Equivalent inputs may share a small loop when every iteration proves the same outcome; avoid nested loops that choose between unrelated cases.

Duplicated setup is acceptable when it makes the proof easier to read. Prefer explicit fixtures and named modifiers to numbered states, outcome bitmasks, ternaries selecting expected errors, or helpers that configure, execute and decide the result. Share mechanical setup and accounting assertions when they reduce noise without hiding the case. More individually readable tests are better than one compact test that covers several outcomes.

Name fixed fixture quantities and derive reserve/custody totals from those constants. Keep literal zero and one where they directly express a boundary. Preserve intentional helper scopes that limit local-variable lifetimes; remove nesting left over from split drivers and format the result before review.

For ordinary cases, choose distinct, readable constants for relevant state quantities and fuzz the operation input within the scenario's explicit interval. The constants are examples, not universal values or substitutes for numerical coverage. Put variable state quantities, solvency budgets and type-maximum splits in separate focused numerical tests. Define selected-entity eligibility separately from obligations owed to other entities.

Audit each fuzz parameter for the distinct behavior or assertion it can change. Use fixed addresses when only their role matters; construct equality/overlap explicitly. Remove inputs that are ignored, overwritten or forced to a constant by the case. Keep unauthorized-caller fuzzing and meaningful numeric domains. When two independent dimensions matter, use separate selectors or enumerate one; deriving both from the same value (such as amount % N) can exclude combinations. Skip a duplicate combination only when it constructs the same state, request and expected assertions.

Separate state construction from selection and execution: configure identities, record exact quantities, add unrelated obligations, and arm interactions in small helpers. Keep the caller, selected entity, lifecycle and input interval visible in the test or a clearly named modifier. Avoid a catch-all input struct that chooses and transforms all of them. Assert the constructed state before execution. A success test should construct a compatible case directly; do not silently return when a generated case is unsuitable.

- Fuzz the continuous input range for each outcome. Enumerate compatible discrete identities/presence states and seed exact endpoints and adjacent transition values through the same case checks. Distinguish reachable fuzz domains from guaranteed executed seeds: a passing random run is not exhaustive combination coverage. A one-unit seed does not prove a larger bucket's partial interval.
- Use bound for exact numeric intervals and assume only to constrain genuinely fuzzed inputs. Assert required properties of fixed fixtures instead of silently rejecting runs. Keep unauthorized callers' exclusions limited to authorized identities. Test permissionless caller behavior where relevant; co-located previews can use a fixed caller once authorization tests establish caller independence, without adding a preview-caller argument to every test.
- Test zero, one, semantic caps, adjacent values and the numeric type maximum where applicable. For inputs above a limit L, fuzz L+1..MAX only when L < MAX; do not substitute another invalid input for an empty interval.
- Respect actual fixture constraints without arbitrary caps that make planned boundaries unreachable. Derive budgets, relationships and independent entities from the target's state model; preserve absent/optional states.
- Share setup, success and rejection assertions within the action's tests. Reuse existing token mocks and Foundry primitives instead of building a generic matrix framework or manually decoding events when native expectations plus exact counts suffice.
- Have targeted tests supply explicit expected results or simple scenario-specific formulas. Assertion helpers should verify those expectations, not decide the same outcome with a copy of the production algorithm. Focused variable-quantity tests may need an independent model; check it against small explicit examples. Assert each raw component, aggregate, balance/custody deltas, unrelated obligations and indexes where relevant. If a getter filters stale entries, it cannot alone prove internal index removal; check underlying membership when that is part of the scenario.
- Reference events from their declaring interface where supported rather than redeclaring them in the fixture. Verify exact event fields, emitters, ordering/count and zero-debit omission. Match exact revert selectors/arguments and relevant rollback state. A reverted call has no committed events; cheatcode-recorded reverted subcall logs are not receipt logs.
- Co-locate preview/getter agreement with execution, including execution-only failures. Compare reads with independent expectations rather than making preview the sole success oracle.
- For callbacks, authorize the nested route so it reaches the intended guard. Keep outer and nested entity/recipient choices independent when relevant, and guarantee both distinct and overlapping identities. Distinguish caught and propagated failure; check configuration/accounting, single payment, and relevant callback reads.
- Snapshots restore EVM state, not mutated memory models. Copy mutable expected data at a clear ownership boundary. Split deterministic drivers when cases become difficult to follow, even if they fit runtime/memory limits; reserve snapshots for independence between repeated checks within a case.
- Name helpers for their action or assertion. Document non-obvious parameters and returns, especially global recorded state versus selected-entity eligibility. Use enums for semantic choices and named constants for bitsets; define each bit and whether it describes global presence or selected eligibility. Add short scope comments to complicated tests stating fixed setup and varied dimensions; keep full expected behavior in the scenario document. Explain allocation math, constraints and snapshot handling without copying assertion checklists above every test.

Use repository test naming; for given/when names, given describes existing state and when describes operation inputs. Stateful invariants complement per-call tests when relationships must survive sequences. Record their actual actor/token/state scope; do not promise coverage the handler cannot generate.

Before removing a test, name its retained replacement and compare constructed states, input intervals, guaranteed boundaries and assertions. Do not assume a more general-looking generator subsumes it. Prefer the clearest proof regardless of which test is older; keep useful explicit regressions. Mark conditional replacements and deliberate scope exclusions honestly.

Do not retain a duplicate baseline suite alongside a replacement indefinitely. Preserve a requested benchmark using the authorized checkpoint workflow, then consolidate only after replacement coverage and focused checks pass. Do not create a checkpoint or delete files outside the user's authorized scope.

## 5. Validate and maintain

Run the changed function's focused tests and the repository's required build/format/lint checks. Avoid unrelated full suites or publication actions. After formatting/renames, refresh links and Scenarios comments.

Before marking rows Covered, check for:

- Generic catch-all columns that contain two or more independently variable facts; split them into named dimensions or state the fixed dimensions above the table.
- Missing identity partitions or bucket masks; absent/full/partial eligibility.
- Invalid ranges transformed into success, MAX/overflow boundaries excluded, or early returns masking a claimed case.
- Preview/implementation/model sharing the same mistaken expected value.
- Aggregate-only assertions concealing compensating bucket errors; missing unrelated-keeper/token checks.
- Missing rollback/index/event/configuration assertions or callbacks failing before the intended guard.
- Duplicated suites, bespoke assertion machinery or speculative fixtures that can be removed without losing proof.

Report the artifacts, remaining Partial/Unmapped rows and exact validation outcome. Read-only review findings remain proposals. If behavior changes later, revise expectations and test mappings together; never keep a stale Covered label.
