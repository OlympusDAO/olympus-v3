# BurnerLoansSeizerTask.removeAsset coverage plan

Source: [removeAsset](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L175). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-REMOVE-ASSET` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN-only; local enablement is independent; own policy activity is enforced before role/input validation. EnumerableSet uses swap-and-pop; nextAssetIndex and per-asset expiry and unhealthy cursors are separate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-A01 | Fuzz caller excluding every ADMIN holder, including BL-admin-only, HEART-only and zero | Any asset; own policy active | ROLES_RequireRole(ADMIN_ROLE) before membership validation | Unmapped |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-I01 | ADMIN_ROLE holder | Asset absent, including0 | AssetNotManaged(asset) | Unmapped |

## Successful execution

Fixed for this table: Accounting / events: AssetRemoved; unrelated cursor remains.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-P01 | Fuzz ADMIN holder | Remove sole managed asset with nonzero borrower cursor; enabled/disabled/re-enabled seeds | Empty set, nextAssetIndex0, selected cursor deleted; exact AssetRemoved(asset); principal/collateral unchanged | Unmapped |

Co-located API assertions: `isAssetManaged`, `getAssets`, `expiredAssetCursor`, `unhealthyAssetCursor`, `nextAssetIndex`. These must be asserted independently of the action return value.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-P02 | Fuzz ADMIN_ROLE holder | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no body/token/module calls or committed logs | Unmapped; required own-policy admission |

## Test organization

[removeAsset.t.sol](./removeAsset.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Swap-and-pop and iterator branches

Local active=true, initialized ROLES. Seed first/middle/last removal in a three-asset set; verify getAssets() order, membership, exact event and all unaffected cursors independently. This function makes no Lens/Seize/Core readiness or pricing calls.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-REMOVE-ASSET-P03 | Fuzz ADMIN holder | Assets remain; saved nextAssetIndex < new count | Remove via swap-and-pop, retain next index, delete only removed asset cursor | Unmapped |
| BLSEIZ-REMOVE-ASSET-P04 | Fuzz ADMIN holder | Assets remain; saved nextAssetIndex >= new count | Store oldNext % newCount; include boundary oldNext=newCount and removal of pending asset | Unmapped |
| BLSEIZ-REMOVE-ASSET-P05 | Fuzz ADMIN holder | Enabled/disabled/re-enabled states; dependency calls all configured to fail | Removal still succeeds with exact set/cursor/event changes; no dependency calls | Unmapped |
| BLSEIZ-REMOVE-ASSET-P06 | Fuzz ADMIN holder | Remove then attempt removal again | First succeeds; second AssetNotManaged(asset), with no further changes/logs | Unmapped |
| BLSEIZ-REMOVE-ASSET-P07 | ADMIN | Independent expiry2/unhealthy8 after real task visits | Removing the asset clears both offsets | Covered: [test][test_givenUnequalCursors_whenAssetRemoved_thenBothCursorsAreCleared] |

[test_givenUnequalCursors_whenAssetRemoved_thenBothCursorsAreCleared]: execute.t.sol#L1088
