# BurnerLoansSeizerTask.removeAsset coverage plan

Source: [removeAsset](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L163). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-REMOVE-ASSET` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN local enablement is independent; own policy activity is enforced before role/input validation. EnumerableSet uses swap-and-pop; nextAssetIndex and per-asset cursor are separate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-A01 | Non-ADMIN | Any asset | ROLES_RequireRole(ADMIN_ROLE) | Unmapped |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-I01 | ADMIN_ROLE holder | Asset absent, including0 | AssetNotManaged(asset) | Unmapped |

## Successful execution

Fixed for this table: Accounting / events: AssetRemoved; unrelated cursor remains.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-P01 | ADMIN_ROLE holder | Remove first/middle/last of1/multiple; current asset/not current | Remove membership, delete selected cursor; normalize nextAssetIndex if beyond remaining, zero when empty | Unmapped |

Co-located API assertions: `isAssetManaged`, `getAssets`, `assetCursor`, `nextAssetIndex`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-P02 | Fuzz ADMIN_ROLE holder | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no body/token/module calls or committed logs | Unmapped; required own-policy admission |

## Test organization

[removeAsset.t.sol](./removeAsset.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.
