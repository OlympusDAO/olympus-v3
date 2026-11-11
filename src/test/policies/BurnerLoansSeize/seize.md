# BurnerLoansSeize.seize coverage plan

Source: [seize](../../../policies/burnerloans/BurnerLoansSeize.sol#L48). Coverage mappings below identify the implemented Foundry proofs.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLLIQ-SEIZE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansSeize; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeize)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansSeize)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Permissionless keeper; list must be nonempty and contain unique nonzero addresses. No protocol batch ceiling is imposed; callers choose a size that fits their gas budget. Defaults: registered asset, Inventory enabled, DM solvent. Each position has positive principal and is expired or has H<1e18. Output mode changes keeper reward units. Here expiry denotes the timestamp stored in FLOAN.position.maturity; the existing field name is unchanged.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Both follow the same function-specific caller/input validation and quote outcome; no writes | Covered: [test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult][test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult], [test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged][test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged], [test_givenActionReEnabled_whenSeized_thenDefaultSucceeds][test_givenActionReEnabled_whenSeized_thenDefaultSucceeds], [test_givenActionReactivated_whenSeized_thenDefaultSucceeds][test_givenActionReactivated_whenSeized_thenDefaultSucceeds] |
| BLLIQ-SEIZE-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenSeized_thenDependencyIdentified][test_givenCoreUnavailable_whenSeized_thenDependencyIdentified], [test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified][test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenSeized_thenDependencyIdentified][test_givenCoreUnavailable_whenSeized_thenDependencyIdentified], [test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified][test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenSeized_thenDependencyIdentified][test_givenCoreUnavailable_whenSeized_thenDependencyIdentified], [test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified][test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenSeized_thenLocalPauseWins][test_givenDisabledAction_whenSeized_thenLocalPauseWins], [test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins][test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins] |
| BLLIQ-SEIZE-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenSeized_thenLocalPauseWins][test_givenDisabledAction_whenSeized_thenLocalPauseWins], [test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins][test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins] |
| BLLIQ-SEIZE-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenSeized_thenLocalPauseWins][test_givenDisabledAction_whenSeized_thenLocalPauseWins], [test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins][test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins] |
| BLLIQ-SEIZE-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenSeized_thenLocalPauseWins][test_givenDisabledAction_whenSeized_thenLocalPauseWins], [test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins][test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins] |
| BLLIQ-SEIZE-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |
| BLLIQ-SEIZE-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansSeize); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified][test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified], [test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified][test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified] |

## Keeper authorization

EOAs and contracts are equally admitted without Kernel/status getters, settlement roles or operator grants. Public caller metadata does not establish authority. Funding and token rules remain separate where applicable.

Action and Core are active/enabled. No borrower grant is required. Fuzz the actual caller over EOAs and contracts, including borrower, unrelated operator and protocol-role holders. Borrower list validation is independent.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-A01 | Fuzz all keepers | Fuzz any actual caller; no borrower grant | `Caller admitted by the public function` | Seizure uses actual keeper identity; no repayment collection | Permissionless view caller; explicit actor selects the reward identity; quote without writes | Covered: [test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult][test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult], [test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged][test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged] |

## Core settlement authorization

Operational action and Core; seizure is permissionless and the actual caller is the keeper. Core requires only the action's `BL_LIQUIDATION_POLICY_ROLE`; no borrower grant is required.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-A02 | Fuzz keeper | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_LIQUIDATION_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_LIQUIDATION_POLICY_ROLE) | Covered: [test_givenSettlementRoleRevoked_whenSeized_reverts][test_givenSettlementRoleRevoked_whenSeized_reverts] |
| BLLIQ-SEIZE-A03 | Fuzz all keepers | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return (token,reward,treasuryAmount) | Seize each eligible position once; settle default debt and allocate output to the actual keeper and Treasury; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenReportedKernelMismatch_whenSeized_thenGetterIsNotRead][test_givenReportedKernelMismatch_whenSeized_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenSeized_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenSeized_thenGetterIsNotRead], [test_givenReportedKernelMismatch_whenAnyKeeperSeizes][test_givenReportedKernelMismatch_whenAnyKeeperSeizes], [test_givenActionKernelGetterReverts_whenAnyKeeperSeizes][test_givenActionKernelGetterReverts_whenAnyKeeperSeizes] |

