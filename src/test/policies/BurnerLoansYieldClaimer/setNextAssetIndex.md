# BurnerLoansYieldClaimer.setNextAssetIndex coverage plan

Scope: manual cursor selection and `nextAssetIndex` getter; automatic progress belongs to
[execute](./execute.md).

## Domains and assertions

`admin` and `burner_loans_admin` are independently permitted. Local disablement, task Kernel
membership, and Burner Loans Kernel membership do not gate this recovery surface. Zero is always
valid without reading the registry, including when the registry is empty or unavailable; every
nonzero index reads the live count and must be below it. Authorization precedes any count lookup. A
same nonzero value is revalidated against the live count before returning without an event.

Unchanged means gas configuration, cursor, target claim state, and lifecycle state retain their
pre-call values; no event is committed.

| ID | Caller | Task Kernel/local state | Asset count | Current cursor | Input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-A01 | Any caller outside both permitted classes, fuzz | Fuzz active/inactive and enabled/disabled | Readable or reverting | Any | Fuzz `uint256` | `NotAuthorised()` before count lookup | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsCursor_reverts] |
| CUR-I01 | Each permitted class | Fuzz active/inactive and enabled/disabled | 0 or positive | Any valid | Fuzz count..max, excluding zero; seed 1, count, count+1, max where applicable | `BurnerLoansYieldClaimer_InvalidAssetIndex(index, count)` | Cursor unchanged | Covered: [range][test_whenCursorIsOutOfRange_reverts], [boundaries][test_whenCursorBoundaryIsInvalid_reverts] |
| CUR-P01 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz 2..8 | Different valid index | Fuzz 0..count-1; seed 0, 1, count-1 | Success | Exact cursor stored; one exact `NextAssetIndexSet` event | Covered: [nonzero range][test_whenChangedCursorIsValid_storesExactInput], [zero reset][test_whenCursorResetToZero_storesExactInput] |
| CUR-P02 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz 0..8 | Same valid index | Current cursor | Success | No storage change or event | Covered: [test][test_whenCurrentCursorProvided_isNoOp] |
| CUR-P03 | Each permitted class | Fuzz active/inactive and enabled/disabled | 0 | 0 | 0 | Success | Cursor remains zero; no event | Covered: [test][test_whenCurrentCursorProvided_isNoOp] |
| CUR-P04 | Admin | Active/enabled | Multiple | 0 | Valid nonzero index | Success followed by Heart execution | Next beat starts at the selected asset | Covered: [test][test_givenRegisteredAssets_whenCursorSelected_nextBeatStartsThere] |
| CUR-P05 | Each permitted class | Any | Reverting count getter | Nonzero | 0 | Success without count lookup | Cursor resets; one exact event | Covered: [test][test_whenRegistryCountReverts_zeroStillResetsCursor] |

[test_whenUnauthorizedCallerSetsCursor_reverts]: ./setNextAssetIndex.t.sol#L14
[test_whenCursorIsOutOfRange_reverts]: ./setNextAssetIndex.t.sol#L33
[test_whenChangedCursorIsValid_storesExactInput]: ./setNextAssetIndex.t.sol#L100
[test_whenCursorResetToZero_storesExactInput]: ./setNextAssetIndex.t.sol#L126
[test_whenCurrentCursorProvided_isNoOp]: ./setNextAssetIndex.t.sol#L163
[test_givenRegisteredAssets_whenCursorSelected_nextBeatStartsThere]: ./setNextAssetIndex.t.sol#L191
[test_whenRegistryCountReverts_zeroStillResetsCursor]: ./setNextAssetIndex.t.sol#L144
[test_whenCursorBoundaryIsInvalid_reverts]: ./setNextAssetIndex.t.sol#L68
