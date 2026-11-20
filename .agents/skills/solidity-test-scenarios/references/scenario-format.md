# Scenario document format

Adapt tables to the function. The main [scenario skill](../SKILL.md) defines behavior and coverage rules; this reference owns document shape, IDs and links.

## Document shape

Use one function-based document. Co-locate previews/getters in existing action cases; do not add preview files, shared scenario files or an index. Keep approved acceptance criteria stable during test implementation; normally only Test mappings and link anchors change.

Start with source references, brief domains/notation and fixed defaults. Define units, caller classes, numeric types, time boundaries and Unchanged once. Then use only sections whose cases need them, such as authorization, lifecycle, invalid inputs, numeric boundaries, successful execution, transfer failures or callbacks. Do not combine unrelated groups under Authorization, lifecycle and inputs merely to reuse a table.

For each table:

- Give every independently varied fact its own named column. Keep Local active/Local enabled and each dependency's flags adjacent. State table-wide constants above it instead of repeating them.
- Include Caller and exact expected execution/return, effects and Test mapping. Add Preview only when applicable, with an exact quote/error or a named execution-only exception.
- Split distinct errors or effects: individual invalid addresses/config fields, zero-balance no-op versus transfer, and mandatory rollback versus optional payout deferral.
- Group genuinely equivalent fuzz domains, with explicit bounds, identity partitions and guaranteed boundary seeds. Avoid unspecified permitted caller(s), valid state, all combinations or generic state/input columns.

A hypothetical admin-configured function accepting amounts up to LIMIT illustrates different table shapes. It is not a protocol rule. The example assumes no preview and a fixed active/enabled subject with initialized authorization.

### Authorization

All operation inputs are otherwise valid. The only permitted class in this example is ADMIN_ROLE; name the actual complete set in a real plan.

| ID | Caller | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| LIMIT-A01 | Fuzz caller excluding every ADMIN_ROLE holder | Exact role error | Unchanged | Unmapped |

### Invalid inputs

Caller holds ADMIN_ROLE; LIMIT is fixed below MAX, where MAX is the input type maximum.

| ID | Caller | Amount domain / guaranteed seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| LIMIT-I01 | ADMIN_ROLE holder | Fuzz LIMIT+1..MAX; seed LIMIT+1,MAX | Exact range error with amount/limit arguments | Unchanged | Unmapped |

### Successful execution

Caller and LIMIT as above. Equality with a previously stored value is a separate no-op case if the function defines one.

| ID | Caller | Amount domain / guaranteed seeds | Return / execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| LIMIT-P01 | ADMIN_ROLE holder | Fuzz 0..LIMIT; seed 0,1 when valid,LIMIT | Success | Stored amount equals input; exact defined event | Unmapped |

Do not copy these columns blindly. An action may instead need a Preview column, explicit fee, output mode or per-bucket state. Boundary seeds belong in the relevant row/domain, not a second disconnected catalogue. Use fixed integer examples for rounding regressions and broader fuzzing for separate numeric properties.

## Scenario and fixture naming

Use `<SCOPE>-<CATEGORY><NN>` for new IDs, for example `BLTRY-L01`. Define one short uppercase contract/function scope per document. Reuse the established scope; do not create a registry. Two digits are the minimum, not a 99-case limit.

| Category | Main proof |
| --- | --- |
| A | Caller authorization |
| L | Local lifecycle/admission |
| D | Dependency readiness/binding |
| I | Invalid inputs |
| N | Numeric bounds, rounding/overflow |
| P | Success, no-op or configuration transition |
| T | Transfers or ordinary external interaction failures |
| C | Callbacks/reentrancy |
| V | View consistency when no corresponding action owns it |

Allocate the next unused number within the scope/category. Keep caller, state, interface and fault descriptions in columns, not suffixes: VERSION cases use P01,P02 rather than P01-state2.

IDs identify behavior, not row order or fixtures. Preserve IDs when reordering, refining fuzz bounds, moving a function or renaming a contract. A split keeps the old ID for its retained behavior and adds fresh IDs; retire an ID whose meaning is replaced. Do not renumber approved plans during mapping-only work.

When a naming-normalization pass is requested, apply the convention across the authorized scope, not only the example suffix/contract. Reserve all existing IDs before allocation, then update every reference and reciprocal test comment together. A naming-only pass preserves cases, expectations and coverage labels.

Fixture helpers describe state, such as givenPendingFees or givenInventoryDisabled; identities describe roles, such as borrower/operator. Do not use numbered fixtures, scenario-ID-named helpers or opaque bitmask selectors. A fixture may serve several cases; one case may require several tests.

## Coverage links

Use Unmapped, Partial or Covered as defined in the main skill. Do not use inline `.t.sol#L...` links in scenario tables. Use named reference links and put their definitions at the bottom of the document, so changing a test's line number does not change table rows. Keep rendered labels short and key references by actual function names:

    | LIMIT-P01 | ... | Covered: [fuzz][test_givenLimit_whenInputIsWithinLimit], [seeds][test_givenLimit_whenBoundariesAreSeeded] |
    | LIMIT-I01 | ... | Partial: [fuzz][test_givenLimit_whenInputExceedsLimit_reverts]; missing exact LIMIT+1 seed |

    [test_givenLimit_whenInputIsWithinLimit]: ./functionName.t.sol#L42
    [test_givenLimit_whenBoundariesAreSeeded]: ./functionName.t.sol#L80
    [test_givenLimit_whenInputExceedsLimit_reverts]: ./functionName.t.sol#L120

Define each target once and reuse its reference throughout the document. If two test files contain the same function name, disambiguate the references with `--fileStem`, for example `[cap][test_whenUnauthorized_reverts--queueLimits]` and `[withdrawal][test_whenUnauthorized_reverts--queueWithdrawal]`. Each definition points to its own file and actual function declaration; the suffix is not part of the Solidity function name. Preserve existing visible labels when converting links.

All reference definitions belong in one final footer, below every table, heading, checklist and explanatory paragraph. Nothing except further definitions and blank lines may follow the first definition. Insert new cases and notes before the footer, moving definitions to the end when extending an older document.

Put reciprocal IDs immediately above each mapped test and seed driver:

    // Scenarios: LIMIT-P01.
    function test_givenLimit_whenBoundariesAreSeeded() public {
        // Setup and assertions independently prove the stated endpoints.
    }

A helper's comment does not replace the test's own comment. Link the actual test file even if legacy tests remain in a differently named directory. Convert existing inline table links to named references without changing scenario expectations or coverage claims. The helper verifies link style, named targets and reciprocal IDs, not behavior, fuzz reachability or semantic coverage.
