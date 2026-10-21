# Scenario document format

Use this shape as a starting point, not a fixed schema. Keep expected results concrete and adapt the state/input/effects columns to the function. Omit inapplicable columns and sections.

## Compact skeleton

    # functionName coverage plan

    ## Domains and notation
    Define caller classes, state gates, identity partitions, units, inclusive ranges,
    defaults and incompatible combinations. Define Unchanged once.

    ## Shared assertions
    Success: independent expected return/accounting, balance deltas, relevant events
    and indexes, isolation, and preview/getter agreement.
    Revert: exact error and relevant rollback; distinguish preview-only checks.

    ## Authorization and lifecycle
    Include only when a separate table helps; say which input rows it crosses.

    ## Behavior and inputs
    Group equivalent combinations into fuzz families with explicit boundary seeds.

    ## Invariant coverage
    If applicable, map properties to existing/new invariant checks and state scope.

    [test_functionName]: ./functionName.t.sol#L123

Default behavior table (replace the example state columns with the dimensions the
function actually reads):

| ID | Caller | Subject state | Dependency state | Routing / identity state | Input / fuzz domain / exact seeds | Preview / return | Execution / error | State / balance effects | Events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P-01 | Each permitted caller class | Exact relevant gates | Exact external state or N/A | Exact flag, destination and relationship | Valid range plus boundary seeds | Independent expected value, if applicable | Success | Explicit affected and unaffected state | Contract-derived events, if any | Unmapped |
| I-01 | Each permitted caller class | Same gates | Same dependency state | Same routing and identities | One invalid input; remaining inputs valid | Exact input error, if applicable | Actual input-check failure | Unchanged | None committed | Unmapped |

Do not copy columns that are inapplicable. Conversely, do not collapse multiple
independent dimensions into a generic `State and inputs` cell merely to keep the
table narrow. When a dimension is constant for every row in a table, state its
fixed value immediately above the table and omit the column.

Separate authorization/lifecycle table, if useful:

| ID | Caller | Relevant contract state | Inputs | Preview / return, if any | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L-01 | Each permitted caller class | Required gates satisfied | Each applicable behavior/input row | Function-derived behavior | Success or input error | Expected updates or Unchanged | Unmapped |
| L-02 | Any caller outside the permitted set | Same state | Same cross-product | Function-derived behavior | Actual access-check failure | Unchanged | Unmapped |
| L-03 | Each permitted caller class | A required gate unsatisfied | Valid and invalid inputs | Function-derived behavior | Actual failure in check order | Unchanged | Unmapped |

Define the permitted set from the actual access logic and name each class in the completed document. Replace error placeholders with the contract's exact errors and arguments. Expand independent state gates and permitted caller classes into separate rows where their combinations matter. Omit access-rejection rows for a permissionless function; do not invent lifecycle gates.

## Discover the relevant state

Inspect the target contract and its ancestors before filling the tables. Follow inherited modifiers, storage, overrides and hooks, plus called helpers and external contracts. Identify state that can change access, validation, return values, calculations, transitions, events or other effects. An inherited limit can matter even when the function declares no local state.

For each candidate dimension, state what behavior it changes and which values separate those behaviors. Build a short dimension inventory before drafting tables, then map every varying item either to its own column or to a fixed-domain statement directly above that table. If intent or relevance remains unclear, offer the user the inferred dimensions and ask a targeted question, such as: “The inherited modifier checks initialization, but this path does not check pause state. Should the plan include a pause-related expectation?” Do not assume all stored variables need a cross-product.

## Simple example: a bounded input

Suppose a function stores an input value only when it is at most the current limit L. This hypothetical rule illustrates grouping; derive the real rule, access conditions, errors and events from the target code. MAX is the input type's maximum.

| ID | Caller | State | Input / fuzz domain / exact seeds | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| P-01 | Each permitted caller class | limit = L; required gates satisfied | Fuzz 0..L; seed 0, 1 when valid, L, and MAX when valid | Success | Stored value equals input; actual defined events | Unmapped |
| I-01 | Each permitted caller class | L < MAX; same gates | Fuzz L+1..MAX; seed L+1 and MAX | Actual range-check failure | Unchanged; None committed | Unmapped |

Vary L only within reachable states. If the current stored value changes behavior, add same-value/different-value cases; otherwise leave it out of the dimensions. Apply the same relevance test to inherited state and external dependencies.

For ordinary tests, a named constant limit (for example LIMIT = 12) can make valid and invalid input intervals obvious. Fuzz the input within 0..LIMIT or LIMIT+1..MAX and guarantee the relevant endpoints. If a changing limit affects behavior, vary it in a separate focused test and map that test to the same row or a numerical row. State clearly which quantities are fixed, which vary, and which cases are guaranteed rather than sampled.

Boundary cases belong in these rows or the shared domain; they are not a second disconnected catalogue. Add a row only when it establishes a distinct outcome, assertion, boundary construction or interaction.

## Stable mapping with short rendered labels

Keep table labels short while keying the references by actual function name. Use labels such as fuzzed callers, explicit identities, boundary checks or error check order; explain unfamiliar terms once. A label should say what proof the linked test adds.

    | P-01 | ... | Covered: [fuzz][test_givenLimit_whenInputIsWithinLimit], [seeds][test_givenLimit_whenBoundariesAreSeeded] |
    | I-01 | ... | Partial: [fuzz][test_givenLimit_whenInputExceedsLimit_reverts]; missing exact L+1 seed |

    [test_givenLimit_whenInputIsWithinLimit]: ./functionName.t.sol#L42
    [test_givenLimit_whenBoundariesAreSeeded]: ./functionName.t.sol#L80
    [test_givenLimit_whenInputExceedsLimit_reverts]: ./functionName.t.sol#L120

Put reciprocal IDs immediately above each function:

    // Scenarios: P-01.
    function test_givenLimit_whenBoundariesAreSeeded() public {
        // Fixed limit; exercise both endpoints and the adjacent in-range value.
    }

The helper resolves names and refreshes anchors after formatting. If a function is renamed, update its reference key and table uses as well. Duplicate function names in a referenced file are ambiguous: use distinct names or maintain those links manually. A helper's Scenarios comment does not replace the mapped test's own comment. A short test scope comment can state fixed setup and varied inputs without repeating the table's expected effects.

For an existing document with inline links, do not force conversion merely to use the helper. Verify each link's target and row association directly.

## Avoid misleading compression

- Any caller outside the permitted set is precise only after defining that set and excluding every permitted class from the rejection generator.
- All compatible states is meaningful only with explicit dimensions and guaranteed seeds. Name the incompatibilities.
- Remaining unchanged is sufficient for unaffected state once Unchanged is defined; state affected values or formulas rather than every repeated fixture value.
- Treat equal/different identities and selected/unrelated entities as dimensions only when they affect this function.
- Use a small explicit example when it helps check a calculation or transition; do not introduce an accounting model for a function that needs none.
- Do not silently omit a boundary because fixture construction is inconvenient. Mark Partial until the generator can reach it or the agreed domain is narrowed explicitly.
