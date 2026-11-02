# BurnerLoansSeizerTask.setNextAssetIndex coverage plan

Source: [setNextAssetIndex](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L204).

Scenario scope: `BLSEIZ-ASSET-INDEX`. Recovery controls follow the existing scan/gas configuration authority: ADMIN_ROLE alone, BURNER_LOANS_ADMIN_ROLE alone, or both. Exclude every holder of either role from unauthorized fuzzing. Require own Kernel activity before authorization/input validation, including for unchanged values. Enabled, disabled and re-enabled states permit recovery.

The index addresses the Task's managed-asset set, in `getAssets()` order. Zero is always a valid reset, including an empty set. Nonzero indices must be less than the current managed count. No downstream calls are needed. Same values produce no writes/events. Borrower cursors, registry, scan/gas settings, lifecycle, positions and balances remain unchanged. This follows RevenueDistributorTask's cursor selection and reset behavior, using the SeizerTask's existing admission order.

| ID | Caller | Local active | Local enabled/history | Input | Expected result and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ASSET-INDEX-A01 | Fuzz caller with neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE | true | Enabled | Fuzz index0..MAX256 | NotAuthorised before range validation; unchanged | Covered: [test][test_whenCallerHasNeitherRole_reverts] |
| BLSEIZ-ASSET-INDEX-P01 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | true | Enabled, disabled or re-enabled; seed each | Two assets; changed index0 or1 | Exact getter and NextAssetIndexSet(index); other state unchanged | Covered: [enabled][test_givenEnabled_whenPermittedCallerChangesAssetIndex], [enabled seeds][test_givenEnabled_whenRoleAndIndexBoundariesSeeded], [disabled][test_givenDisabled_whenPermittedCallerChangesAssetIndex], [disabled seeds][test_givenDisabled_whenRoleAndIndexBoundariesSeeded], [re-enabled][test_givenReEnabled_whenPermittedCallerChangesAssetIndex], [re-enabled seeds][test_givenReEnabled_whenRoleAndIndexBoundariesSeeded] |
| BLSEIZ-ASSET-INDEX-P02 | ADMIN_ROLE | true | Enabled | Empty managed set; index0 | Successful event-free no-op | Covered: [test][test_givenEmptyRegistry_whenReset_thenEventFreeNoOp] |
| BLSEIZ-ASSET-INDEX-I01 | ADMIN_ROLE | true | Enabled | Two assets; fuzz index2..MAX256; seed2,MAX256 | InvalidAssetIndex(index,2); unchanged | Covered: [test][test_whenIndexOutsideManagedSet_reverts], [test][test_whenInvalidIndexBoundariesSeeded_reverts] |
| BLSEIZ-ASSET-INDEX-I02 | ADMIN_ROLE | true | Enabled | Empty set; fuzz index1..MAX256; seed1,MAX256 | InvalidAssetIndex(index,0); unchanged | Covered: [test][test_givenEmptyRegistry_whenNonzeroIndexSet_reverts], [test][test_whenInvalidIndexBoundariesSeeded_reverts] |
| BLSEIZ-ASSET-INDEX-I03 | ADMIN_ROLE | true | Enabled | Single asset; index1 | InvalidAssetIndex(1,1); unchanged | Covered: [test][test_givenSingleAsset_whenIndexEqualsCount_reverts] |
| BLSEIZ-ASSET-INDEX-P03 | ADMIN_ROLE | true | Enabled | Current index1; proposed1 | Event-free no-op after validation | Covered: [test][test_whenIndexUnchanged_thenEventFreeNoOp] |
| BLSEIZ-ASSET-INDEX-P04 | ADMIN_ROLE | true | Enabled | Current index1; downstream reads fail; proposed0 | Reset to zero with exact event and no downstream calls | Covered: [test][test_givenDownstreamUnavailable_whenReset_thenNoDownstreamReads] |
| BLSEIZ-ASSET-INDEX-L01 | ADMIN_ROLE | false then restored | Enabled/disabled independently | Valid index, including reset0 | Own PolicyNotActive before body/no-op; successful retry after activation | Covered: [enabled][test_givenInactiveEnabledTask_whenAssetIndexSet_reverts], [disabled][test_givenInactiveDisabledTask_whenAssetIndexSet_reverts], [seeds][test_whenInactiveLifecycleAndIndexBoundariesSeeded_reverts] |
| BLSEIZ-ASSET-INDEX-P05 | ADMIN_ROLE then HEART_ROLE | true | Enabled | Select second asset, then execute | Second asset scanned; traversal wraps to first | Covered: [test][test_whenSecondAssetSelected_thenNextExecutionScansIt] |
| BLSEIZ-ASSET-INDEX-P06 | Authorized handler | true | Arbitrary pause/re-enable history | Arbitrary valid cursor recovery between beats | Registry bounds, next-beat rotation and authoritative accounting remain consistent | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent] |

- [x] Write named tests, then implement the recovery setter.
- [x] Run focused tests, invariant, formatting/lint and reciprocal mapping checks.

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenDownstreamUnavailable_whenReset_thenNoDownstreamReads]: ./setNextAssetIndex.t.sol#L174
[test_givenEmptyRegistry_whenNonzeroIndexSet_reverts]: ./setNextAssetIndex.t.sol#L116
[test_givenEmptyRegistry_whenReset_thenEventFreeNoOp]: ./setNextAssetIndex.t.sol#L155
[test_givenSingleAsset_whenIndexEqualsCount_reverts]: ./setNextAssetIndex.t.sol#L142
[test_whenCallerHasNeitherRole_reverts]: ./setNextAssetIndex.t.sol#L90
[test_whenIndexOutsideManagedSet_reverts]: ./setNextAssetIndex.t.sol#L102
[test_whenIndexUnchanged_thenEventFreeNoOp]: ./setNextAssetIndex.t.sol#L165
[test_whenInvalidIndexBoundariesSeeded_reverts]: ./setNextAssetIndex.t.sol#L132
[test_whenSecondAssetSelected_thenNextExecutionScansIt]: ./setNextAssetIndex.t.sol#L220

[test_givenEnabled_whenPermittedCallerChangesAssetIndex]: ./setNextAssetIndex.t.sol#L33
[test_givenEnabled_whenRoleAndIndexBoundariesSeeded]: ./setNextAssetIndex.t.sol#L42
[test_givenDisabled_whenPermittedCallerChangesAssetIndex]: ./setNextAssetIndex.t.sol#L52
[test_givenDisabled_whenRoleAndIndexBoundariesSeeded]: ./setNextAssetIndex.t.sol#L61
[test_givenReEnabled_whenPermittedCallerChangesAssetIndex]: ./setNextAssetIndex.t.sol#L71
[test_givenReEnabled_whenRoleAndIndexBoundariesSeeded]: ./setNextAssetIndex.t.sol#L80

[test_givenInactiveEnabledTask_whenAssetIndexSet_reverts]: ./setNextAssetIndex.t.sol#L197
[test_givenInactiveDisabledTask_whenAssetIndexSet_reverts]: ./setNextAssetIndex.t.sol#L202
[test_whenInactiveLifecycleAndIndexBoundariesSeeded_reverts]: ./setNextAssetIndex.t.sol#L209