## Dependency lifecycle

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-D04 | Fuzz keeper | Valid batch length; Inventory disabled | `PolicyDependency_NotActive(Inventory)` | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenInventoryUnavailable_whenSeized_reverts][test_givenInventoryUnavailable_whenSeized_reverts], [test_givenEachUnavailableInventoryState_whenSeized_thenDependencyIdentified][test_givenEachUnavailableInventoryState_whenSeized_thenDependencyIdentified] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-I01 | Fuzz keeper | Batch length=0 | `BurnerLoans_InvalidBatch()` | Same BurnerLoans_InvalidBatch() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenBatchEmpty_reverts][test_whenBatchEmpty_reverts] |
| BLLIQ-SEIZE-I02 | Fuzz keeper | Batch length fuzz51..256, containing zero addresses; seed51 | `BurnerLoans_ZeroAddress()` | Same zero-address error after removing the former length ceiling; assert no writes | Covered: [test_whenLargeBatchContainsZeroBorrower_reverts][test_whenLargeBatchContainsZeroBorrower_reverts], [test_whenBatchFiftyOneContainsZeroBorrower_reverts][test_whenBatchFiftyOneContainsZeroBorrower_reverts] |
| BLLIQ-SEIZE-I03 | Fuzz keeper | One zero borrower; seed first/middle/last position | `BurnerLoans_ZeroAddress()` | Same BurnerLoans_ZeroAddress() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenBorrowerZero_reverts][test_whenBorrowerZero_reverts], [test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts][test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts], [test_whenZeroBorrowerAtFirstMiddleAndLast_reverts][test_whenZeroBorrowerAtFirstMiddleAndLast_reverts] |
| BLLIQ-SEIZE-I04 | Fuzz keeper | Snapshot invalid; all loans expired | `BurnerLoans_InvalidPrice()` | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired][test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired] |

## Successful execution

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-P01 | Fuzz keeper | Duplicate borrower; adjacent pair | `BurnerLoans_DuplicateBorrower(borrower)` | Same BurnerLoans_DuplicateBorrower(borrower) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAdjacentDuplicate_reverts][test_whenAdjacentDuplicate_reverts] |
| BLLIQ-SEIZE-P02 | Fuzz keeper | Duplicate borrower; nonadjacent pair | `BurnerLoans_DuplicateBorrower(borrower)` | Same BurnerLoans_DuplicateBorrower(borrower) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenNonAdjacentDuplicate_reverts][test_whenNonAdjacentDuplicate_reverts] |
| BLLIQ-SEIZE-P03 | Fuzz keeper | One position has no debt; all identities valid | `BurnerLoansCore_NoDebt()` | Revert BurnerLoansCore_NoDebt(); reject the entire batch without returning partial totals | Covered: [test_whenBorrowerHasNoDebt_reverts][test_whenBorrowerHasNoDebt_reverts] |
| BLLIQ-SEIZE-P04 | Fuzz keeper | Unexpired position; health H=1e18 | `BurnerLoans_PositionNotSeizable(borrower)` | Revert BurnerLoans_PositionNotSeizable(borrower); reject the entire batch | Covered: [test_givenHealthyUnexpiredDebt_whenSeized_reverts][test_givenHealthyUnexpiredDebt_whenSeized_reverts], [test_whenHealthAtAndAboveThreshold_reverts][test_whenHealthAtAndAboveThreshold_reverts], [test_givenHealthyDebt_whenOneSecondBeforeMaturity_reverts][test_givenHealthyDebt_whenOneSecondBeforeMaturity_reverts] |
| BLLIQ-SEIZE-P05 | Fuzz keeper | Unexpired position; H>1e18 | `BurnerLoans_PositionNotSeizable(borrower)` | Revert BurnerLoans_PositionNotSeizable(borrower); reject the entire batch | Covered: [test_givenHealthyUnexpiredDebt_whenSeized_reverts][test_givenHealthyUnexpiredDebt_whenSeized_reverts], [test_whenHealthAtAndAboveThreshold_reverts][test_whenHealthAtAndAboveThreshold_reverts] |
| BLLIQ-SEIZE-P06 | Fuzz keeper | All loans eligible; payout insolvent | `BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed)` | Preview and action reject BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed); preview checks solvency before snapshot/borrower identity, so assert each path’s actual precedence | Covered: [test_givenInsolventCustody_whenSeized_reverts][test_givenInsolventCustody_whenSeized_reverts] |

