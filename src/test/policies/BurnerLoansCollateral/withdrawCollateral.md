# BurnerLoansCollateral.withdrawCollateral coverage plan

Source: [withdrawCollateral](../../../policies/burnerloans/BurnerLoansCollateral.sol#L91). Test mappings describe the verified scope of each named test.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLCOL-WITHDRAW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCollateral; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Implemented recipient rule: reject recipient=address(this) before price refresh or Core settlement. This is the general rule for user-facing actions accepting an explicit output recipient. Preserve the existing separate Core and selected-Custody rejection cases.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Defaults: `onBehalfOf_` is the nonzero borrower; execution is authorized; registered asset; amount>0; recipient nonzero and distinct from this action, Core and selected Custody. Position collateral C; principal D; resulting health H evaluated using one refreshed snapshot only if D>0.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Preview is permissionless and validates `onBehalfOf_`/inputs; execution separately authenticates its caller; no quote writes | Covered: [test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired][test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired], [test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree][test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree], [test_givenReEnabledAction_whenWithdrawn_thenOperational][test_givenReEnabledAction_whenWithdrawn_thenOperational], [test_givenReactivatedAction_whenWithdrawn_thenOperational][test_givenReactivatedAction_whenWithdrawn_thenOperational] |
| BLCOL-WITHDRAW-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCollateral_whenCoreIsDisabled_reverts][test_givenCollateral_whenCoreIsDisabled_reverts], [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCollateral_whenCoreIsInactive_reverts][test_givenCollateral_whenCoreIsInactive_reverts], [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenCollateral_whenActionIsDisabled_reverts][test_givenCollateral_whenActionIsDisabled_reverts], [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenCollateral_whenActionIsInactive_reverts][test_givenCollateral_whenActionIsInactive_reverts], [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-WITHDRAW-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |

## Borrower authorization

Quote requester and execution caller are independent. `onBehalfOf_` is the borrower whose
position is quoted; `recipient_` remains the output destination where applicable. Quotes do not
authenticate the viewer, read operator grants or inspect the viewer's funding/allowance.
Execution still authenticates `msg.sender` and collects that caller's deposit or fee.
For a viewer with no/cancelled/expired grant, the preview reaches input/economic checks;
execution retains its authorization error and earlier lifecycle guard order. Hold prices,
positions and time fixed when comparing viewers; changing time may change economic eligibility.

Borrowers and authorized operators may be EOAs or contracts without Kernel/status getters or protocol roles. Protocol roles do not replace borrower authorization. Existing grant cases retain independent deadline boundaries, cancellation and unrelated-caller rejection.

Action and Core are active/enabled. Unauthorized caller fuzzing excludes borrower and all currently authorized operators; zero borrower is tested independently.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-A01 | Borrower | caller=borrower; no operator grant | `Authorized` | Payer is the actual caller | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired][test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired], [test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree][test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-WITHDRAW-A02 | Delegated operator | caller=operator; grant issued at time1; independently fuzz deadline D in 2..MAX48 and now in 1..D-1; seed now=1,D-1 and D=MAX48 | `Authorized` | Borrower collateral debited; specified recipient paid; no fee or deposit collection | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenOperatorGrant_whenBeforeDeadline_thenAllWithdrawalEffectsAgree][test_givenOperatorGrant_whenBeforeDeadline_thenAllWithdrawalEffectsAgree], [test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A03 | Delegated operator | caller=operator; now=deadline; grant nonzero | `Authorized` | Deadline equality accepted | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenOperatorGrant_whenAtDeadline_thenWithdrawalSucceeds][test_givenOperatorGrant_whenAtDeadline_thenWithdrawalSucceeds], [test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A04 | Delegated operator | caller=operator; deadline=MAX48; now<=deadline | `Authorized` | No deadline narrowing | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-WITHDRAW-A05 | Fuzz all callers | borrower=0; actual caller arbitrary | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenWithdrawalBorrowerZero_reverts][test_whenWithdrawalBorrowerZero_reverts] |
| BLCOL-WITHDRAW-A06 | Fuzz callers excluding borrower | caller differs from borrower; no grant | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenDebtFreePosition_whenCallerIsUnauthorized_reverts][test_givenDebtFreePosition_whenCallerIsUnauthorized_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A07 | Fuzz callers excluding borrower | caller differs from borrower; grant cancelled to zero | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenCancelledGrant_whenOperatorActs_reverts][test_givenCancelledGrant_whenOperatorActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A08 | Delegated operator | caller=operator; grant nonzero; independently fuzz stored deadline D in 1..MAX48 and now in D+1..MAX256; seed D+1,MAX48+1,MAX256 | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenExpiredGrant_whenOperatorActs_reverts][test_givenExpiredGrant_whenOperatorActs_reverts], [test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized][test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A11 | Fuzz unrelated caller X | Borrower B has a valid grant to O; O differs from B; X differs from B and O and has no grant; independently fuzz deadline D in 2..MAX48 and now in 1..D; seed now=1,D and D=MAX48 | `OperatorAuth_UnauthorizedOnBehalfOf()` | B→O grant unchanged; no position, balance or accounting change; no committed logs | X receives the same quote as B under equal economic state; the B→O grant does not restrict quoting | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts][test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts], [test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected][test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |

## Core settlement authorization

Operational action and Core; borrower/operator authorization passes. Core requires only the action's `BL_COLLATERAL_POLICY_ROLE`, independently of the borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-A09 | Borrower | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test_givenSettlementRoleRevoked_whenWithdrawing_thenBothPathsReject][test_givenSettlementRoleRevoked_whenWithdrawing_thenBothPathsReject] |
| BLCOL-WITHDRAW-A10 | Borrower or authorized operator | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return WithdrawPreview(tokenOut,actualOutput,C-amount,H) | Debit collateral once and pay the selected recipient; principal unchanged; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenReportedKernelMismatch_whenWithdrawn_thenGetterIsNotRead][test_givenReportedKernelMismatch_whenWithdrawn_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenWithdrawn_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenWithdrawn_thenGetterIsNotRead] |

