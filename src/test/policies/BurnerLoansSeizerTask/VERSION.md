# BurnerLoansSeizerTask.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L148). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Unmapped |

## Shared assertions

Assert both returned components directly: major=1 and minor=0. No dependency read, lifecycle change, event or token effect occurs.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.