## Eligible batches and fund flows

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-P07 | Fuzz keeper | Unexpired position; H<1e18 | `Success` | Debt and collateral defaulted atomically | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput][test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput], [test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes][test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes], [test_whenHealthOneUnitBelowThreshold_thenSeizes][test_whenHealthOneUnitBelowThreshold_thenSeizes], [test_whenHealthZero_thenSeizes][test_whenHealthZero_thenSeizes] |
| BLLIQ-SEIZE-P08 | Fuzz keeper | now=expiry; H>=1e18 | `Success` | Expiry equality is seizable | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExactlyExpiredHealthyDebt_whenSeized_thenAllowed][test_givenExactlyExpiredHealthyDebt_whenSeized_thenAllowed] |
| BLLIQ-SEIZE-P09 | Fuzz keeper | now>expiry; H>=1e18 | `Success` | Health need not be below threshold | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExpiredHealthyDebt_whenSeized_thenAllowed][test_givenExpiredHealthyDebt_whenSeized_thenAllowed], [test_givenExpiredDebt_whenTimeIsMaximum_thenSeizes][test_givenExpiredDebt_whenTimeIsMaximum_thenSeizes], [test_givenExpiredDebt_whenTimeJustAfterMaturity_thenSeizes][test_givenExpiredDebt_whenTimeJustAfterMaturity_thenSeizes] |
| BLLIQ-SEIZE-P10 | Fuzz keeper | Batch length=1 | `Success` | Per-position Seized then aggregate SeizureBatchSettled; proceeds→Custody | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [invariant_modelMatchesEveryAuthoritativeLedger][invariant_modelMatchesEveryAuthoritativeLedger], [test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput][test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput] |
| BLLIQ-SEIZE-P11 | Fuzz keeper | Batch length fuzz1..MAX8; seed50,51,255; every position eligible | `Success` | Bounded complete batch; no partial execution | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_whenValidBatchSeized_thenEveryPositionSettledOnce][test_whenValidBatchSeized_thenEveryPositionSettledOnce], [test_whenMaxUint8BorrowersSeized_thenEveryPositionSettledOnce][test_whenMaxUint8BorrowersSeized_thenEveryPositionSettledOnce], [test_whenFiftyBorrowersSeized_thenEveryPositionSettledOnce][test_whenFiftyBorrowersSeized_thenEveryPositionSettledOnce], [test_whenFiftyOneBorrowersSeized_thenEveryPositionSettledOnce][test_whenFiftyOneBorrowersSeized_thenEveryPositionSettledOnce] |
| BLLIQ-SEIZE-P12 | Fuzz keeper | Ordinary keeper without HEART/BURNER_LOANS_SEIZER_ROLE | `Keeper reward per current Risk` | Reward+Treasury remainder=actual redemption output | Set preview actor to actual keeper independently of preview caller; compare role-aware reward and Treasury remainder using independently expected output | Covered: [test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput][test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput] |
| BLLIQ-SEIZE-P13 | Fuzz keeper | HEART_ROLE keeper | `Keeper reward=0` | All proceeds allocated to Treasury | Preview actor has HEART role; reward=0 regardless of preview caller; action keeper has same role | Covered: [test_givenProtocolKeeper_whenSeized_thenNoReward][test_givenProtocolKeeper_whenSeized_thenNoReward], [test_givenEachProtocolRole_whenSeized_thenNoReward][test_givenEachProtocolRole_whenSeized_thenNoReward] |
| BLLIQ-SEIZE-P14 | Fuzz keeper | BURNER_LOANS_SEIZER_ROLE keeper without HEART_ROLE | `Keeper reward=0` | All proceeds allocated to Treasury | Preview actor has seizer role; reward=0 regardless of preview caller; action keeper has same role | Covered: [test_givenProtocolKeeper_whenSeized_thenNoReward][test_givenProtocolKeeper_whenSeized_thenNoReward], [test_givenEachProtocolRole_whenSeized_thenNoReward][test_givenEachProtocolRole_whenSeized_thenNoReward] |
| BLLIQ-SEIZE-P15 | Fuzz keeper | Keeper payout transfer fails; Treasury succeeds | `Seizure succeeds` | Only keeper obligation stays pending | Quote reward/remainder without delivery; cannot predict blacklisted keeper; action succeeds with only keeper payout pending | Covered: [test_givenKeeperPayoutFails_whenSeized_thenOnlyKeeperRemainsPending][test_givenKeeperPayoutFails_whenSeized_thenOnlyKeeperRemainsPending] |
| BLLIQ-SEIZE-P16 | Fuzz keeper | Treasury payout fails; keeper succeeds | `Seizure succeeds` | Only seized-collateral obligation stays pending | Quote reward/remainder without delivery; action succeeds with only Treasury payout pending | Covered: [test_givenTreasuryPayoutFails_whenSeized_thenOnlyTreasuryRemainsPending][test_givenTreasuryPayoutFails_whenSeized_thenOnlyTreasuryRemainsPending] |
| BLLIQ-SEIZE-P17 | Fuzz keeper | Both final payout transfers fail | `Seizure succeeds` | Both obligations retained; aggregate reserve equals their sum | Quote totals without delivery; action succeeds and retains both unpaid buckets | Covered: [test_givenBothPayoutsFail_whenSeized_thenBothRemainPending][test_givenBothPayoutsFail_whenSeized_thenBothRemainPending] |