## Invalid inputs

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-I01 | Borrower | amount=0 | `BurnerLoansCore_ZeroAmount()` | Unchanged; no committed logs | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_givenCollateral_whenAmountIsZero_reverts][test_givenCollateral_whenAmountIsZero_reverts] |
| BLCOL-WITHDRAW-I02 | Borrower | recipient=0; positive amount | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_givenCollateral_whenRecipientIsZero_reverts][test_givenCollateral_whenRecipientIsZero_reverts] |
| BLCOL-WITHDRAW-I03 | Borrower | recipient=Core | `BurnerLoans_InvalidRecipient(recipient)` | Unchanged; no committed logs | Same BurnerLoans_InvalidRecipient(recipient) | Covered: [test_givenCollateral_whenRecipientIsCore_reverts][test_givenCollateral_whenRecipientIsCore_reverts] |
| BLCOL-WITHDRAW-I04 | Borrower | recipient=selected Custody | `BurnerLoans_InvalidRecipient(recipient)` | Unchanged; no committed logs | Same BurnerLoans_InvalidRecipient(recipient) | Covered: [test_givenCollateral_whenRecipientIsCustody_reverts][test_givenCollateral_whenRecipientIsCustody_reverts] |
| BLCOL-WITHDRAW-I05 | Borrower | recipient=BurnerLoansCollateral (address(this)); all other inputs valid | `BurnerLoans_InvalidRecipient(recipient)` | Unchanged; no Core settlement, token transfer or committed logs | Same BurnerLoans_InvalidRecipient(recipient) | Covered: [test_givenCollateral_whenRecipientIsAction_reverts][test_givenCollateral_whenRecipientIsAction_reverts] |
| BLCOL-WITHDRAW-I06 | Borrower | C<MAX128; fuzz amount C+1..MAX128; seed C+1 and MAX128 | `BurnerLoans_InsufficientCollateral(amount,C)` | Unchanged; no committed logs | Same BurnerLoans_InsufficientCollateral(amount,C) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenCollateral_whenAmountExceedsBalance_reverts][test_givenCollateral_whenAmountExceedsBalance_reverts], [test_givenCollateral_whenImmediatelyOverBalance_thenBothPathsReject][test_givenCollateral_whenImmediatelyOverBalance_thenBothPathsReject], [test_givenCollateral_whenMaximumAmount_thenBothPathsReject][test_givenCollateral_whenMaximumAmount_thenBothPathsReject], [test_givenDebtAndBrokenPricing_whenAmountExceedsCollateral_thenBoundsWin][test_givenDebtAndBrokenPricing_whenAmountExceedsCollateral_thenBoundsWin], [test_givenNoPosition_whenPositiveWithdrawal_thenBothPathsReject][test_givenNoPosition_whenPositiveWithdrawal_thenBothPathsReject] |

