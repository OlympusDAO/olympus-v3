---
name: solidity-test-scenarios
description: Plan Solidity function scenarios, implement or assess Foundry tests against them, and maintain scenario-to-test coverage mappings. Use for function-level coverage and scenario documents.
---

# Solidity test scenarios

Treat the scenario document as acceptance criteria, then connect it to tests that prove those criteria. Source inspection establishes current behavior; it does not override an agreed requirement.

## Scope and ownership

- Planning/review: inspect implementation and existing tests; edit the requested plans. Do not implement contracts or tests without authorization.
- Implementation: use the agreed plan and repository test-writing/ERC-20 guidance. Write failing tests before changing behavior.
- Coverage maintenance: update Test mappings, reciprocal comments and link anchors. Preserve approved expectations, IDs and structure unless the user requests a change or a substantive conflict needs resolution.

For Kernel policies and their dependency boundaries, also apply [policy-lifecycle](../policy-lifecycle/SKILL.md). It owns policy admission, dependency binding/setters and enable/disable/reEnable rules; do not maintain a competing checklist here. Read [scenario-format.md](references/scenario-format.md) when creating or restructuring a document.

Keep one function-based plan per independently callable action. Put corresponding preview/getter assertions in the action's existing tables and tests. Do not add preview stub files, preview-only sections, shared scenario files or indexes as a substitute for complete function plans. Preserve existing test locations unless moving them is authorized. A contract rename alone does not require new scenario IDs.

## Derive the acceptance criteria

Read the concrete function, inherited guards/hooks, internal callees and relevant external contracts. Inspect the extensive existing tests for regression evidence, fixture assumptions and expected accounting; do not infer coverage from names alone. Record file/line references to the implementation and useful existing tests.

Identify only facts that change admission, validation, economics or effects:

- Actual caller, permitted roles, delegated grants and forwarded actor/payer/recipient identities.
- Independent local and dependency states, reachable lifecycle drift and relevant initialization history.
- Input bounds, collection limits, address overlaps and absent/existing positions or obligations.
- Pricing/conversion inputs, credited versus requested amounts, caps and rounding direction.
- Authoritative state, custody, external transfers and rollback boundaries.

Trace guard order, including modifier expansion and external reads. Name exact errors and arguments from their declaring interfaces; distinguish own-policy inactivity from a failed dependency. Include competing faults where order matters, rather than multiplying every error by every invalid input.

Keep required behavior, observed source behavior and unresolved decisions distinct. Flag material conflicts once near the relevant section or in the Test mapping; do not replace the expected Preview/Execution value with an implementation-gap essay. Ask about unresolved security, governance or integration choices before writing dependent tests; reuse answers already given.

## Write focused tables

Define identities, units, fixed defaults, inclusive fuzz domains and Unchanged once. Unchanged covers relevant authoritative accounting, balances/allowances and indexes; a revert commits no logs.

Group cases by the dimensions their tables need: authorization, lifecycle, invalid inputs, numeric boundaries, successful execution, transfers or callbacks. These are useful groups, not mandatory headings. Keep each table's varying facts in separately named columns; state constants directly above it. Put `Local active` next to `Local enabled`, and keep each dependency's active/enabled columns adjacent. Avoid generic State/input columns and unspecified permitted callers.

Give each row one outcome and validation path. Split distinct invalid fields, fee/risk configuration failures, errors, zero/nonzero balance behavior and caught/propagated failures. Use equivalent caller or input fuzz families instead of duplicated tables. Name the complete accepted caller set; unauthorized fuzzing excludes every accepted identity. For delegated authorization, include a valid borrower B→operator O grant with an unrelated caller X≠B,O and no grant to X. Fuzz grant deadlines and time independently, with equality and adjacent seeds. Fuzz callers for permissionless functions, but avoid redundant caller variation in arithmetic regressions once caller independence is established.

State whether each cap applies to nominal input or actual credited/settled output. When those differ, assert that stored position/accounting uses the authoritative value. Keep validators and setters consistent on the same fee/risk field boundaries; forwarding tests prove delegation, not a second implementation of the validator.

For configuration, include same-value behavior and interacting setting transitions. Repository defaults: an unchanged contract pointer reverts; an unchanged ordinary parameter is a no-op without writes/events. Reject an unchanged contract pointer before migrations or authority handoff. Preserve approved validation order and exceptions, including setGracePeriod as described in policy-lifecycle. For queues, separate queue validation, committed target/pre-state, intervening drift, execution conflict/downstream failure, and whether failure retains the action/key.

## Previews

Use a Preview column in existing action tables when applicable. Repository default: return a quote on success and revert on applicable admission, input, dependency, pricing or economic failure. Do not introduce executable flags, reason enums or error-selector forwarding.

Previews are permissionless: the quote requester need not be the borrower, an authorized operator or a governance caller. Keep borrower/input validation separate from execution-only caller authentication. An explicit onBehalfOf_ identifies the position owner; use a distinct actor/payer parameter only when that identity affects the quote. Retain checks on the action contract's own settlement authority where required for service usability. Prove that unrelated viewers receive the same quote under equal economic state while unauthorized execution still rejects. Quote-only calls must not read borrower/operator authorization or require payer balances/allowances. Where a permissionless downstream preview previously checked a forwarder's authority, update the wrapper's scenarios explicitly instead of assuming that quote proves execution authority.