## Fixed payout rounding and zero-output cases

Use a fixed ordinary keeper without HEART_ROLE or BURNER_LOANS_SEIZER_ROLE. All amounts below are raw units of the actual output token, including shares; one unit means the smallest representable amount, not necessarily 1e-18 of the underlying. Hard-code the expected integers. Do not fuzz these fixtures or calculate expectations by calling production math.

Action unit tests configure mock Risk with the exact reward below and assert that Core/Custody receive that allocation unchanged. For the same fixed examples in real Risk integration, use OHM decimals=9, underlying decimals=6, all snapshot prices/backing=1e18, principal=1 raw OHM unit and backingMultiplierBps=10000. Required backing rounds up to 1 raw underlying unit. Use expired positions, maxKeeperReward=1000 raw underlying units and an exact preview/redemption conversion. The share fixture must independently establish 100 underlying units redeeming to 1 share.

| ID | Caller | Output mode | Collateral credit / actual output | keeperRewardBps | Exact reward / Treasury remainder | Accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-N01 | Fixed ordinary keeper | Underlying | 99 / 99 | 100 | 0 / 99; the percentage reward is 0.99 of a raw unit and rounds down | Success; no keeper obligation or keeper payout; all 99 units allocated to Treasury; preview/action return reward=0 and remainder=99 | Covered: [test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward][test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward] |
| BLLIQ-SEIZE-N02 | Fixed ordinary keeper | Shares | 100 underlying / 1 share | 100 | 0 shares / 1 share; the 1-underlying-unit reward converts to 0.01 share and rounds down | Success; no keeper obligation or keeper payout; The complete share is allocated to Treasury; preview/action use share units | Covered: [test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury][test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury] |
| BLLIQ-SEIZE-N03 | Fixed ordinary keeper | Underlying | 2 / 2 | 9999 | 1 / 1; percentage-only Treasury remainder would be 0.0002 raw units before rounding/backing constraints | Success; reward rounds down and preserves the 1-unit backing requirement; Treasury is allocated the integer remainder 1, never an independently rounded zero; preview/action conserve both output units | Covered: [test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation][test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation] |
| BLLIQ-SEIZE-N04 | Fixed ordinary keeper | Shares | Positive collateral credit / 0 shares from documented vault rounding | 100 | 0 / 0 | Success; default and Inventory reconciliation commit once; no payout obligation or zero-value transfer; preview/action return zero reward and remainder | Covered: [test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout][test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout] |

Treasury allocation is actual integer output minus the already-rounded keeper reward. It is not separately rounded down. In the positive-principal, positive-backing examples above, a positive output leaves at least one output unit for Treasury; the zero-output example checks the valid zero-remainder path. Custody tests own delivery, deferral and zero-bucket bookkeeping.

## Settlement failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-T01 | Fuzz keeper | DM returns unexpected output token | `BurnerLoansCore_InvalidSettlement()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenUnexpectedRedemptionToken_whenSeized_thenDefaultRollsBack][test_givenUnexpectedRedemptionToken_whenSeized_thenDefaultRollsBack] |
| BLLIQ-SEIZE-T02 | Fuzz keeper | New Custody receipts smaller than returned amount; old surplus sufficient | `BurnerLoansCore_InvalidSettlement()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenOldCustodySurplus_whenNewReceiptShort_thenSurplusCannotMaskIt][test_givenOldCustodySurplus_whenNewReceiptShort_thenSurplusCannotMaskIt] |
| BLLIQ-SEIZE-T03 | Fuzz keeper | Risk reward exceeds actual redemption output | `BurnerLoansCore_InvalidSettlement()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenRiskRewardExceedsOutput_whenSeized_reverts][test_givenRiskRewardExceedsOutput_whenSeized_reverts] |
| BLLIQ-SEIZE-T04 | Fuzz keeper | Injected inconsistent FLOAN aggregate debt exceeds uint128; aggregate collateral remains uint256 | `SafeCastOverflowedUintDowncast(128,total)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenInjectedAggregateDebtOverflow_whenSeized_thenTypedFailureAndRollback][test_givenInjectedAggregateDebtOverflow_whenSeized_thenTypedFailureAndRollback] |
| BLLIQ-SEIZE-T05 | Fuzz keeper | Late Inventory default-accounting failure | `Exact injected Inventory error` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenLateInventoryFailure_whenSeized_thenAllAccountingRollsBack][test_givenLateInventoryFailure_whenSeized_thenAllAccountingRollsBack] |
| BLLIQ-SEIZE-T06 | Fuzz keeper | Custody rejects credit backing | `BurnerLoansCore_InvalidSettlement()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenCustodyCreditFailure_whenSeized_thenEverythingRollsBack][test_givenCustodyCreditFailure_whenSeized_thenEverythingRollsBack] |