## Health and numeric boundaries

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-N01 | Borrower | Debt=0; amount 1..C; seed 1,C,MAX128 when constructible | `Health=MAX256; actual output/remaining collateral` | Actual DM receipt/liability debits; CollateralWithdrawn at action | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired][test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired], [test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree][test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree], [test_givenMaximumCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree][test_givenMaximumCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree], [test_givenOneUnitCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree][test_givenOneUnitCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree] |
| BLCOL-WITHDRAW-N02 | Borrower | Debt=0; unavailable pricing | `Health=MAX256` | No Risk/PRICE/cache call | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired][test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired], [test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree][test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree] |
| BLCOL-WITHDRAW-N03 | Borrower | Debt>0; actual remaining position health H<1e18 | `BurnerLoans_UnhealthyFinalPosition(H)` | Unchanged; no committed logs | Revert BurnerLoans_UnhealthyFinalPosition(H); no quote values are returned | Covered: [test_givenDebt_whenPostSettlementRiskValidationFails_thenTransfersAndAccountingRollBack][test_givenDebt_whenPostSettlementRiskValidationFails_thenTransfersAndAccountingRollBack], [test_givenUnhealthyFinalPosition_whenWithdrawn_thenExactErrorAndFullRollback][test_givenUnhealthyFinalPosition_whenWithdrawn_thenExactErrorAndFullRollback], [test_givenHealthImmediatelyBelowOne_whenWithdrawn_reverts][test_givenHealthImmediatelyBelowOne_whenWithdrawn_reverts], [test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback][test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback] |
| BLCOL-WITHDRAW-N04 | Borrower | Debt>0; actual remaining health H=1e18 | `Success` | Health accepted exactly at boundary | Return output, remaining collateral and health=1e18; compare actual values under unchanged prices/conversion | Covered: [test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned][test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned], [test_givenDebt_whenHealthExactlyOne_thenAccepted][test_givenDebt_whenHealthExactlyOne_thenAccepted], [test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted][test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted] |
| BLCOL-WITHDRAW-N05 | Borrower | Debt>0; actual remaining health H>1e18 | `Success` | Return health from actual remaining collateral/canonical principal | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned][test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned], [test_givenMaximumHealth_whenWithdrawn_thenExactValueReturned][test_givenMaximumHealth_whenWithdrawn_thenExactValueReturned], [test_givenHealthImmediatelyAboveOne_whenWithdrawn_thenExactValueReturned][test_givenHealthImmediatelyAboveOne_whenWithdrawn_thenExactValueReturned], [test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral][test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral] |
| BLCOL-WITHDRAW-N06 | Borrower | Originations disabled; healthy withdrawal | `Success` | No origination gate on servicing | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen][test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen] |
| BLCOL-WITHDRAW-N07 | Borrower | Inventory disabled; healthy withdrawal | `Success` | No Inventory gate on collateral exits | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen][test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen] |
| BLCOL-WITHDRAW-N08 | Borrower | Underlying-output custody mode | `Success` | Underlying recipient delta equals actual returned amount | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenTokenIsRecipient_whenWithdrawn_thenAllowedOverlap][test_givenTokenIsRecipient_whenWithdrawn_thenAllowedOverlap], [_withdrawSynchronousVault][_withdrawSynchronousVault], [test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved][test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved], [test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput][test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput], [test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed][test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed], [test_givenRepeatedPartialWithdrawals_whenLastCreditConsumed_thenExactlyExhausted][test_givenRepeatedPartialWithdrawals_whenLastCreditConsumed_thenExactlyExhausted], [test_givenSynchronousVault_whenUnderlyingWithdrawn][test_givenSynchronousVault_whenUnderlyingWithdrawn], [test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn][test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn] |
| BLCOL-WITHDRAW-N09 | Borrower | Share-output custody mode | `Success` | Share-token recipient delta and decimals verified | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [_withdrawSynchronousVault][_withdrawSynchronousVault], [test_givenExternalSharesWithSameDecimals_whenWithdrawn_thenExternalTokenDelivered][test_givenExternalSharesWithSameDecimals_whenWithdrawn_thenExternalTokenDelivered], [test_givenExternalSharesWithDifferentDecimals_whenWithdrawn_thenUnitsPreserved][test_givenExternalSharesWithDifferentDecimals_whenWithdrawn_thenUnitsPreserved], [test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved][test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved], [test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput][test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput], [test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed][test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed], [test_givenAsynchronousVaultDrift_whenUnderlyingRequested_thenBothPathsReject][test_givenAsynchronousVaultDrift_whenUnderlyingRequested_thenBothPathsReject], [test_givenExplicitWarmupRequirement_whenUnderlyingRequested_thenBothPathsReject][test_givenExplicitWarmupRequirement_whenUnderlyingRequested_thenBothPathsReject], [test_givenAsynchronousVaultDrift_whenSharesRequested_thenExitRemainsAvailable][test_givenAsynchronousVaultDrift_whenSharesRequested_thenExitRemainsAvailable], [test_givenSynchronousVault_whenSharesWithdrawn][test_givenSynchronousVault_whenSharesWithdrawn], [test_givenOneVaultUnit_whenSharesWithdrawn][test_givenOneVaultUnit_whenSharesWithdrawn] |