State exceptions once when a check is execution-only because of the API or approved semantics, such as a real token delivery. Missing source validation is not an approved exception. Identify the economic actor separately from the view caller when the API accepts an actor. Compare exact values/errors under equal relevant state and stored/refreshed snapshots; do not use the preview as the sole expected-value oracle or require it to predict a mutating callback's outcome.

## Prove each contract's responsibility

Choose mocks from the actual call graph: if an action only forwards a settlement result, test that handoff there and calculator use in the settling contract. For action/forwarder unit tests, mock replaceable calculators and downstream boundaries where useful. Configure arbitrary returned fees/rewards independently of the position inputs, then assert exact call arguments and unchanged use in limits, settlement instructions, collections, returns and events. Zero fees should not trigger collection/handoff. Assert delivery to the component that owns routing; test Treasury/distributor choices, delivery failures and pending-bucket behavior in that component's suite.

Use real dependency integration tests separately to prove wiring and arithmetic. For rounding, decimal-scale and sub-unit edge cases, choose small fixed inputs and hard-coded expected integers with the derivation explained. Do not fuzz these particular regressions or reproduce production math as the expected result. Fuzz broader numeric properties separately. Express amounts in raw units of the actual underlying/share output; test zero allocations and conservation. A remainder defined as output minus an already-rounded reward is not independently rounded.

Each token-moving action needs a representative token callback case. Authorize/fund an otherwise-valid nested operation so it reaches the intended guard; use another eligible position if the outer action has already consumed its own. Assert the guard rejection and the required outer success or rollback. Add further routes or caught/propagated cases only when they establish a different security boundary or effect, such as mandatory rollback versus optional payout deferral. Do not expand every action into an all-contract callback matrix or repeat safe-transfer library return-shape tests.

## Implement and map honestly

Keep fixtures semantic, setup separate from execution, and tests focused on one outcome. Follow repository given/when naming and descriptive assertions. Prefer existing mocks and simple helpers over numbered fixture selectors, outcome bitmasks, generic matrix runners or helpers that also decide the expected result.

For test placement, branch splitting and shared setup/error helpers, follow [test-write's Test Body Shape and Helper Boundaries](../../../.claude/skills/test-write/SKILL.md#test-body-shape-and-helper-boundaries). Preserve the covered domains and assertions when moving cases into their external action's file, and refresh both sides of the scenario mapping.

- Fuzz continuous valid/invalid intervals; guarantee zero, one, semantic boundaries, adjacent values and the numeric type maximum where applicable. Distinguish random coverage from deterministic seeds. Keep independent dimensions independent.
- Use bound for the stated numeric interval and assume for genuinely variable constraints. Do not silently return, substitute a different invalid input, or impose an arbitrary fixture cap to hide an untested boundary.
- Assert actual token/custody deltas, raw bucket components and aggregates, unaffected relevant entities, indexes and exact event fields/emitters. A filtered getter alone does not prove internal index removal. Recorded reverted subcall logs are not committed receipt logs.
- A model must supply independent expectations, not call the same implementation. EVM snapshots do not restore mutated in-memory models. Use stateful invariants for applicable relationships across call sequences, with the handler's real scope stated.
- Before replacing/deleting tests, identify the retained proof of their states, ranges, seeds and assertions. Preserve requested legacy/reference suites; do not create checkpoints or delete them merely to simplify the task.

Use only these Test labels:

| Status | Required evidence |
| --- | --- |
| Unmapped | No test identified for this row. |
| Partial | Linked tests prove part of the row; name the remaining domains/assertions. |
| Covered | The linked tests prove the entire stated compatible domain and effects, and focused execution passes. |

Map actual test functions and deterministic seed drivers, with reciprocal `// Scenarios:` comments. Several tests may prove one row; one test may prove several rows. Existing legacy tests inform the plan but are not automatically proof for a rewritten API.

Do not use inline test links such as `[test](functionName.t.sol#L42)` in scenario tables. Use named reference links such as `[test][test_givenState_whenAction]`, with `[test_givenState_whenAction]: ./functionName.t.sol#L42` defined once at the bottom of the document. This keeps line-number updates out of the tables. Preserve readable link labels and key references by the actual function name; qualify the reference with `--fileStem` only when different test files contain the same function name. Apply this format to existing scenario tables as well as new ones.

Keep all reference definitions together in a final footer after every table, section and prose paragraph. Only reference definitions and blank lines may follow the first definition. When adding scenarios or notes, insert them above the footer; do not append tables or other content below existing definitions.

The existing helper checks named test/invariant references, function locations and reciprocal IDs. Shared tests may name cases in other scenario files or suites under `src/test`; reciprocity is checked within the selected document:

    python3 <skill-dir>/scripts/check_mapping.py path/to/functionName.md
    python3 <skill-dir>/scripts/check_mapping.py path/to/functionName.md --update

The helper rejects inline test links in tables and content below reference definitions, and checks file-qualified references against their actual function names. It does not certify semantic coverage. Refresh anchors only within the authorized document scope.

Run focused tests when code/tests change and the required repository formatting/lint checks. For documentation-only work, validate Markdown, links, IDs and mappings without claiming Solidity behavior is proved. Report remaining Partial/Unmapped cases and actual validation failures; keep unrelated suite failures separate. Never weaken an expected result to make a test pass.
