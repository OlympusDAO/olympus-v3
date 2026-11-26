# setNextAssetIndex scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: RDTask cursor selection and nextAssetIndex getter; traversal normalization after active-set shrink belongs to [execute](./execute.md).

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorTask; own inactivity uses `RevenueDistributorTask_PolicyNotActive(Task)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin or Revenue Distributor Admin, separately; local task disablement and RD lifecycle do not gate this setter. Own RDTask inactivity rejects before reading RD asset count. Input is uint256; asset count is the live Active count. Zero is always valid, including count=0.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. A changed valid cursor is stored and emits one NextAssetIndexSet(index), with no payout or route changes. A valid same-value nonzero cursor is revalidated against the live asset count. Zero resets without reading the registry; an unchanged zero cursor does not write or emit. Failed setter preserves the previous cursor.

## Authorization

| ID | Caller | Local active | Local enabled | Active asset count | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-A01 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | true | true | Fuzz zero/positive | Fuzz valid/invalid | NotAuthorised() before count lookup | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsCursor_reverts], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-A02 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | true | false | Fuzz zero/positive | Fuzz valid/invalid | NotAuthorised() before count lookup | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsCursor_reverts], [test][test_givenCursorAndRoleBoundarySeeds] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Distributor active | Distributor enabled | Active asset count | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-P02 | Fuzz permitted role caller | true | false | true | true | Readable count | Valid for count | Success | Cursor change only; RD and task lifecycle unchanged | Covered: [test][test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P04 | Fuzz permitted role caller | true | false | true | false | Readable count | Valid for count | Success | Cursor change only; RD and task lifecycle unchanged | Covered: [test][test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P05 | Fuzz permitted role caller | true | false | false | true | Readable count | Valid for count | Success | Cursor change only; RD and task lifecycle unchanged | Covered: [test][test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P06 | Fuzz permitted role caller | true | false | false | false | Readable count | Valid for count | Success | Cursor change only; RD and task lifecycle unchanged | Covered: [test][test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-L01 | Fuzz permitted role caller | false | true | true | true | Readable positive count | Valid changed cursor | RevenueDistributorTask_PolicyNotActive(Task) | Cursor/configuration/balances unchanged; no RD count query or setter event | Covered: [test][test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts], [test][test_givenCursorAndRoleBoundarySeeds] |

## Invalid inputs

| ID | Caller | Local active | Local enabled | Active asset count | Current cursor | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-I01 | Fuzz permitted role caller | true | true | Fuzz zero/positive | Nonzero valid where possible | If count=0, fuzz 1..MAX; otherwise fuzz count..MAX; seed 1,count,count+1,MAX where applicable | RevenueDistributorTask_InvalidAssetIndex(index, count) | Retain prior cursor | Covered: [test][test_whenCursorIsOutOfRange_reverts], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-I02 | Fuzz permitted role caller | true | false | Fuzz zero/positive | Nonzero valid where possible | If count=0, fuzz 1..MAX; otherwise fuzz count..MAX; seed 1,count,count+1,MAX where applicable | RevenueDistributorTask_InvalidAssetIndex(index, count) | Retain prior cursor | Covered: [test][test_whenCursorIsOutOfRange_reverts], [test][test_givenCursorAndRoleBoundarySeeds] |

## Cursor inputs and bounds

| ID | Caller | Local enabled | Active asset count | Current cursor | `index_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-P01 | Fuzz permitted role caller | true | Fuzz multiple | Different from input | Fuzz 0..count-1 excluding current; seed 0,1,count-1 | Success | Store requested index and emit exact event; subsequent beat starts at the selected asset | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P07 | Fuzz permitted role caller | false | Fuzz multiple | Different from input | Fuzz 0..count-1 excluding current; seed 0,1,count-1 | Success | Store requested index and emit exact event; subsequent beat starts at the selected asset | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P03 | Fuzz permitted role caller | true | Fuzz 0,1,multiple | Same as input and valid for live count | Current cursor | Success | For nonzero input, live count is queried; zero skips lookup; no storage change/event | Covered: [test][test_whenCurrentCursorProvided_isNoOp], [test][test_givenCursorAndRoleBoundarySeeds] |
| CUR-P08 | Fuzz permitted role caller | false | Fuzz 0,1,multiple | Same as input and valid for live count | Current cursor | Success | For nonzero input, live count is queried; zero skips lookup; no storage change/event | Covered: [test][test_whenCurrentCursorProvided_isNoOp], [test][test_givenCursorAndRoleBoundarySeeds] |

## Registry-independent reset

| ID | Caller | Local active | Local enabled | Registry | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-P09 | Admin | true | true | Count getter reverts | 0 from nonzero cursor | Success; no registry probe | Cursor reset; exact event | Covered: [test][test_givenUnavailableRegistry_whenCursorReset_succeeds] |
| CUR-P10 | Admin | true | true | Count getter reverts | 0 from zero cursor | Success; no registry probe | No state change or event | Covered: [test][test_givenUnavailableRegistry_whenZeroCursorSetAgain_succeeds] |

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CUR-L02 | Any address, fuzz, without authorization exclusions | false | false | Task locally disabled, then Kernel-deactivated; Fuzz full `uint256` input type without bounds/exclusions | `RevenueDistributorTask_PolicyNotActive(task)` before local enablement (where required), caller and input checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst] |

[test_whenUnauthorizedCallerSetsCursor_reverts]: ./setNextAssetIndex.t.sol#L16
[test_givenTaskDisabled_whenPermittedCallerSetsCursor_ignoresDistributorLifecycle]: ./setNextAssetIndex.t.sol#L77
[test_givenTaskInactive_whenPermittedCallerSetsCursor_reverts]: ./setNextAssetIndex.t.sol#L49
[test_whenCursorIsOutOfRange_reverts]: ./setNextAssetIndex.t.sol#L95
[test_whenChangedCursorIsValid_storesExactInput]: ./setNextAssetIndex.t.sol#L138
[test_whenCurrentCursorProvided_isNoOp]: ./setNextAssetIndex.t.sol#L166
[test_givenActiveAssets_whenCursorSelected_nextBeatStartsThere]: ./setNextAssetIndex.t.sol#L202
[test_givenUnavailableRegistry_whenCursorReset_succeeds]: ./setNextAssetIndex.t.sol#L237
[test_givenUnavailableRegistry_whenZeroCursorSetAgain_succeeds]: ./setNextAssetIndex.t.sol#L254
[test_givenCursorAndRoleBoundarySeeds]: ./setNextAssetIndex.t.sol#L268
[test_givenInactiveAndDisabled_whenAnyCallerSetsValue_revertsActivityFirst]: ./setNextAssetIndex.t.sol#L851