## Transfer and settlement failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-T01 | Borrower | Actual withdrawal output=0 | `BurnerLoansCore_ZeroCollateralWithdrawal()` | Unchanged; no committed logs | Revert BurnerLoansCore_ZeroCollateralWithdrawal() when projected output is zero | Covered: [test_givenWithdrawalRoundsToZero_whenQuotedOrExecuted_thenRejectAndRollback][test_givenWithdrawalRoundsToZero_whenQuotedOrExecuted_thenRejectAndRollback], [test_givenDebtAndSubShareOutput_whenWithdrawn_thenBothPathsReject][test_givenDebtAndSubShareOutput_whenWithdrawn_thenBothPathsReject] |
| BLCOL-WITHDRAW-T02 | Borrower | DM returns unexpected output token | `BurnerLoansCore_InvalidSettlement()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenUnexpectedWithdrawalToken_whenWithdrawn_thenCollateralDebitRollsBack][test_givenUnexpectedWithdrawalToken_whenWithdrawn_thenCollateralDebitRollsBack] |
| BLCOL-WITHDRAW-T03 | Borrower | DM operator assets+borrowed < liabilities at post-exit validation | `DepositManager_Insolvent(asset,liabilities,assets,borrowed)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenVaultLoss_whenWithdrawn_thenDepositManagerEnforcesPostExitSolvency][test_givenVaultLoss_whenWithdrawn_thenDepositManagerEnforcesPostExitSolvency] |
| BLCOL-WITHDRAW-T04 | Borrower | Debt>0; snapshot dependency fails | `Exact configured pricing/dependency error` | Unchanged; no committed logs | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers][test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers], [test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack][test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack] |
| BLCOL-WITHDRAW-T05 | Borrower | Recipient token transfer returns false | `SafeERC20FailedOperation(outputToken)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenWithdrawalTokenReturnsFalse_whenWithdrawn_thenEntireExitRollsBack][test_givenWithdrawalTokenReturnsFalse_whenWithdrawn_thenEntireExitRollsBack] |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee, health and reward responses used by this function. Assert exact method arguments and call counts, actual Core/FLOAN state and returned configured values; do not duplicate Risk arithmetic in action assertions. Debt-free or full-repayment price-free paths configure the mock to reject unexpected pricing calls. Risk’s suite independently proves math and rounding.

Seed uint128 maximum, one-unit redemption rounding, exact health threshold and token and recipient sharing an address overlaps permitted by the public layer. DM recipient validation may reject DM itself. The preview reverts with BurnerLoans_UnhealthyFinalPosition(H) for unhealthy remaining collateral and BurnerLoansCore_ZeroCollateralWithdrawal() for zero projected output. Recipient and borrower-grant validation follows the action rules. Test nested guarded Core operations at withdrawal callbacks, caught and propagated, and isolate other positions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Guarantee ERC7575 external share tokens with same AND different decimals; async/warmup vault underlying rejection and shares success; vault yield after preview; repeated partial withdrawals exactly exhaust credited collateral; sub-share output rejection with positive debt; vault loss triggers DM solvency rollback.

## Real Risk integration

Use withdrawCollateralIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Fix the borrower/keeper caller because authorization is covered in unit scenarios. Derive expected economics independently from prices, decimal scales and actual settlement state. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-P01 | Borrower | Valid real snapshot; compatible payout and funding; independent economic boundary seeds from this function’s numeric rows | Successful operation | Actual balances, collateral/debt, fee/reward and WAD health match an independent calculation; preview agrees only with unchanged prices/conversion | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral][test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral], [test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted][test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted], [test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback][test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback] |
| BLCOL-WITHDRAW-P02 | Borrower | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Real view pricing failure rejects preview; real refresh failure rejects execution; compare exact errors only when the same underlying dependency fails both paths | Covered: [test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers][test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers], [test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack][test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack] |

## Price-refresh callbacks before settlement

Core's transfer guard is not entered during Risk.refreshSnapshot. Use an operational cache callback actor, with a real unexpired borrower grant for authorized borrowing/withdrawal/extension and funded payer approvals for repayment. Do not expect a Core reentrancy error before the guard is entered.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-C01 | Borrower | Cache callback removes collateral through a valid nested action; outer request exceeds reloaded available collateral; FLOAN/Core rejection rolls back all nested and outer changes | IFLOANv1.FLOAN_InvalidAmount(); all nested/outer changes roll back | Successful call reflects actual state; rejected call restores Core/FLOAN/Inventory/DM/cache balances, allowances and logs | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheWithdraws_whenOuterNowExceedsCollateral_thenRollback][test_givenCacheWithdraws_whenOuterNowExceedsCollateral_thenRollback] |

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCaughtUnauthorizedCacheAction_whenWithdrawing_thenOneDebit][test_givenCaughtUnauthorizedCacheAction_whenWithdrawing_thenOneDebit] |
| BLCOL-WITHDRAW-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenPropagatedUnauthorizedCacheAction_whenWithdrawing_thenRollback][test_givenPropagatedUnauthorizedCacheAction_whenWithdrawing_thenRollback] |

Retired BLCOL-WITHDRAW-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative collateral-token transfer with nonzero pre-existing accounting and an unrelated entity. Core/DepositManager/vault suites own their distinct custody boundaries; do not multiply the action case across every transfer hook or caller class. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-C05 | Borrower | Collateral delivery from DepositManager to recipient | One authorized, funded nested public action reaches Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One collateral debit and recipient output; actual remaining collateral and WAD health agree; unrelated positions unchanged | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test_givenUnderlyingDeliveryCallback_whenActionReentryCaught][test_givenUnderlyingDeliveryCallback_whenActionReentryCaught], [test_givenUnderlyingDeliveryCallback_whenCoreReentryCaught][test_givenUnderlyingDeliveryCallback_whenCoreReentryCaught], [test_givenVaultRedemptionCallback_whenActionReentryCaught][test_givenVaultRedemptionCallback_whenActionReentryCaught], [test_givenVaultRedemptionCallback_whenCoreReentryCaught][test_givenVaultRedemptionCallback_whenCoreReentryCaught], [test_givenShareDeliveryCallback_whenActionReentryCaught][test_givenShareDeliveryCallback_whenActionReentryCaught], [test_givenShareDeliveryCallback_whenCoreReentryCaught][test_givenShareDeliveryCallback_whenCoreReentryCaught] |
| BLCOL-WITHDRAW-C06 | Borrower | Collateral delivery from DepositManager to recipient | One authorized, funded nested public action reaches Core settlement; callback propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test_givenUnderlyingDeliveryCallback_whenActionReentryPropagated][test_givenUnderlyingDeliveryCallback_whenActionReentryPropagated], [test_givenUnderlyingDeliveryCallback_whenCoreReentryPropagated][test_givenUnderlyingDeliveryCallback_whenCoreReentryPropagated], [test_givenVaultRedemptionCallback_whenActionReentryPropagated][test_givenVaultRedemptionCallback_whenActionReentryPropagated], [test_givenVaultRedemptionCallback_whenCoreReentryPropagated][test_givenVaultRedemptionCallback_whenCoreReentryPropagated], [test_givenShareDeliveryCallback_whenActionReentryPropagated][test_givenShareDeliveryCallback_whenActionReentryPropagated], [test_givenShareDeliveryCallback_whenCoreReentryPropagated][test_givenShareDeliveryCallback_whenCoreReentryPropagated] |

## Core Kernel binding

The action and Core are active and enabled. Core remains a member of the expected Kernel but reports a different Kernel.

| ID | Caller | Core reported Kernel | Execution | Preview | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-D04 | Borrower | Foreign Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel) | Same exact error | No position, custody or balance changes | Covered: [test_givenCoreReportsAnotherKernel_whenWithdrawn_thenKernelMismatch][test_givenCoreReportsAnotherKernel_whenWithdrawn_thenKernelMismatch] |

## Permissionless quote identities

| ID | Quote requester | Position owner | Execution caller / history | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-A12 | Fuzz every address; no authorization lookup allowed | Nonzero `onBehalfOf_`=B | Borrower or operator may execute later | Identical independently checked quote for B; no writes/logs or funding requirements | Covered: [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-WITHDRAW-A13 | Unrelated viewer X | B | Prospective operator O before grant, while valid, at deadline, after expiry and after revocation | Quote remains independent of O's grant while economic state is valid; execution follows grant validity | Covered: [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLCOL-WITHDRAW-A14 | Unrelated viewer X | B | B collateral=100e6; X collateral=50; quote withdrawal=7 to a separate recipient | Output=7; projected B collateral=100e6-7; neither position changes | Covered: [test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted][test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted] |

## Custody exit availability

Action and Core are active/enabled. Permitted borrower for withdrawals; fuzz permissionless keeper for unavailable seizure custody. Other dependencies are ready.

| ID | Pre-state | Preview / execution | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-D05 | DepositManager locally paused; existing debt-free position | Both revert BurnerLoansCore_InvalidDepositManager(DM) | No position, receipt, balance or allowance change | Covered: [test_givenDepositManagerPaused_whenWithdrawn_reverts][test_givenDepositManagerPaused_whenWithdrawn_reverts] |
| BLCOL-WITHDRAW-D06 | Deposit period configured but disabled for new deposits | Both permit existing-position withdrawal | Exact output and remaining collateral; quote is read-only | Covered: [test_givenDepositPeriodDisabled_whenWithdrawn_thenExitRemainsAvailable][test_givenDepositPeriodDisabled_whenWithdrawn_thenExitRemainsAvailable] |

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLCOL-WITHDRAW-D07 | Borrower | DepositManager Kernel-inactive; valid withdrawal | PolicyDependency_NotActive(DepositManager) on preview and execution; custody/position unchanged | Covered: [test_givenDepositManagerInactive_whenWithdrawn_reverts][test_givenDepositManagerInactive_whenWithdrawn_reverts] |

## Backing availability regressions

Local policy and ordinary dependencies are active/enabled; callers satisfy the
existing action authorization. Each fault varies backing readiness independently.
Rejection preserves authoritative accounting, custody and emitted logs.

| ID | Scenario | Expected execution and preview | Test |
| --- | --- | --- | --- |
| BLCOL-WITHDRAW-D08 | Debt=100e9; oracle disabled; change collateral by 1e6 | Preview/execution: PolicyDependency_NotActive(oracle); accounting/custody unchanged | Covered: [test][test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement] |
| BLCOL-WITHDRAW-D09 | Debt-free collateral=100e6; oracle disabled; change collateral by 1e6 | Exact 1e6 credit/output and 101e6 deposit or 99e6 withdrawal remainder; uint256.max health | Covered: [test][test_givenDebtFreeAndBackingPaused_whenCollateralChanged] |

[_withdrawSynchronousVault]: withdrawCollateralIntegration.t.sol#L28
[test_givenActionKernelGetterReverts_whenWithdrawn_thenGetterIsNotRead]: withdrawCollateral.t.sol#L513
[test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected]: withdrawCollateral.t.sol#L876
[test_givenAsynchronousVaultDrift_whenSharesRequested_thenExitRemainsAvailable]: withdrawCollateralIntegration.t.sol#L440
[test_givenAsynchronousVaultDrift_whenUnderlyingRequested_thenBothPathsReject]: withdrawCollateralIntegration.t.sol#L424
[test_givenCacheWithdraws_whenOuterNowExceedsCollateral_thenRollback]: withdrawCollateralPriceCallbacks.t.sol#L19
[test_givenCancelledGrant_whenOperatorActs_reverts]: withdrawCollateral.t.sol#L411
[test_givenCaughtUnauthorizedCacheAction_whenWithdrawing_thenOneDebit]: withdrawCollateralPriceCallbacks.t.sol#L56
[test_givenCollateral_whenActionIsDisabled_reverts]: withdrawCollateral.t.sol#L273
[test_givenCollateral_whenActionIsInactive_reverts]: withdrawCollateral.t.sol#L279
[test_givenCollateral_whenAmountExceedsBalance_reverts]: withdrawCollateral.t.sol#L191
[test_givenCollateral_whenAmountIsZero_reverts]: withdrawCollateral.t.sol#L182
[test_givenCollateral_whenCoreIsDisabled_reverts]: withdrawCollateral.t.sol#L292
[test_givenCollateral_whenCoreIsInactive_reverts]: withdrawCollateral.t.sol#L305
[test_givenCollateral_whenImmediatelyOverBalance_thenBothPathsReject]: withdrawCollateral.t.sol#L708
[test_givenCollateral_whenMaximumAmount_thenBothPathsReject]: withdrawCollateral.t.sol#L724
[test_givenCollateral_whenRecipientIsAction_reverts]: withdrawCollateral.t.sol#L220
[test_givenCollateral_whenRecipientIsCore_reverts]: withdrawCollateral.t.sol#L231
[test_givenCollateral_whenRecipientIsCustody_reverts]: withdrawCollateral.t.sol#L242
[test_givenCollateral_whenRecipientIsZero_reverts]: withdrawCollateral.t.sol#L212
[test_givenCoreReportsAnotherKernel_whenWithdrawn_thenKernelMismatch]: withdrawCollateral.t.sol#L86
[test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified]: withdrawCollateral.t.sol#L474
[test_givenDebtAndBrokenPricing_whenAmountExceedsCollateral_thenBoundsWin]: withdrawCollateral.t.sol#L892
[test_givenDebtAndSubShareOutput_whenWithdrawn_thenBothPathsReject]: withdrawCollateralIntegration.t.sol#L401
[test_givenDebtFreePosition_whenCallerIsUnauthorized_reverts]: withdrawCollateral.t.sol#L170
[test_givenDebtFreePosition_whenCollateralIsWithdrawn_thenNoPriceIsRequired]: withdrawCollateral.t.sol#L105
[test_givenDebtFreePosition_whenFullRangeWithdrawal_thenAllReturnsAndCustodyAgree]: withdrawCollateral.t.sol#L674
[test_givenDebt_whenCollateralIsWithdrawn_thenHealthUsesActualRemainingCollateral]: withdrawCollateralIntegration.t.sol#L258
[test_givenDebt_whenHealthExactlyOne_thenAccepted]: withdrawCollateral.t.sol#L576
[test_givenDebt_whenPostSettlementRiskValidationFails_thenTransfersAndAccountingRollBack]: withdrawCollateral.t.sol#L136
[test_givenDebt_whenRiskReturnsBoundaryHealth_thenExactValueReturned]: withdrawCollateral.t.sol#L530
[test_givenDepositManagerInactive_whenWithdrawn_reverts]: withdrawCollateral.t.sol#L31
[test_givenDepositManagerPaused_whenWithdrawn_reverts]: withdrawCollateral.t.sol#L47
[test_givenDepositPeriodDisabled_whenWithdrawn_thenExitRemainsAvailable]: withdrawCollateral.t.sol#L60
[test_givenDisabledAction_whenInvoked_thenLocalPauseWins]: withdrawCollateral.t.sol#L461
[test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins]: withdrawCollateral.t.sol#L809
[test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized]: withdrawCollateral.t.sol#L866
[test_givenExpiredGrant_whenOperatorActs_reverts]: withdrawCollateral.t.sol#L425
[test_givenExpiredGrant_whenUnrelatedViewerQuotes]: withdrawCollateral.t.sol#L996
[test_givenExplicitWarmupRequirement_whenUnderlyingRequested_thenBothPathsReject]: withdrawCollateralIntegration.t.sol#L431
[test_givenExternalSharesWithDifferentDecimals_whenWithdrawn_thenUnitsPreserved]: withdrawCollateralIntegration.t.sol#L108
[test_givenExternalSharesWithSameDecimals_whenWithdrawn_thenExternalTokenDelivered]: withdrawCollateralIntegration.t.sol#L80
[test_givenGrantDeadline_whenUnrelatedViewerQuotes]: withdrawCollateral.t.sol#L987
[test_givenHealthImmediatelyAboveOne_whenWithdrawn_thenExactValueReturned]: withdrawCollateral.t.sol#L767
[test_givenHealthImmediatelyBelowOne_whenWithdrawn_reverts]: withdrawCollateral.t.sol#L757
[test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified]: withdrawCollateral.t.sol#L443
[test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins]: withdrawCollateral.t.sol#L792
[test_givenMaximumCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree]: withdrawCollateral.t.sol#L695
[test_givenMaximumHealth_whenWithdrawn_thenExactValueReturned]: withdrawCollateral.t.sol#L762
[test_givenMaximumOperatorDeadline_whenWithdrawalBoundaryTimesUsed]: withdrawCollateral.t.sol#L649
[test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved]: withdrawCollateralIntegration.t.sol#L219
[test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn]: withdrawCollateralIntegration.t.sol#L516
[test_givenNoGrant_whenUnrelatedViewerQuotes]: withdrawCollateral.t.sol#L968
[test_givenNoPosition_whenPositiveWithdrawal_thenBothPathsReject]: withdrawCollateral.t.sol#L918
[test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput]: withdrawCollateralIntegration.t.sol#L224
[test_givenOneUnitCollateral_whenFullyWithdrawn_thenAllReturnsAndCustodyAgree]: withdrawCollateral.t.sol#L703
[test_givenOneVaultUnit_whenSharesWithdrawn]: withdrawCollateralIntegration.t.sol#L521
[test_givenOperatorGrant_whenAtDeadline_thenWithdrawalSucceeds]: withdrawCollateral.t.sol#L638
[test_givenOperatorGrant_whenBeforeDeadline_thenAllWithdrawalEffectsAgree]: withdrawCollateral.t.sol#L626
[test_givenOriginationsAndInventoryDisabled_whenHealthyWithdrawn_thenServicingOpen]: withdrawCollateral.t.sol#L597
[test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts]: withdrawCollateral.t.sol#L389
[test_givenPropagatedUnauthorizedCacheAction_whenWithdrawing_thenRollback]: withdrawCollateralPriceCallbacks.t.sol#L76
[test_givenReEnabledAction_whenWithdrawn_thenOperational]: withdrawCollateral.t.sol#L772
[test_givenReactivatedAction_whenWithdrawn_thenOperational]: withdrawCollateral.t.sol#L782
[test_givenRealRisk_whenOneUnitBeyondHealthyWithdrawal_thenFullRollback]: withdrawCollateralIntegration.t.sol#L318
[test_givenRealRisk_whenWithdrawalLeavesExactBacking_thenAccepted]: withdrawCollateralIntegration.t.sol#L293
[test_givenRealStalePrice_whenWithdrawalQuotedOrExecuted_thenRejectsBeforeTransfers]: withdrawCollateralIntegration.t.sol#L229
[test_givenRepeatedPartialWithdrawals_whenLastCreditConsumed_thenExactlyExhausted]: withdrawCollateralIntegration.t.sol#L370
[test_givenReportedKernelMismatch_whenWithdrawn_thenGetterIsNotRead]: withdrawCollateral.t.sol#L501
[test_givenRevokedGrant_whenUnrelatedViewerQuotes]: withdrawCollateral.t.sol#L1009
[test_givenSettlementRoleRevoked_whenWithdrawing_thenBothPathsReject]: withdrawCollateral.t.sol#L661
[test_givenShareDeliveryCallback_whenActionReentryCaught]: withdrawCollateralCallbacks.t.sol#L140
[test_givenShareDeliveryCallback_whenActionReentryPropagated]: withdrawCollateralCallbacks.t.sol#L156
[test_givenShareDeliveryCallback_whenCoreReentryCaught]: withdrawCollateralCallbacks.t.sol#L173
[test_givenShareDeliveryCallback_whenCoreReentryPropagated]: withdrawCollateralCallbacks.t.sol#L185
[test_givenStaleRealCache_whenPriceFeedFails_thenQuoteAndExecutionRollBack]: withdrawCollateralIntegration.t.sol#L526
[test_givenSynchronousVault_whenSharesWithdrawn]: withdrawCollateralIntegration.t.sol#L508
[test_givenSynchronousVault_whenUnderlyingWithdrawn]: withdrawCollateralIntegration.t.sol#L500
[test_givenTokenIsRecipient_whenWithdrawn_thenAllowedOverlap]: withdrawCollateral.t.sol#L841
[test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins]: withdrawCollateral.t.sol#L825
[test_givenUnderlyingDeliveryCallback_whenActionReentryCaught]: withdrawCollateralCallbacks.t.sol#L26
[test_givenUnderlyingDeliveryCallback_whenActionReentryPropagated]: withdrawCollateralCallbacks.t.sol#L42
[test_givenUnderlyingDeliveryCallback_whenCoreReentryCaught]: withdrawCollateralCallbacks.t.sol#L34
[test_givenUnderlyingDeliveryCallback_whenCoreReentryPropagated]: withdrawCollateralCallbacks.t.sol#L51
[test_givenUnexpectedWithdrawalToken_whenWithdrawn_thenCollateralDebitRollsBack]: withdrawCollateral.t.sol#L318
[test_givenUnhealthyFinalPosition_whenWithdrawn_thenExactErrorAndFullRollback]: withdrawCollateral.t.sol#L740
[test_givenValidGrant_whenUnrelatedViewerQuotes]: withdrawCollateral.t.sol#L979
[test_givenVaultLoss_whenWithdrawn_thenDepositManagerEnforcesPostExitSolvency]: withdrawCollateralIntegration.t.sol#L180
[test_givenVaultRedemptionCallback_whenActionReentryCaught]: withdrawCollateralCallbacks.t.sol#L60
[test_givenVaultRedemptionCallback_whenActionReentryPropagated]: withdrawCollateralCallbacks.t.sol#L76
[test_givenVaultRedemptionCallback_whenCoreReentryCaught]: withdrawCollateralCallbacks.t.sol#L68
[test_givenVaultRedemptionCallback_whenCoreReentryPropagated]: withdrawCollateralCallbacks.t.sol#L85
[test_givenVaultYieldAfterQuote_whenSharesWithdrawn_thenActualOutputUsed]: withdrawCollateralIntegration.t.sol#L334
[test_givenWithdrawalRoundsToZero_whenQuotedOrExecuted_thenRejectAndRollback]: withdrawCollateralIntegration.t.sol#L152
[test_givenWithdrawalTokenReturnsFalse_whenWithdrawn_thenEntireExitRollsBack]: withdrawCollateral.t.sol#L347
[test_whenAnyViewerQuotesWithoutAuthorizationRead]: withdrawCollateral.t.sol#L934
[test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted]: withdrawCollateral.t.sol#L1023
[test_whenWithdrawalBorrowerZero_reverts]: withdrawCollateral.t.sol#L581

[test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement]: ./withdrawCollateral.t.sol#L1045

[test_givenDebtFreeAndBackingPaused_whenCollateralChanged]: ./withdrawCollateral.t.sol#L1072