## Stateful external-share custody

The modular campaign retains the removed legacy share invariant's multi-borrower scope. It uses three
borrowers, an 18-decimal asset and a separate 6-decimal share token. Deposits span 1..100,000 asset
units; oracle prices span $0.50..$2; time advances span 1 second..31 days. Yield, direct withdrawals, repayments, nonzero origination fees, permissionless and periodic seizure, Inventory supply/withdrawal, origination
pauses, withdrawal-mode changes and asynchronous-redemption drift are interleaved. Deterministic setup exercises partial and full repayment with share withdrawals between them,
then each remaining settlement path before fuzzing. Assertions and unexpected execution reverts fail
the campaign; empty balances or unavailable modeled inputs may skip an operation.

| ID | Caller | Sequence | Required properties | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-S01 | Ordinary keeper and protocol SeizerTask; three borrower identities | Arbitrary modeled actions and governance/capability changes within the domain above | Per-borrower collateral/principal, FLOAN aggregates/defaults, Inventory funding, DM liabilities/receipts/cap utilization and external share custody reconcile; custody stays solvent; share/underlying withdrawal, seizure and yield outputs conserve; failed mode changes are atomic; periphery retains no transient tokens | Covered: [invariant_shareCustodyAndPositionAccountingConserve][invariant_shareCustodyAndPositionAccountingConserve] |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee, health and reward responses used by this function. Assert exact method arguments and call counts, actual Core/FLOAN state and returned configured values; do not duplicate Risk arithmetic in action assertions. Debt-free or full-repayment price-free paths configure the mock to reject unexpected pricing calls. Risk’s suite independently proves math and rounding.

Current Risk applies to existing positions; role change changes reward. Core emits Seized and SeizureBatchSettled, not action. Liquidation.previewSeizeFor rejects an ineligible batch with the same validation error as seizure; compare equivalent snapshots/states and preserve validation order. A propagated collateral-token callback failure must roll back defaults and payout credits.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Carry forward zero-collateral positive-debt default, zero-share-output default with remaining vault dust subsequently claimable as yield, actual-output redemption fee preserving backing (2000 collateral→1800 output vs1875 required backing gives keeper0), ERC7575 externalshares at differentdecimals, seizure protocolrole reward0, and reopening reusable positionID after default.

| ID | Pre-state | Execution | Required proof | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-R01 | Historical zero-collateral positive-debt position; module and Inventory debt agree | Success without redemption | Principal defaults once; zero output and no payout obligation | Covered: [test_givenZeroCollateralDebt_whenSeized_thenDebtDefaultsWithoutRedemption][test_givenZeroCollateralDebt_whenSeized_thenDebtDefaultsWithoutRedemption] |
| BLLIQ-SEIZE-R02 | Solvent vault with yield; 2000e6 collateral redeems to 1800e6 after fee; backing requirement 1875e6 | Reward zero; Treasury receives 1800e6 | Independent backing calculation, actual output balances and default accounting | Covered: [test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking][test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking] |
| BLLIQ-SEIZE-R03 | ERC7575 external shares with 6 decimals; underlying has 18 decimals | Share output paid in external token | 2000e18 underlying becomes 2000e6 shares; reward 20e6, Treasury 1980e6; underlying remains in vault | Covered: [test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid][test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid] |
| BLLIQ-SEIZE-R04 | Borrower defaults and subsequently deposits/borrows again | Reuse canonical position ID | Fresh debt episode and custody; active index reinserted once; historical default retained | Covered: [test_givenDefaultedPosition_whenBorrowerReopens_thenPositionIdReused][test_givenDefaultedPosition_whenBorrowerReopens_thenPositionIdReused] |
| BLLIQ-SEIZE-R05 | Existing debt; asset originations disabled | Seizure still succeeds | Default accounting and actual output unchanged by origination pause | Covered: [test_givenOriginationsDisabled_whenSeized_thenDefaultStillSucceeds][test_givenOriginationsDisabled_whenSeized_thenDefaultStillSucceeds] |

## Real Risk integration

Use seizeIntegration.t.sol and seizeSharesIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Fix the borrower/keeper caller because authorization is covered in unit scenarios. Derive expected economics independently from prices, decimal scales and actual settlement state. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-P18 | Keeper | Valid real snapshot; compatible custody and funding; independent economic boundary seeds from this function’s numeric rows | Successful operation | Actual balances, collateral/debt, fee/reward and WAD health match an independent calculation; preview agrees only with unchanged prices/conversion | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward][test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward], [test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation][test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation], [test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking][test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking], [test_givenRealUnhealthyUnexpiredDebt_whenSeized_thenHealthAndBalancesMatch][test_givenRealUnhealthyUnexpiredDebt_whenSeized_thenHealthAndBalancesMatch], [test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury][test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury], [test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout][test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout], [test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid][test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid] |
| BLLIQ-SEIZE-P19 | Keeper | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired][test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired] |

