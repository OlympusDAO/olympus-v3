# setNextAssetIndex scenario plan

Scope: RDTask cursor selection and nextAssetIndex getter; traversal normalization after active-set shrink belongs to [execute](./execute.md).

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; local task disablement and RD lifecycle do not gate this setter. Own RDTask inactivity rejects before reading RD asset count. Input is uint256; asset count is the live Active count. Zero is always valid, including count=0.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid cursor is stored and emits one NextAssetIndexSet(index), with no payout or route changes. A valid same-value cursor is revalidated against the live asset count, then returns without a storage write or event. Failed setter preserves the previous cursor.

## Authorization

| ID | Caller | Task Kernel | Task local | Active asset count | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-A01 | Unauthorized caller, fuzz | Active | Fuzz enabled/disabled | Fuzz zero/positive | Fuzz valid/invalid | NotAuthorised() before count lookup | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsCursor_reverts] |

## Lifecycle

| ID | Caller | Task Kernel | Task local | RD Kernel | RD local | Active asset count | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-P02 | Admin; Revenue Distributor Admin separately | Active | Disabled | Fuzz active/inactive | Fuzz enabled/disabled | Readable count | Valid for count | Success | Cursor change only; RD and task lifecycle unchanged | Covered: [test][test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle] |
| CUR-L01 | Admin; Revenue Distributor Admin separately, roles retained | Inactive | Enabled | Active | Enabled | Readable positive count | Valid changed cursor | RevenueDistributorTask_PolicyInactive() | Cursor/configuration/balances unchanged; no RD count query or setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts] |

## Invalid inputs

| ID | Caller | Task state | Active asset count | Current cursor | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-I01 | Each permitted caller | Active; fuzz enabled/disabled | Fuzz zero/positive | Nonzero valid where possible | If count=0, fuzz 1..MAX; otherwise fuzz count..MAX; seed 1,count,count+1,MAX where applicable | RevenueDistributorTask_InvalidAssetIndex(index, count) | Retain prior cursor | Covered: [test][test_whenCursorIsOutOfRange_reverts] |

## Cursor inputs and bounds

| ID | Caller | Task local | Active asset count | Current cursor | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-P01 | Each permitted caller | Fuzz enabled/disabled | Fuzz multiple | Different from input | Fuzz 0..count-1 excluding current; seed 0,1,count-1 | Success | Store requested index and emit exact event; subsequent beat starts at the selected asset | Covered: [range][test_whenChangedCursorIsValid_storesExactInput], [execution][test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere] |
| CUR-P03 | Each permitted caller | Fuzz enabled/disabled | Fuzz 0,1,multiple | Same as input and valid for live count | Current cursor | Success | Live count is queried; no storage change and no event | Covered: [test][test_whenCurrentCursorProvided_isNoOp] |

[test_whenUnauthorizedCallerSetsCursor_reverts]: ./setNextAssetIndex.t.sol#L14
[test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle]: ./setNextAssetIndex.t.sol#L52
[test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts]: ./setNextAssetIndex.t.sol#L34
[test_whenCursorIsOutOfRange_reverts]: ./setNextAssetIndex.t.sol#L67
[test_whenChangedCursorIsValid_storesExactInput]: ./setNextAssetIndex.t.sol#L99
[test_whenCurrentCursorProvided_isNoOp]: ./setNextAssetIndex.t.sol#L120
[test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere]: ./setNextAssetIndex.t.sol#L147