## Transfer callbacks and reentrancy

Use direct underlying custody and two expired eligible positions. Arm the collateral token only after setup. During redemption of the outer position to Custody, the token calls seize for the second position, which still has debt and passes public eligibility checks, so the nested call reaches Core's guard. Propagate the callback failure; no additional callback routes are needed here. Custody's own tests cover outgoing payouts.

| ID | Caller | Collateral callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-C02 | Fixed ordinary keeper | Underlying transfer from DepositManager to Custody invokes nested seizure of the second eligible position | Nested `ReentrancyGuardReentrantCall()`; outer `ReentrantFeeToken.CallbackFailed()` | Both positions, aggregate debt/collateral, Inventory principal, token/receipt balances and payout obligations restored; no committed logs | Quote before arming the callback; preview performs no transfer and cannot predict token callback failure | Covered: [test_givenPropagatedCollateralCallback_whenSeized_thenMandatoryTransferRollsBack][test_givenPropagatedCollateralCallback_whenSeized_thenMandatoryTransferRollsBack] |

## Payout dependency readiness

Other admission checks pass. Payout is selected on Core; direct IEnabler state can drift after Core/action enablement.

| ID | Caller | Payout active | Payout enabled | Execution | Preview | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-D05 | Caller | true | false | PolicyDependency_NotActive(Payout) for seizure | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts][test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts], [test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified][test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-D06 | Caller | false | true | PolicyDependency_NotActive(Payout) for seizure | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts][test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts], [test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified][test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-D07 | Caller | false | false | PolicyDependency_NotActive(Payout) for seizure | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts][test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts], [test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified][test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified] |
| BLLIQ-SEIZE-D08 | Fuzz all callers | true | true; reports another Kernel | PolicyDependency_KernelMismatch(Payout, expected, reported) for seizure | Same error | No accounting/transfers | Covered: [test_givenPayoutReportsAnotherKernel_whenSeizedOrPreviewed_reverts][test_givenPayoutReportsAnotherKernel_whenSeizedOrPreviewed_reverts] |

## Custody exit availability

Action and Core are active/enabled. Permitted borrower for withdrawals; fuzz permissionless keeper for unavailable seizure custody. Other dependencies are ready.

| ID | Pre-state | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-D10 | DepositManager locally paused; eligible debt-bearing position | Both revert BurnerLoansCore_InvalidDepositManager(DM) | No default, reserve, custody or balance change | Covered: [test_givenDepositManagerPaused_whenSeizedOrPreviewed_reverts][test_givenDepositManagerPaused_whenSeizedOrPreviewed_reverts] |
| BLLIQ-SEIZE-D11 | Deposit period configured but disabled for new deposits | Both permit eligible seizure | Exact debt default and keeper/Treasury output conservation | Covered: [test_givenDepositPeriodDisabled_whenSeized_thenExitRemainsAvailable][test_givenDepositPeriodDisabled_whenSeized_thenExitRemainsAvailable] |

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-D12 | Fuzz keeper/viewer | DepositManager Kernel-inactive; otherwise seizable batch | PolicyDependency_NotActive(DepositManager) on preview and execution; custody/debt unchanged | Covered: [test_givenDepositManagerInactive_whenSeizedOrPreviewed_reverts][test_givenDepositManagerInactive_whenSeizedOrPreviewed_reverts] |

## Keeper destination admission

The caller remains permissionless; reward delivery requires a valid keeper destination only when
Risk returns a positive reward. Payout enforces final settlement admission, and previewSeizeFor
calls the selected Payout.validatePayoutRecipient(actor) to apply the same rule. Zero rewards do
not create a keeper obligation or call the destination validator.

| ID | Caller / actor | Reward | Preview | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-I05 | Zero, otherwise operational | 7 raw units; positive | BurnerLoansPayout_InvalidRecipient(0) | Same Payout error; full rollback of defaults, redemptions, Inventory principal, reserves and custody | Covered: [test_whenZeroAddressKeeperSeizes_reverts][test_whenZeroAddressKeeperSeizes_reverts] |
| BLLIQ-SEIZE-I06 | Selected Payout, otherwise operational | 7 raw units; positive | BurnerLoansPayout_InvalidRecipient(Payout) | Same Payout error; full rollback of defaults, redemptions, Inventory principal, reserves and custody | Covered: [test_whenPayoutKeeperSeizes_reverts][test_whenPayoutKeeperSeizes_reverts] |
| BLLIQ-SEIZE-P20 | Independently zero / selected Payout | 0 | Quote zero keeper reward and complete Treasury allocation | Seizure succeeds; Treasury receives all 2,000,000,000 raw output units; no keeper claim or pending reserve | Covered: [test_givenZeroReward_whenKeeperDestinationUnused][test_givenZeroReward_whenKeeperDestinationUnused] |

## Backing readiness for matured debt

Local action/Core and ordinary dependencies are active/enabled. A public keeper
and a HEART_ROLE keeper both require snapshot acquisition, even after maturity.
The Lens maturity predicate remains true independently of backing readiness.

| ID | Oracle active | Oracle enabled | Caller | Execution and preview | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-SEIZE-D13 | true | false | Public keeper / HEART_ROLE keeper, guarantee both | PolicyDependency_NotActive(oracle); debt, custody and payouts unchanged | Covered: [test][test_givenMaturedDebtAndBackingPaused_whenSeized_reverts] |

[invariant_modelMatchesEveryAuthoritativeLedger]: accounting.invariants.t.sol#L39
[invariant_shareCustodyAndPositionAccountingConserve]: seizeShares.invariant.t.sol#L203
[test_givenActionKernelGetterReverts_whenAnyKeeperSeizes]: seize.t.sol#L433
[test_givenActionKernelGetterReverts_whenSeized_thenGetterIsNotRead]: seize.t.sol#L407
[test_givenActionReEnabled_whenSeized_thenDefaultSucceeds]: seize.t.sol#L541
[test_givenActionReactivated_whenSeized_thenDefaultSucceeds]: seize.t.sol#L548
[test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired]: seizeIntegration.t.sol#L76
[test_givenBothPayoutsFail_whenSeized_thenBothRemainPending]: seizePayout.t.sol#L33
[test_givenCoreUnavailable_whenSeized_thenDependencyIdentified]: seize.t.sol#L478
[test_givenCustodyCreditFailure_whenSeized_thenEverythingRollsBack]: seizeSettlement.t.sol#L78
[test_givenDefaultedPosition_whenBorrowerReopens_thenPositionIdReused]: seizeIntegration.t.sol#L165
[test_givenDepositManagerInactive_whenSeizedOrPreviewed_reverts]: seize.t.sol#L28
[test_givenDepositManagerPaused_whenSeizedOrPreviewed_reverts]: seize.t.sol#L49
[test_givenDepositPeriodDisabled_whenSeized_thenExitRemainsAvailable]: seize.t.sol#L43
[test_givenDisabledActionAndEveryCoreState_whenSeized_thenLocalPauseWins]: seize.t.sol#L555
[test_givenDisabledAction_whenSeized_thenLocalPauseWins]: seize.t.sol#L467
[test_givenEachProtocolRole_whenSeized_thenNoReward]: seizeIntegration.t.sol#L107
[test_givenEachUnavailableInventoryState_whenSeized_thenDependencyIdentified]: seize.t.sol#L603
[test_givenEachUnavailablePayoutState_whenSeized_thenDependencyIdentified]: seize.t.sol#L531
[test_givenEveryUnavailableCoreState_whenSeized_thenDependencyIdentified]: seize.t.sol#L593
[test_givenExactlyExpiredHealthyDebt_whenSeized_thenAllowed]: seize.t.sol#L230
[test_givenExpiredDebt_whenTimeIsMaximum_thenSeizes]: seize.t.sol#L323
[test_givenExpiredDebt_whenTimeJustAfterMaturity_thenSeizes]: seize.t.sol#L330
[test_givenExpiredHealthyDebt_whenSeized_thenAllowed]: seize.t.sol#L241
[test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid]: seizeSharesIntegration.t.sol#L77
[test_givenHealthyDebt_whenOneSecondBeforeMaturity_reverts]: seize.t.sol#L335
[test_givenHealthyUnexpiredDebt_whenSeized_reverts]: seize.t.sol#L209
[test_givenInactiveActionAndEveryOtherState_whenSeized_thenOwnPolicyIdentified]: seize.t.sol#L570
[test_givenInactiveAction_whenSeized_thenOwnPolicyIdentified]: seize.t.sol#L448
[test_givenInjectedAggregateDebtOverflow_whenSeized_thenTypedFailureAndRollback]: seizeSettlement.t.sol#L90
[test_givenInsolventCustody_whenSeized_reverts]: seize.t.sol#L253
[test_givenInventoryUnavailable_whenSeized_reverts]: seize.t.sol#L368
[test_givenKeeperPayoutFails_whenSeized_thenOnlyKeeperRemainsPending]: seizePayout.t.sol#L21
[test_givenLateInventoryFailure_whenSeized_thenAllAccountingRollsBack]: seizeSettlement.t.sol#L38
[test_givenOldCustodySurplus_whenNewReceiptShort_thenSurplusCannotMaskIt]: seizeSettlement.t.sol#L60
[test_givenOriginationsDisabled_whenSeized_thenDefaultStillSucceeds]: seizeIntegration.t.sol#L193
[test_givenPayoutReportsAnotherKernel_whenSeizedOrPreviewed_reverts]: seize.t.sol#L495
[test_givenPayoutUnavailable_whenSeizedOrPreviewed_reverts]: seize.t.sol#L513
[test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout]: seizeSharesIntegration.t.sol#L49
[test_givenPropagatedCollateralCallback_whenSeized_thenMandatoryTransferRollsBack]: seizeCallback.t.sol#L72
[test_givenProtocolKeeper_whenSeized_thenNoReward]: seizeIntegration.t.sol#L47
[test_givenRealUnhealthyUnexpiredDebt_whenSeized_thenHealthAndBalancesMatch]: seizeIntegration.t.sol#L201
[test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking]: seizeIntegration.t.sol#L122
[test_givenReportedKernelMismatch_whenAnyKeeperSeizes]: seize.t.sol#L418
[test_givenReportedKernelMismatch_whenSeized_thenGetterIsNotRead]: seize.t.sol#L396
[test_givenRiskRewardExceedsOutput_whenSeized_reverts]: seizeSettlement.t.sol#L24
[test_givenSettlementRoleRevoked_whenSeized_reverts]: seize.t.sol#L386
[test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury]: seizeSharesIntegration.t.sol#L40
[test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation]: seizeIntegration.t.sol#L38
[test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward]: seizeIntegration.t.sol#L29
[test_givenTreasuryPayoutFails_whenSeized_thenOnlyTreasuryRemainsPending]: seizePayout.t.sol#L27
[test_givenUnexpectedRedemptionToken_whenSeized_thenDefaultRollsBack]: seizeSettlement.t.sol#L48
[test_givenUnexpiredDebt_whenHealthBelowThreshold_thenSeizes]: seize.t.sol#L302
[test_givenUnhealthyDebt_whenSeized_thenDefaultAndPayoutConserveOutput]: seize.t.sol#L115
[test_givenZeroBorrowerAtAnyIndex_whenSeized_reverts]: seize.t.sol#L277
[test_givenZeroCollateralDebt_whenSeized_thenDebtDefaultsWithoutRedemption]: seizeIntegration.t.sol#L147
[test_givenZeroReward_whenKeeperDestinationUnused]: seizePayout.t.sol#L155
[test_whenAdjacentDuplicate_reverts]: seize.t.sol#L166
[test_whenBatchEmpty_reverts]: seize.t.sol#L135
[test_whenBatchFiftyOneContainsZeroBorrower_reverts]: seize.t.sol#L341
[test_whenBorrowerHasNoDebt_reverts]: seize.t.sol#L197
[test_whenBorrowerZero_reverts]: seize.t.sol#L157
[test_whenCallerAndResultBoundarySeeds_thenForwardsUnchanged]: seize.t.sol#L353
[test_whenFiftyBorrowersSeized_thenEveryPositionSettledOnce]: seizeBatch.t.sol#L128
[test_whenFiftyOneBorrowersSeized_thenEveryPositionSettledOnce]: seizeBatch.t.sol#L118
[test_whenHealthAtAndAboveThreshold_reverts]: seize.t.sol#L295
[test_whenHealthOneUnitBelowThreshold_thenSeizes]: seize.t.sol#L313
[test_whenHealthZero_thenSeizes]: seize.t.sol#L318
[test_whenLargeBatchContainsZeroBorrower_reverts]: seize.t.sol#L144
[test_whenMaxUint8BorrowersSeized_thenEveryPositionSettledOnce]: seizeBatch.t.sol#L123
[test_whenNonAdjacentDuplicate_reverts]: seize.t.sol#L181
[test_whenPayoutKeeperSeizes_reverts]: seizePayout.t.sol#L139
[test_whenPermissionlessKeeperSeizes_thenForwardsKeeperAndCoreResult]: seize.t.sol#L62
[test_whenValidBatchSeized_thenEveryPositionSettledOnce]: seizeBatch.t.sol#L22
[test_whenZeroAddressKeeperSeizes_reverts]: seizePayout.t.sol#L123
[test_givenMaturedDebtAndBackingPaused_whenSeized_reverts]: ./seizeIntegration.t.sol#L231
[test_whenZeroBorrowerAtFirstMiddleAndLast_reverts]: seize.t.sol#L346
