# BurnerLoansCollateral.depositCollateral coverage plan

Authorization migration: grants now live on the selected BurnerLoansAuth. The public caller is the actual operator. Zero operator identities reject with `OperatorAuth_InvalidIdentity`; other absent/cancelled authority rejects with `OperatorAuth_InvalidContext`; expired accepted grants reject with `OperatorAuth_ExpiredGrant(deadline)`. An expired grant does not block permissionless previews. Cancelled-grant fixtures use nonzero operators because zero-operator grants cannot be created. Canonical permissions bind the explicit market asset, including custom callback tokens.

Source: [depositCollateral](../../../policies/burnerloans/BurnerLoansCollateral.sol#L50). Test mappings describe the verified scope of each named test.

Coverage records implemented domains and assertions. `Covered` requires passing focused execution;
`Partial` identifies missing proof or pending execution, not necessarily a production failure.
New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLCOL-DEPOSIT` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCollateral; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Implemented API: return `(credit, collateral, resultingHealthFactor)`. Compute WAD health from actual post-deposit FLOAN collateral and debt using the operation’s refreshed Risk snapshot captured before settlement. Use `Risk.health`, not `validateHealth`: a deposit may improve a still-unhealthy position. Debt-free executions return uint256.max health without pricing. Debt-bearing executions require working Risk/pricing and roll back atomically if health reporting fails. The preview change below removes health and pricing from deposit quotes.

Cap applies to actual credited amount Q, not input amount A: DepositManager enforces pre-utilization U+Q<=cap. For direct custody Q=A; vault conversion may make them differ. Minimum deposit remains an input-amount check. No duplicate input-amount cap check belongs to the action.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Defaults: `onBehalfOf_` is the nonzero borrower; execution is authorized; asset registered, market originations enabled except the explicit disabled-originations cases; DepositManager active/enabled, asset and period 1 for Core configured/enabled. Units: amount and credited collateral are underlying asset units; credit need not equal amount.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Deposit preview return values

Approved review direction: `previewDepositCollateral` returns `(credit, collateral)` only.
It makes no Risk, PRICE, oracle, cache or health-calculation calls, regardless of existing debt.
The action still returns `(credit, collateral, resultingHealthFactor)` and retains its health reporting.
Withdrawal execution and withdrawal previews keep their existing health fields.

Preview validates its existing own/Core admission, borrower, market, custody support, minimum,
converted credit, cap and uint128 resulting-collateral bounds. It remains permissionless and read-only.
Compare its two fields with the action's first two fields under stable conversion.
Post-deposit solvency and changes realized by a vault call remain execution-only conditions.

The input signature and selector remain unchanged; successful returndata becomes two uint256 words
(64 bytes). All local callers, fixtures, handlers and proposal tests must decode two return values.
Three-value decoders are incompatible even though the selector and ERC-165 interface ID do not change.
Existing rows whose preview requirements change are Partial until their assertions migrate.
Preserve their execution/health coverage rather than deleting it with the preview field.

| ID | Caller | Existing debt / dependencies | Required preview result | Execution control | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-P22 | Fuzz every viewer without role exclusions | New/existing position; compatible C,Q and uint128 maximum seeds | Exactly two values (estimated Q,C+Q), 64-byte success result; no health field or writes | Stable execution matches the first two fields and retains its third health return | Covered: [test][test_whenDepositQuoted_thenOnlyCreditAndCollateralReturned], [test][test_whenAnyViewerQuotesCompatibleCollateral], [test][test_whenDepositQuoteMaximumSeeds], [test][test_givenExistingCollateral_whenDepositQuoteReachesMaximum] |
| BLCOL-DEPOSIT-P23 | Unrelated viewer | Debt>0; independently make Risk.snapshot, refreshSnapshot and health revert; pause oracle/cache; guarantee each fault | Quote Q,C+Q without touching any price/health service | Actual deposit preserves its existing pricing/health failures and atomic rollback | Covered: [test][test_givenDebtAndPricingUnavailable_whenDepositQuoted_thenNoPricingRead], [test][test_givenDebtAndRiskSnapshotUnavailable_whenDepositQuoted], [test][test_givenDebtAndRiskPointerUnavailable_whenDepositQuoted], [test][test_givenDebt_whenRiskHealthFails_thenDepositRollsBack], [test][test_givenDebt_whenSnapshotRefreshFails_thenIndependentViewAndRollback], [test][test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement], [test][test_givenDebtAndPriceCachePaused_whenCollateralDeposited] |

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Preview is permissionless and validates `onBehalfOf_`/inputs; execution separately authenticates its caller; no quote writes | Covered: [test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree][test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree], [test_givenReEnabledAction_whenDeposited_thenOperational][test_givenReEnabledAction_whenDeposited_thenOperational], [test_givenReactivatedAction_whenDeposited_thenOperational][test_givenReactivatedAction_whenDeposited_thenOperational] |
| BLCOL-DEPOSIT-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified][test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified], [test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenDisabledAction_whenInvoked_thenLocalPauseWins][test_givenDisabledAction_whenInvoked_thenLocalPauseWins], [test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |
| BLCOL-DEPOSIT-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansCollateral); reject before presenting an executable quote | Covered: [test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified][test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified], [test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins][test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins] |

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
| BLCOL-DEPOSIT-A01 | Borrower | caller=borrower; no operator grant | `Authorized` | Payer is the actual caller | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree][test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-DEPOSIT-A02 | Delegated operator | caller=operator; grant issued at time1; independently fuzz deadline D in 2..MAX48 and now in 1..D-1; seed now=1,D-1 and D=MAX48 | `Authorized` | Borrower collateral credited; actual caller funds the deposit | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenOperatorGrant_whenBeforeDeadline_thenAllDepositEffectsAgree][test_givenOperatorGrant_whenBeforeDeadline_thenAllDepositEffectsAgree], [test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A03 | Delegated operator | caller=operator; now=deadline; grant nonzero | `Authorized` | Deadline equality accepted | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenOperatorGrant_whenAtDeadline_thenDepositSucceeds][test_givenOperatorGrant_whenAtDeadline_thenDepositSucceeds], [test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A04 | Delegated operator | caller=operator; deadline=MAX48; now<=deadline | `Authorized` | No deadline narrowing | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed][test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-DEPOSIT-A05 | Fuzz all callers | borrower=0; actual caller arbitrary | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerIsZero_thenPreviewAndExecutionReject][test_whenBorrowerIsZero_thenPreviewAndExecutionReject] |
| BLCOL-DEPOSIT-A06 | Fuzz callers excluding borrower | caller differs from borrower; no grant | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_whenCallerIsUnauthorized_reverts][test_whenCallerIsUnauthorized_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A07 | Fuzz callers excluding borrower | caller differs from borrower; grant cancelled to zero | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenCancelledGrant_whenOperatorActs_reverts][test_givenCancelledGrant_whenOperatorActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A08 | Delegated operator | caller=operator; grant nonzero; independently fuzz stored deadline D in 1..MAX48 and now in D+1..MAX256; seed D+1,MAX48+1,MAX256 | `OperatorAuth_ExpiredGrant(D)` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenAuthorizationExpired_whenOperatorDeposits_reverts][test_givenAuthorizationExpired_whenOperatorDeposits_reverts], [test_givenExpiredGrant_whenOperatorActs_reverts][test_givenExpiredGrant_whenOperatorActs_reverts], [test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized][test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A11 | Fuzz unrelated caller X | Borrower B has a valid grant to O; O differs from B; X differs from B and O and has no grant; independently fuzz deadline D in 2..MAX48 and now in 1..D; seed now=1,D and D=MAX48 | `OperatorAuth_InvalidContext()` | B→O grant unchanged; no position, balance or accounting change; no committed logs | X receives the same quote as B under equal economic state; the B→O grant does not restrict quoting | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts][test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts], [test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected][test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |

## Core settlement authorization

Operational action and Core; borrower/operator authorization passes. Core requires only the action's `BL_COLLATERAL_POLICY_ROLE`, independently of the borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-A09 | Borrower | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test_givenSettlementRoleRevoked_whenDepositing_thenBothPathsReject][test_givenSettlementRoleRevoked_whenDepositing_thenBothPathsReject] |
| BLCOL-DEPOSIT-A10 | Borrower or authorized operator | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return (Q,C+Q,H) | Credit actual Q once to the selected position and Core receipts/liabilities; actual caller funds the deposit; no new debt; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenReportedKernelMismatch_whenDeposited_thenGetterIsNotRead][test_givenReportedKernelMismatch_whenDeposited_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenDeposited_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenDeposited_thenGetterIsNotRead] |

## Invalid inputs

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-I01 | Borrower | amount=0; borrower nonzero and authorized | `BurnerLoansCore_ZeroAmount()` | Unchanged; no committed logs | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAmountIsZero_reverts][test_whenAmountIsZero_reverts] |
| BLCOL-DEPOSIT-I02 | Borrower | asset unregistered; amount=1 | `BurnerLoansCore_AssetNotConfigured(asset)` | Unchanged; no committed logs | Same BurnerLoansCore_AssetNotConfigured(asset) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAssetIsUnregistered_reverts][test_whenAssetIsUnregistered_reverts], [test_whenZeroAsset_thenExactRegistrationError][test_whenZeroAsset_thenExactRegistrationError] |
| BLCOL-DEPOSIT-I04 | Borrower | DepositManager locally disabled | `BurnerLoansCore_InvalidDepositManager(DM)` | Unchanged; no committed logs | Same input/custody/cap failure with earlier preview admission satisfied; no Risk/PRICE calls or writes | Covered: [test_givenDepositManagerDisabled_whenDeposited_reverts][test_givenDepositManagerDisabled_whenDeposited_reverts] |
| BLCOL-DEPOSIT-I05 | Borrower | DepositManager asset absent | `BurnerLoansCore_InvalidDepositManager(DM)` | Unchanged; no committed logs | Same input/custody/cap failure with earlier preview admission satisfied; no Risk/PRICE calls or writes | Covered: [test_givenAssetNoLongerConfiguredInManager_whenDeposited_reverts][test_givenAssetNoLongerConfiguredInManager_whenDeposited_reverts] |
| BLCOL-DEPOSIT-I06 | Borrower | Core operator deposit period 1 absent; unrelated operator period present | `BurnerLoansCore_InvalidDepositManager(DM)` | Unchanged; no committed logs | Same input/custody/cap failure with earlier preview admission satisfied; no Risk/PRICE calls or writes | Covered: [test_givenOnlyAnotherOperatorPeriod_whenDeposited_reverts][test_givenOnlyAnotherOperatorPeriod_whenDeposited_reverts] |
| BLCOL-DEPOSIT-I07 | Borrower | Core operator deposit period 1 disabled | `BurnerLoansCore_InvalidDepositManager(DM)` | Unchanged; no committed logs | Same input/custody/cap failure with earlier preview admission satisfied; no Risk/PRICE calls or writes | Covered: [test_givenCoreDepositPeriodDisabled_whenDeposited_reverts][test_givenCoreDepositPeriodDisabled_whenDeposited_reverts] |
| BLCOL-DEPOSIT-I08 | Borrower | minimum>1; fuzz amount in 1..minimum-1; seed 1 and minimum-1 | `AssetManager_MinimumDepositNotMet(asset,amount,minimum)` | Unchanged; no committed logs | Same AssetManager_MinimumDepositNotMet(asset,amount,minimum) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenMinimumDeposit_whenInputBelowMinimum_reverts][test_givenMinimumDeposit_whenInputBelowMinimum_reverts], [test_givenMinimumDeposit_whenImmediatelyBelowMinimum_reverts][test_givenMinimumDeposit_whenImmediatelyBelowMinimum_reverts], [test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree][test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree] |

With originations disabled, deposits remain permitted for new collateral-only positions and existing positions, with or without debt. A deposit does not create borrowing authority or re-enable originations. Borrowing and extension retain their separate restrictions; policy pauses, DepositManager limits and solvency requirements still apply. Retired `BLCOL-DEPOSIT-I03` and `BLCOL-DEPOSIT-I09` rejected deposits based on originations; `BLCOL-DEPOSIT-P15` specifies new-position success. `BLCOL-DEPOSIT-P11` remains retired.

## Numeric boundaries and credit

Vault previews use the current conversion rate. Rounded deposits can themselves change that rate: the fixed initial-vault regression quotes 1998 units and settles 1999 units. Those values are checked independently; quote/execution equality is asserted when conversion is stable. Actual settled credit remains authoritative for positions, receipts and liabilities.

Let A be the requested deposit, Q DepositManager’s actual credited amount and C prior FLOAN collateral. Assert returned credit=Q, returned collateral=C+Q and stored FLOAN collateral=C+Q in every successful case. Assert collateral delta=Q, Core operator receipt/liability deltas=Q and unchanged debt. The event records requested A separately from credited Q. Whenever Q differs from A, explicitly assert that the position was not credited by A.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-N01 | Borrower | Direct payout; no prior position; fuzz amount max(1,minimum)..MAX128, actual credit Q=amount fits cap room and representable aggregate; seed minimum, 1 when valid, MAX128 | `Return (amount,amount,H)` | Payer→Core→DM; Core receipt balance and liabilities +amount; new FLOAN collateral=amount; action CollateralDeposited | Independently quote (A,A); compare credit and total collateral with execution; no health output, Risk/PRICE call or writes | Covered: [test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree][test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree], [test_whenOneUnitDeposited_thenFullCredit][test_whenOneUnitDeposited_thenFullCredit], [test_whenMaximumDeposited_thenAllReturnsAndCustodyAgree][test_whenMaximumDeposited_thenAllReturnsAndCustodyAgree], [test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree][test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree] |
| BLCOL-DEPOSIT-N02 | Borrower | Direct payout; existing collateral C; fuzz positive amount through min(actualCreditCapRoom,MAX128-C); direct payout has Q=amount | `Return (amount,C+amount,H)` | Only selected position/receipt/operator accounting increases | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition][test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition], [test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached][test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached] |
| BLCOL-DEPOSIT-N03 | Borrower | Synchronous vault; fuzz positive amount with nonzero representable actual credit Q; seed Q=1 and MAX128; include reachable rounding cases `0<Q<A` | `Return (Q,C+Q,H)` | Credit Q independently derived from actual shares/conversion; returned/stored collateral=C+Q, not C+A; asset/share/receipt/liability deltas verified | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved][test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved], [test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput][test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput], [test_givenSynchronousVault_whenUnderlyingWithdrawn][test_givenSynchronousVault_whenUnderlyingWithdrawn], [test_givenSynchronousVault_whenSharesWithdrawn][test_givenSynchronousVault_whenSharesWithdrawn], [test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn][test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn], [test_givenOneVaultUnit_whenSharesWithdrawn][test_givenOneVaultUnit_whenSharesWithdrawn], [rounded credit below cap][test_givenVaultRounding_whenRawInputExceedsCapAndCreditIsBelowCap_thenAccepted], [rounded credit at cap][test_givenVaultRounding_whenRawInputExceedsCapAndCreditEqualsCap_thenAccepted], [test_givenNonUnitVaultRate_whenDepositedAcrossFullRange_thenActualCreditAndCustodyAgree][test_givenNonUnitVaultRate_whenDepositedAcrossFullRange_thenActualCreditAndCustodyAgree], [test_givenExistingVaultCollateral_whenToppedUpAcrossFullRange_thenActualCreditAddsOnce][test_givenExistingVaultCollateral_whenToppedUpAcrossFullRange_thenActualCreditAddsOnce], [test_givenNonUnitVaultRate_whenCreditIsOne_thenAllReturnsAndCustodyAgree][test_givenNonUnitVaultRate_whenCreditIsOne_thenAllReturnsAndCustodyAgree], [test_givenNonUnitVaultRate_whenCreditIsMaximum_thenAllReturnsAndCustodyAgree][test_givenNonUnitVaultRate_whenCreditIsMaximum_thenAllReturnsAndCustodyAgree] |
| BLCOL-DEPOSIT-N04 | Borrower | Raw amount > deposit cap room; vault credit Q < remaining cap room | `Success` | Cap checks converted Q; returned/stored collateral=C+Q, not C+A; receipt/liability deltas=Q | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenVaultRounding_whenRawInputExceedsCapAndCreditIsBelowCap_thenAccepted][test_givenVaultRounding_whenRawInputExceedsCapAndCreditIsBelowCap_thenAccepted] |
| BLCOL-DEPOSIT-N05 | Borrower | Actual credit Q exactly remaining deposit cap room | `Success` | Utilization reaches exact configured cap | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenExactDepositCapRoom_whenDeposited_thenCapReached][test_givenExactDepositCapRoom_whenDeposited_thenCapReached], [test_givenVaultRounding_whenRawInputExceedsCapAndCreditEqualsCap_thenAccepted][test_givenVaultRounding_whenRawInputExceedsCapAndCreditEqualsCap_thenAccepted] |
| BLCOL-DEPOSIT-N06 | Borrower | Finite cap room R<MAX128; fuzz reachable vault credit Q in R+1..MAX128; seed R+1 and MAX128; all prior validations pass | `AssetManager_DepositCapExceeded(asset,utilization,cap)` | Unchanged; no committed logs | Same input/custody/cap failure with earlier preview admission satisfied; no Risk/PRICE calls or writes | Covered: [test_givenDepositCap_whenActualCreditExceedsCap_reverts][test_givenDepositCap_whenActualCreditExceedsCap_reverts], [test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback][test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback], [test_givenVaultCap_whenOneOverRoom_thenBothPathsReject][test_givenVaultCap_whenOneOverRoom_thenBothPathsReject], [test_givenVaultCapZero_whenMaximumCredit_thenBothPathsReject][test_givenVaultCapZero_whenMaximumCredit_thenBothPathsReject] |
| BLCOL-DEPOSIT-N07 | Borrower | Existing C<=MAX128; positive actual Q<=MAX128; C+Q>MAX128; seed C=MAX128,Q=1; DM aggregate/cap otherwise valid | Current FLOAN uint128 collateral addition reverts Panic(0x11) | Full DM/receipt/token and position rollback; no committed logs | Revert for the same unrepresentable resulting collateral as execution; the uint256 quote must respect the uint128 position bound | Covered: [test_givenMaximumCollateral_whenAnotherUnitDeposited_thenSameOverflowAndRollback][test_givenMaximumCollateral_whenAnotherUnitDeposited_thenSameOverflowAndRollback], [test_givenExistingCollateral_whenTopUpOverflowsUint128_thenBothPathsRollBack][test_givenExistingCollateral_whenTopUpOverflowsUint128_thenBothPathsRollBack] |
| BLCOL-DEPOSIT-P15 | Borrower or authorized operator | originationsEnabled=false; no canonical position; direct custody Q=amount; fuzz amount max(1,minimum)..MAX128 within deposit-cap room; seed minimum, 1 when valid and MAX128 | Return (Q,Q,MAX256) | Create one collateral-only position; credit Q to FLOAN and Core receipts/liabilities; actual caller funds the deposit; principal stays zero; emit CollateralDeposited; originations remain disabled | Independently quote (Q,Q); no position creation, Risk/PRICE call or writes | Covered: [test_givenOriginationsDisabled_whenBorrowerFirstDeposits][test_givenOriginationsDisabled_whenBorrowerFirstDeposits], [test_givenOriginationsDisabled_whenOperatorFirstDeposits][test_givenOriginationsDisabled_whenOperatorFirstDeposits], [test_givenOriginationsDisabled_whenFirstDepositAmountSeeds][test_givenOriginationsDisabled_whenFirstDepositAmountSeeds] |
| BLCOL-DEPOSIT-P12 | Borrower | originationsEnabled=false; existing collateral-only position C, including C=0; actual credit Q>0 | Return (Q,C+Q,MAX256) | Existing position credited once by Q; no new position or debt | Quote (Q,C+Q); no health output, Risk/PRICE call or writes | Covered: [test_givenOriginationsDisabled_givenDebtFreePosition_whenTopUpQuoted_thenCreditReturned][test_givenOriginationsDisabled_givenDebtFreePosition_whenTopUpQuoted_thenCreditReturned], [test_givenOriginationsDisabled_givenDebtFreePosition_whenToppedUp_thenExistingPositionCredited][test_givenOriginationsDisabled_givenDebtFreePosition_whenToppedUp_thenExistingPositionCredited], [test_givenOriginationsDisabled_givenEmptyPosition_whenTopUpQuoted_thenExistenceAllowsDeposit][test_givenOriginationsDisabled_givenEmptyPosition_whenTopUpQuoted_thenExistenceAllowsDeposit], [test_givenOriginationsDisabled_givenEmptyPosition_whenToppedUp_thenSamePositionReused][test_givenOriginationsDisabled_givenEmptyPosition_whenToppedUp_thenSamePositionReused] |
| BLCOL-DEPOSIT-P13 | Borrower | originationsEnabled=false; existing debt D>0 and collateral C; mock Risk returns H<1e18 after actual Q credit | Return (Q,C+Q,H); succeeds | Actual Q added; debt/expiry unchanged; partial health-improving top-up allowed | Quote (Q,C+Q) under stable conversion; do not read Risk or return H; execution still reports partial health improvement | Covered: [test_givenOriginationsDisabled_givenUnhealthyDebt_whenPartialTopUpQuoted][test_givenOriginationsDisabled_givenUnhealthyDebt_whenPartialTopUpQuoted], [test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenPartialImprovementAllowed][test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenPartialImprovementAllowed] |
| BLCOL-DEPOSIT-P14 | Borrower | originationsEnabled=false; existing debt-bearing position; mock pre-deposit health=0.9e18 and post-deposit health=1.2e18 for actual credit Q | Return (Q,C+Q,1.2e18) | Actual Q credited once; debt/expiry unchanged; top-up restores health above liquidation threshold | Quote (Q,C+Q) under stable conversion; no health output or pricing call; execution alone reports 1.2e18 health | Covered: [test_givenOriginationsDisabled_givenUnhealthyDebt_whenCuringTopUpQuoted][test_givenOriginationsDisabled_givenUnhealthyDebt_whenCuringTopUpQuoted], [test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenHealthCuredWithoutNewDebt][test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenHealthCuredWithoutNewDebt] |

## Transfer and custody failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-T01 | Borrower | Payer token transferFrom returns false | `SafeERC20FailedOperation(asset)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_whenTransferFromReturnsFalse_thenNoCredit][test_whenTransferFromReturnsFalse_thenNoCredit] |
| BLCOL-DEPOSIT-T02 | Borrower | Payer token transferFrom reverts with a configured custom token error | `Exact configured token error` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_whenTransferFromReverts_thenExactErrorAndNoCredit][test_whenTransferFromReverts_thenExactErrorAndNoCredit] |
| BLCOL-DEPOSIT-T03 | Borrower | Core receives less than amount; seed pre-existing Core surplus separately | `SafeERC20Exact_InexactTransferFrom(asset,Core,amount,received)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenInexactCoreReceipt_whenDeposited_reverts][test_givenInexactCoreReceipt_whenDeposited_reverts], [test_givenPreexistingCoreSurplus_whenIncomingReceiptIsShort_reverts][test_givenPreexistingCoreSurplus_whenIncomingReceiptIsShort_reverts] |
| BLCOL-DEPOSIT-T04 | Borrower | One representative over-receipt from Core transferFrom; shared SafeERC20Exact compatibility case | `SafeERC20Exact_InexactTransferFrom(asset,Core,amount,received)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenIncomingOverReceipt_whenDeposited_thenExactTransferBoundaryRejects][test_givenIncomingOverReceipt_whenDeposited_thenExactTransferBoundaryRejects] |
| BLCOL-DEPOSIT-T05 | Borrower | Vault reports minted shares different from the DM share-balance delta | `AssetManager_InexactSharesReceived(asset,shareToken,expected,actual)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenVaultMisreportsShares_whenDeposited_thenReceiptDeltaEnforced][test_givenVaultMisreportsShares_whenDeposited_thenReceiptDeltaEnforced] |
| BLCOL-DEPOSIT-T06 | Borrower | ReceiptTokenManager refuses Core burn approval | `BurnerLoansCore_ReceiptApprovalFailed(manager)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenReceiptBurnApprovalRejected_whenDeposited_thenFullRollback][test_givenReceiptBurnApprovalRejected_whenDeposited_thenFullRollback] |
| BLCOL-DEPOSIT-T07 | Borrower | DepositManager injected post-pull deposit failure | `MockDepositManager_TransferFailed()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenCoreIncomingPull_whenDepositManagerRejects_thenPullRollsBack][test_givenCoreIncomingPull_whenDepositManagerRejects_thenPullRollsBack] |
| BLCOL-DEPOSIT-T08 | Borrower | DepositManager returns actual collateral credit=0 | `BurnerLoansCore_ZeroCollateralCredit()` | Unchanged; no committed logs | Revert ZeroCollateralCredit when projected credit is zero; distinguish later conversion changes from the quoted result | Covered: [test_givenZeroDepositManagerCredit_whenDeposited_reverts][test_givenZeroDepositManagerCredit_whenDeposited_reverts], [test_givenProjectedZeroCredit_whenPreviewed_reverts][test_givenProjectedZeroCredit_whenPreviewed_reverts] |
| BLCOL-DEPOSIT-T09 | Borrower | DepositManager returns credit>MAX128; fuzz MAX128+1..MAX256; seed both endpoints | `SafeCastOverflowedUintDowncast(128,credit)` | Unchanged; no committed logs | Projected credit>MAX128 rejects SafeCastOverflowedUintDowncast(128,Q) in LoanCustody; execution also rejects oversized actual credit; isolate projection versus actual receipt | Covered: [test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts][test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts], [test_givenOversizedActualCredit_whenDeposited_reverts][test_givenOversizedActualCredit_whenDeposited_reverts], [test_givenMaximumActualCredit_whenDeposited_reverts][test_givenMaximumActualCredit_whenDeposited_reverts], [test_givenFirstUnrepresentableCredit_whenDeposited_reverts][test_givenFirstUnrepresentableCredit_whenDeposited_reverts], [test_givenProjectedCreditEndpoints_whenPreviewed_reverts][test_givenProjectedCreditEndpoints_whenPreviewed_reverts] |

## Shared assertions

Use real DepositManager and ReceiptTokenManager for custody assertions, plus targeted boundary mocks for zero/oversized credit. Use a mock Risk for action unit tests: it supplies a named snapshot and health result, asserts the exact asset/snapshot/actual post-settlement collateral/debt arguments, and can reject an unexpected call. Risk math is tested in Risk’s own suite; the real integration cases below prove wiring. Do not use Lens as the only oracle. Compare the action preview only when unchanged vault conversion makes it comparable; borrower grants and zero-credit rejection follow the action validation; transfers are not performed by the view. Unit tests independently assert actual post-deposit state and the precise arguments sent to mock Risk, then assert its configured H is returned; D=0 uses uint256.max. Integration tests derive H independently from real prices and risk parameters. Stale cache refresh success differs from a broken refresh. Pricing failures for D>0 roll back deposits; no healthy-position threshold is imposed on a top-up.

## Interaction coverage

The transfer callback matrix below covers payer-token, DM/vault and receipt interactions separately from pre-settlement price-refresh callbacks. Test payer=borrower and payer=operator explicitly; preserve unrelated borrower, asset and operator accounting.

- [x] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Resulting health and price dependencies

Action/Core operational; borrower authorized; supported asset; all custody/cap constraints compatible. Let C be prior collateral, Q actual credit and D actual post-settlement principal. Use mock Risk throughout this unit table; assert the captured snapshot and (asset,C+Q,D) arguments rather than duplicating risk arithmetic. Borrower is the fixed caller because operator authorization is covered separately. H is WAD.

| ID | Caller | Existing debt D | Prior / resulting position | Mock Risk behavior | Return / execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-P01 | Borrower | 0 | New position; Q>0 | Mock Risk configured to revert if called | `(Q,Q,MAX256)`; no price call | Actual collateral credited; debt stays zero | Quote (Q,Q); no health output or Risk call; compare only credit and total collateral with execution | Covered: [test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree][test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree] |
| BLCOL-DEPOSIT-P02 | Borrower | 0 | Existing C; Q>0 | Mock Risk configured to revert if called | `(Q,C+Q,MAX256)` | Existing stored collateral becomes C+Q; debt stays zero | Quote (Q,C+Q); no health output or Risk call; preserve existing-position accounting | Covered: [test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition][test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition], [test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached][test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached] |
| BLCOL-DEPOSIT-P03 | Borrower | D>0 | Mock H>1e18; fuzz compatible C,Q,D and H in 1e18+1..MAX256 | Return captured snapshot and configured H | `(Q,C+Q,H)` | Health uses actual credit, unchanged debt | Quote (Q,C+Q) without Risk/PRICE calls; H is an execution-only result | Covered: [test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold][test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold], [test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff][test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff] |
| BLCOL-DEPOSIT-P04 | Borrower | D>0 | Mock H exactly1e18 | Return captured snapshot and 1e18 | `(Q,C+Q,1e18)` | No minimum-health rejection | Quote (Q,C+Q) without Risk/PRICE calls; execution alone reports H=WAD | Covered: [test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold][test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold], [test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff][test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff] |
| BLCOL-DEPOSIT-P05 | Borrower | D>0 | Positive top-up; configured H in 0..1e18-1; seed 0,1e18-1 | Return captured snapshot and configured H | `(Q,C+Q,H)`; succeeds | Helpful deposit allowed without curing the entire shortfall | Quote (Q,C+Q) without Risk/PRICE calls; execution alone reports H<WAD; partial top-up stays allowed | Covered: [test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold][test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold], [test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff][test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff], [test_givenUnhealthyDebt_whenPartialTopUpIsDeposited_thenUnhealthyHealthIsReturned][test_givenUnhealthyDebt_whenPartialTopUpIsDeposited_thenUnhealthyHealthIsReturned] |
| BLCOL-DEPOSIT-P06 | Borrower | D>0 | Positive Q; payout otherwise succeeds | refreshSnapshot reverts | Exact configured Risk error | Full rollback of position, token/receipt balances and cache writes | Quote (Q,C+Q) despite failing Risk snapshot/refresh; execution propagates its existing refresh error and rolls back | Covered: [test_givenDebt_whenSnapshotRefreshFails_thenIndependentViewAndRollback][test_givenDebt_whenSnapshotRefreshFails_thenIndependentViewAndRollback] |
| BLCOL-DEPOSIT-P07 | Borrower | D>0 | Positive Q; settlement completes before health evaluation | health reverts | Exact configured Risk error | Core/DM/FLOAN changes and emitted deposit/transfer logs all roll back | Quote (Q,C+Q) without Risk.health; execution alone propagates health failure and rolls back settlement | Covered: [test_givenDebt_whenRiskHealthFails_thenDepositRollsBack][test_givenDebt_whenRiskHealthFails_thenDepositRollsBack], [test_givenRealCacheRefresh_whenFinalHealthReportFails_thenCacheAndSettlementRollBack][test_givenRealCacheRefresh_whenFinalHealthReportFails_thenCacheAndSettlementRollBack] |

The existing shared SafeERC20Exact helper rejects over-receipt as well as short receipt. Keep one representative BL over-receipt regression; exhaustive transfer-shape coverage belongs to that helper. Relaxing it would require deciding whether excess is credited or remains Core surplus; this plan retains the existing helper semantics.

## Real Risk and pricing integration

Use a separate depositCollateralIntegration.t.sol with real Risk, pricing/cache/backing dependencies, Core, FLOAN, DepositManager and ReceiptTokenManager, using existing oracle/vault mocks only at the external feed boundary. Unit tests above do not prove risk arithmetic or cache wiring. Borrower is the fixed caller; action/Core operational; supported asset and custody otherwise compatible. Independently derive H from configured prices/decimals, actual credit and debt.

| ID | Caller | Position / custody | Real Risk / pricing state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-P08 | Borrower | D>0; existing collateral C; vault rounding gives 0<Q<A; seed below/equal/above-WAD resulting H with compatible fixtures | Fresh valid snapshot | (Q,C+Q,H) | Returned and stored collateral=C+Q; health uses Q, not A; actual receipts/liabilities +Q; debt unchanged | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenRoundedVaultCredit_whenHealthyTopUp_thenRealHealthUsesActualCredit][test_givenRoundedVaultCredit_whenHealthyTopUp_thenRealHealthUsesActualCredit], [test_givenRoundedVaultCredit_whenPartialTopUp_thenRealHealthUsesActualCredit][test_givenRoundedVaultCredit_whenPartialTopUp_thenRealHealthUsesActualCredit], [test_givenRoundedVaultCredit_whenHealthExactlyOne_thenAccepted][test_givenRoundedVaultCredit_whenHealthExactlyOne_thenAccepted] |
| BLCOL-DEPOSIT-P09 | Borrower | D>0; positive representable Q | Stale cache; real refresh succeeds | (Q,C+Q,H) using refreshed prices | Cache timestamp/prices updated; actual payout/position deltas verified | Independently quote credit and total collateral; compare the first two action results under stable conversion; no Risk/PRICE calls or writes | Covered: [test_givenRealStaleCache_whenToppedUp_thenRefreshAndCanonicalHealthAgree][test_givenRealStaleCache_whenToppedUp_thenRefreshAndCanonicalHealthAgree] |
| BLCOL-DEPOSIT-P10 | Borrower | D>0; positive representable Q | Stale cache; configured feed makes real refresh revert | Exact configured feed/PRICE error | Full rollback of collateral, receipts/liabilities, tokens and cache writes; no committed logs | Quote estimated credit and projected collateral without touching stale/failed pricing; execution retains its price-refresh failure | Covered: [test_givenRealStalePrice_whenDepositExecuted_reverts][test_givenRealStalePrice_whenDepositExecuted_reverts], [test_givenStaleRealCache_whenPriceFeedFails_reverts][test_givenStaleRealCache_whenPriceFeedFails_reverts] |

Approved deposit semantics: partial top-ups remain allowed even when returned H<1e18. No minimum-health condition is imposed on deposits. Withdrawals and borrowing retain their own health admission rules.

## Price-refresh callbacks before settlement

Core's transfer guard is not entered during Risk.refreshSnapshot. Use an operational cache callback actor, with a real unexpired borrower grant for authorized borrowing/withdrawal/extension and funded payer approvals for repayment. Do not expect a Core reentrancy error before the guard is entered.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-C01 | Borrower | Cache callback changes debt for the same authorized borrower; outer top-up reports health using actual final principal and credited collateral, without a minimum-health cure gate | Return actual credit/collateral and Risk.health for final principal; full-debt repayment returns MAX256 | Successful call reflects actual state; rejected call restores Core/FLOAN/Inventory/DM/cache balances, allowances and logs | Conversion-only credit/collateral quote; no Risk call or mutating refresh callback; compare position and credit only if callback leaves them unchanged | Covered: [test_givenCacheFullyRepays_whenTopUpSettles_thenActualDebtFreeHealthReturned][test_givenCacheFullyRepays_whenTopUpSettles_thenActualDebtFreeHealthReturned] |

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Conversion-only credit/collateral quote; no Risk call or mutating refresh callback; compare position and credit only if callback leaves them unchanged | Covered: [test_givenCaughtUnauthorizedCacheAction_whenDepositing_thenOneCredit][test_givenCaughtUnauthorizedCacheAction_whenDepositing_thenOneCredit] |
| BLCOL-DEPOSIT-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Conversion-only credit/collateral quote; no Risk call or mutating refresh callback; compare position and credit only if callback leaves them unchanged | Covered: [test_givenPropagatedUnauthorizedCacheAction_whenDepositing_thenRollback][test_givenPropagatedUnauthorizedCacheAction_whenDepositing_thenRollback] |

Retired BLCOL-DEPOSIT-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative collateral-token transfer with nonzero pre-existing accounting and an unrelated entity. Core/DepositManager/vault suites own their distinct custody boundaries; do not multiply the action case across every transfer hook or caller class. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-C05 | Borrower | Payer→Core collateral transferFrom | One authorized, funded nested public action reaches Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One outer deposit only; actual Q credited once to FLOAN and Core DM liabilities/receipts; payer funds debited once; unrelated borrower/operator unchanged | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test_givenPayerPullCallback_whenActionReentryCaught][test_givenPayerPullCallback_whenActionReentryCaught], [test_givenPayerPullCallback_whenCoreReentryCaught][test_givenPayerPullCallback_whenCoreReentryCaught], [test_givenManagerPullCallback_whenActionReentryCaught][test_givenManagerPullCallback_whenActionReentryCaught], [test_givenManagerPullCallback_whenCoreReentryCaught][test_givenManagerPullCallback_whenCoreReentryCaught], [test_givenVaultDepositCallback_whenActionReentryCaught][test_givenVaultDepositCallback_whenActionReentryCaught], [test_givenVaultDepositCallback_whenCoreReentryCaught][test_givenVaultDepositCallback_whenCoreReentryCaught], [test_givenOperatorFundedDeposit_whenCallbackCaught][test_givenOperatorFundedDeposit_whenCallbackCaught], [test_givenReceiptApprovalCallback_whenActionReentryCaught][test_givenReceiptApprovalCallback_whenActionReentryCaught], [test_givenReceiptApprovalCallback_whenCoreReentryCaught][test_givenReceiptApprovalCallback_whenCoreReentryCaught] |
| BLCOL-DEPOSIT-C06 | Borrower | Payer→Core collateral transferFrom | One authorized, funded nested public action reaches Core settlement; callback propagates the guard rejection | Exact propagated token/dependency error rejects outer operation; ReentrantFeeToken wraps its nested guard rejection as CallbackFailed() | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Quote before arming transfer callback; no token/vault/receipt transfer or callback; caught action agrees under stable economics; propagated execution failure is not predicted | Covered: [test_givenPayerPullCallback_whenActionReentryPropagated][test_givenPayerPullCallback_whenActionReentryPropagated], [test_givenPayerPullCallback_whenCoreReentryPropagated][test_givenPayerPullCallback_whenCoreReentryPropagated], [test_givenManagerPullCallback_whenActionReentryPropagated][test_givenManagerPullCallback_whenActionReentryPropagated], [test_givenManagerPullCallback_whenCoreReentryPropagated][test_givenManagerPullCallback_whenCoreReentryPropagated], [test_givenVaultDepositCallback_whenActionReentryPropagated][test_givenVaultDepositCallback_whenActionReentryPropagated], [test_givenVaultDepositCallback_whenCoreReentryPropagated][test_givenVaultDepositCallback_whenCoreReentryPropagated], [test_givenOperatorFundedDeposit_whenCallbackPropagated][test_givenOperatorFundedDeposit_whenCallbackPropagated], [test_givenReceiptApprovalCallback_whenActionReentryPropagated][test_givenReceiptApprovalCallback_whenActionReentryPropagated], [test_givenReceiptApprovalCallback_whenCoreReentryPropagated][test_givenReceiptApprovalCallback_whenCoreReentryPropagated] |

## Permissionless quote identities

| ID | Quote requester | Position owner | Execution caller / history | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-A12 | Fuzz every address; no authorization lookup allowed | Nonzero `onBehalfOf_`=B | Borrower or operator may execute later | Identical independently checked quote for B; no writes/logs or funding requirements | Covered: [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLCOL-DEPOSIT-A13 | Unrelated viewer X | B | Prospective operator O before grant, while valid, at deadline, after expiry and after revocation | Quote remains independent of O's grant while economic state is valid; execution follows grant validity | Covered: [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLCOL-DEPOSIT-A14 | Unrelated viewer X | B | B collateral=100; X collateral=50; quote deposit=7 | Credit=7; projected B collateral=107; neither position changes | Covered: [test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted][test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted] |

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-D04 | Borrower | DepositManager Kernel-inactive; otherwise valid deposit | PolicyDependency_NotActive(DepositManager) on preview and execution; custody/position unchanged | Covered: [test_givenDepositManagerInactive_whenDeposited_reverts][test_givenDepositManagerInactive_whenDeposited_reverts] |

## Backing availability regressions

Local policy and ordinary dependencies are active/enabled; callers satisfy the
existing action authorization. Each fault varies backing readiness independently.
Rejection preserves authoritative accounting, custody and emitted logs.

| ID | Scenario | Expected execution and preview | Test |
| --- | --- | --- | --- |
| BLCOL-DEPOSIT-D05 | Debt=100e9; oracle disabled; change collateral by 1e6 | Deposit preview returns (1e6,priorCollateral+1e6) without oracle calls; debt-bearing deposit execution and collateral withdrawal preview/execution retain PolicyDependency_NotActive(oracle); rejected executions preserve accounting | Covered: [test][test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement] |
| BLCOL-DEPOSIT-D06 | Debt-free collateral=100e6; oracle disabled; change collateral by 1e6 | Deposit preview returns (1e6,101e6); deposit execution retains uint256.max health; withdrawal keeps its existing output and health fields | Covered: [test][test_givenDebtFreeAndBackingPaused_whenCollateralChanged] |

## Auth completion and delegated vault rounding

| ID | Scenario | Expected behavior | Named test |
| --- | --- | --- | --- |
| BLCOL-DEPOSIT-AUTH-C01 | Account token callback cancels the captured operator pair during actual Core payer transfer | Original stamp is rejected on completion; custody, canonical state, wallet balances, callback state and pair epoch all roll back | [test][test_givenDelegatedDeposit_whenAccountCancelsDuringPayerPull_reverts] |
| BLCOL-DEPOSIT-AUTH-C02 | Account token callback accepts identical permissions at the next pair epoch | Completion cannot adopt replacement authority; complete rollback | [test][test_givenDelegatedDeposit_whenIdenticalPermissionsReacceptedDuringPayerPull_reverts] |
| BLCOL-DEPOSIT-AUTH-C03 | Unrelated callback token attempts to replace borrower authority and catches failure | Exact invalid-identity error; original grant epoch unchanged; one actual deposit settles | [test][test_givenUnauthorizedAuthCallback_whenFailureCaught_thenOriginalGrantCompletes] |
| BLCOL-DEPOSIT-AUTH-C04 | Same unauthorized replacement failure propagates | Token callback error; full custody/accounting rollback and no epoch consumption | [test][test_givenUnauthorizedAuthCallback_whenFailurePropagated_thenFullRollback] |
| BLCOL-DEPOSIT-AUTH-N01 | Nominal vault input 2000, actual credited collateral 1999, delegated resulting cap 1999 | Success; 666 custody shares and 1999 canonical liability | [test][test_givenDelegatedVaultDeposit_whenNominalExceedsGrantButActualCreditEqualsCap_thenAccepted] |
| BLCOL-DEPOSIT-AUTH-N02 | Same rounding with delegated resulting cap 1998 | Exact Core result-limit error; payer transfer, vault backing/supply, custody and accounting roll back | [test][test_givenDelegatedVaultDeposit_whenActualCreditExceedsGrant_thenFullRollback] |

## Auth rotation during preparation

| ID | Setup | Expected result | Test |
| --- | --- | --- | --- |
| BLCOL-DEPOSIT-AUTH-C05 | Owner or delegated operator; real price callback rotates A to B to A | Original captured generation rejected before settlement; pointer/epochs/custody/accounting all roll back | [rotation][test_givenPreparationCallback_whenAuthRotatesAndReturns_reverts] |

## Insolvency

These acceptance criteria cover final custody solvency through the real collateral/Core/DepositManager flow.
Use the real Core, DepositManager, ReceiptTokenManager, FLOAN and vault integration fixture.
The existing authorization, lifecycle, minimum, credit, cap, price and health rules above still apply.
Borrower B and delegated operator O are distinct; authorized O pays from its own balance.
An unrelated borrower C and an independent DepositManager operator X establish namespace isolation.

The new solvency check belongs to DepositManager after custody and liabilities update. Core must
propagate its exact `DepositManager_Insolvent(asset,Lpost,assetsPost,borrowedPost)` error.
Do not replace it with `BurnerLoansCore_Insolvent` or add a new pre-deposit guard to Core/the action.

Default: B deposits 100 raw units into an initially 1:1 vault, creating 100 shares and liabilities.
The vault then loses 20 units, so Core's recorded shares are worth 80. A further input of 8 units
mints 10 shares worth 8; candidate custody=88 and liabilities=108. Each rejection below expects
`DepositManager_Insolvent(asset,108,88,0)` unless its row changes those values.

Full rollback includes payer/Core/DM/vault underlying and share balances, allowances, receipt balances
and approvals, FLOAN positions and indexes, collateral/debt, grant usage/completion, aggregate caps,
price refresh/cache state and committed events. A failed first deposit creates no borrower position.

Preview exception: `previewDepositCollateral` returns only its snapshot conversion and total collateral.
It cannot execute a vault deposit and does not prove the final custody solvency condition.
For the stable loss fixture, it returns credit=8 and projected collateral=108 for B, despite the
execution rejection. For a new borrower C, projected collateral is 8. No health value is returned.
No preview authorization, funding, pricing or solvency precheck is added. This exception is part of sign-off.

| ID | Caller | Position / namespace | Deposit input or transition | Execution and authoritative effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOL-DEPOSIT-T10 | B | Existing B collateral=100; Core custody has the default loss | A=8 | Exact DM insolvency error; full rollback; B keeps A and no collateral credit survives | Quote credit=8,total=108; no health output; final solvency remains execution-only | Covered: [test][test_givenVaultLoss_whenExistingBorrowerDeposits_reverts], [test][test_givenVaultLossAndOriginationsDisabled_whenExistingBorrowerDeposits_reverts], [test][test_givenVaultLoss_whenExistingBorrowerDeposits_thenFinalInsolvencyRollsBack] |
| BLCOL-DEPOSIT-T11 | C, a first-time borrower | B's loss makes the shared Core namespace insolvent; C has no position | A=8 | Same exact DM insolvency error; full rollback; C's position/index remains absent | Quote credit=8,total=8; no health output; final solvency remains execution-only | Covered: [test][test_givenVaultLoss_whenNewBorrowerDeposits_reverts], [test][test_givenVaultLossAndOriginationsDisabled_whenNewBorrowerDeposits_reverts] |
| BLCOL-DEPOSIT-T12 | Authorized O for B | Valid current grant and sufficient remaining cap; default loss | A=8 funded by O | Same exact DM error; O's funds/allowance and B's grant usage/completion unchanged | Permissionless viewer receives B's credit/collateral quote without grant or Risk/PRICE read | Covered: [test][test_givenVaultLoss_whenAuthorizedOperatorDeposits_reverts] |
| BLCOL-DEPOSIT-T13 | B | Debt-bearing position; working Risk and refreshing price cache; namespace insolvent | Valid top-up after price refresh | Exact final DM insolvency error; include cache refresh in full rollback; no health threshold substitutes for custody solvency | Quote estimated credit and total collateral without pricing; execution separately refreshes prices and checks final custody | Covered: [test][test_givenDebtAndVaultLoss_whenTopUpRefreshesCache_reverts] |
| BLCOL-DEPOSIT-N08 | B | Fixed real-vault fixture ends one raw unit short of liabilities after deposit | Small deterministic A chosen for exact conversion | DM error includes final one-unit deficit; full rollback | Conversion/total-collateral estimate only; no health output | Covered: [test][test_givenOneUnitDeficit_whenCollateralDeposited_reverts] |
| BLCOL-DEPOSIT-T14 | B | Namespace starts solvent | Deposit callback realizes enough vault loss to make final state insolvent | DM final-state error; rollback callback loss and all settlement effects | Pre-call quote cannot predict mutation | Covered: [test][test_givenSolventCustody_whenVaultRealizesLossDuringDeposit_reverts] |
| BLCOL-DEPOSIT-P16 | B | Permissionless donor supplies 8 underlying to Core's namespace; custody becomes 88 against L=100 | Subsequent A=8 -> candidate custody=96,L=108 | `DepositManager_Insolvent(asset,108,96,0)`; prior donation persists; top-up fully rolls back | Stable quote remains an estimate | Covered: [test][test_givenPartialDonation_whenBorrowerDeposits_reverts] |
| BLCOL-DEPOSIT-P17 | B | Donor supplies 20 underlying to Core's namespace; custody=L=100 | A=8, then withdraw the 108 recorded collateral using a funded, debt-free position | Deposit credits exactly 8; existing plus new collateral exits for 108 underlying units; donation creates no FLOAN collateral or receipts | Quote matches actual top-up after repair; stable withdrawal quote agrees | Covered: [test][test_givenFullDonation_whenBorrowerDepositsAndWithdraws] |
| BLCOL-DEPOSIT-P18 | B | Vault exchange rate below one but Core's assets cover liabilities; separate healthy starting fixture | Valid nonzero top-up | Deposit succeeds; independent custody/receipts/FLOAN credit and health agree | Stable quote matches actual conversion | Covered: [test][test_givenSolventCustodyBelowUnitExchangeRate_whenBorrowerDeposits] |
| BLCOL-DEPOSIT-P19 | B | Unhealthy individual loan; Core custody remains solvent | Partial helpful top-up leaves health below 1e18 | Deposit succeeds; retain existing partial-improvement behavior, with actual credit and debt preserved | Stable quote matches actual credit and collateral; execution alone reports resulting health | Covered: [test][test_givenUnhealthyDebt_whenPartialTopUpIsDeposited_thenUnhealthyHealthIsReturned] |
| BLCOL-DEPOSIT-P20 | B | Same asset in independent operator X is insolvent; Core namespace solvent | Valid Core top-up | Deposit succeeds; no lookup or accounting mutation in X | Stable quote matches actual credit | Covered: [test][test_givenOtherOperatorInsolvent_whenCoreDeposits] |
| BLCOL-DEPOSIT-T15 | B | Separate ERC-7575 share token and asynchronous-redemption vault, each with real loss; guarantee both variants | Valid synchronous-deposit top-up | Exact DM insolvency error; no redemption call; full rollback through Core | Use live supported conversion path; estimate only | Covered: [test][test_givenSeparateShareVaultLoss_whenBorrowerDeposits_reverts], [test][test_givenAsyncRedemptionVaultLoss_whenBorrowerDeposits_reverts] |
| BLCOL-DEPOSIT-P21 | B | Core owns all 100 vault shares and has L=100; backing=99 after loss; B is debt-free | A=2 -> S=2,Q=floor(2*101/102)=1 | Deposit succeeds through action and Core; custody=L=101; B collateral=101; payer spends 2; no precheck prevents full rounding repair | Quote credit=1,total=101; no health output or pre-deposit solvency guard | Covered: [test][test_givenOneUnitLoss_whenDepositRoundingRepairsCustody] |

Repeat T10/T11 with originations disabled while ordinary collateral deposits remain permitted.
Use otherwise authorized callers and usable dependencies; the deficit must reach the new DM check.
These integration cases supplement the full donation/custody scenarios in
[DepositManager.donate](../DepositManager/donate.md) and
[DepositManager.deposit](../DepositManager/deposit.md). They do not duplicate DM's token failure matrix.

[test_givenActionKernelGetterReverts_whenDeposited_thenGetterIsNotRead]: depositCollateral.t.sol#L1113
[test_whenDepositQuoted_thenOnlyCreditAndCollateralReturned]: ./depositCollateral.t.sol#L43
[test_givenDebtAndPricingUnavailable_whenDepositQuoted_thenNoPricingRead]: ./depositCollateral.t.sol#L55
[test_givenVaultLoss_whenExistingBorrowerDeposits_thenFinalInsolvencyRollsBack]: ./depositCollateralIntegration.t.sol#L65
[test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected]: depositCollateral.t.sol#L1503
[test_givenAssetNoLongerConfiguredInManager_whenDeposited_reverts]: depositCollateral.t.sol#L745
[test_givenAuthorizationExpired_whenOperatorDeposits_reverts]: depositCollateral.t.sol#L568
[test_givenCacheFullyRepays_whenTopUpSettles_thenActualDebtFreeHealthReturned]: depositCollateralPriceCallbacks.t.sol#L58
[test_givenCancelledGrant_whenOperatorActs_reverts]: depositCollateral.t.sol#L1017
[test_givenCaughtUnauthorizedCacheAction_whenDepositing_thenOneCredit]: depositCollateralPriceCallbacks.t.sol#L106
[test_givenCoreDepositPeriodDisabled_whenDeposited_reverts]: depositCollateral.t.sol#L782
[test_givenCoreIncomingPull_whenDepositManagerRejects_thenPullRollsBack]: depositCollateral.t.sol#L972
[test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified]: depositCollateral.t.sol#L1075
[test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition]: depositCollateral.t.sol#L1154
[test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold]: depositCollateral.t.sol#L1130
[test_givenDebt_whenRiskHealthFails_thenDepositRollsBack]: depositCollateral.t.sol#L531
[test_givenDebt_whenSnapshotRefreshFails_thenIndependentViewAndRollback]: depositCollateral.t.sol#L666
[test_givenDepositCap_whenActualCreditExceedsCap_reverts]: depositCollateral.t.sol#L461
[test_givenDepositManagerDisabled_whenDeposited_reverts]: depositCollateral.t.sol#L739
[test_givenDepositManagerInactive_whenDeposited_reverts]: depositCollateral.t.sol#L727
[test_givenDisabledAction_whenInvoked_thenLocalPauseWins]: depositCollateral.t.sol#L1063
[test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins]: depositCollateral.t.sol#L1383
[test_givenExactDepositCapRoom_whenDeposited_thenCapReached]: depositCollateral.t.sol#L809
[test_givenExistingCollateral_whenTopUpOverflowsUint128_thenBothPathsRollBack]: depositCollateral.t.sol#L1519
[test_givenDelegatedDeposit_whenAccountCancelsDuringPayerPull_reverts]: depositCollateralCallbacks.t.sol#L210
[test_givenDelegatedDeposit_whenIdenticalPermissionsReacceptedDuringPayerPull_reverts]: depositCollateralCallbacks.t.sol#L215
[test_givenDelegatedVaultDeposit_whenActualCreditExceedsGrant_thenFullRollback]: depositCollateralIntegration.t.sol#L386
[test_givenDelegatedVaultDeposit_whenNominalExceedsGrantButActualCreditEqualsCap_thenAccepted]: depositCollateralIntegration.t.sol#L357
[test_givenExistingVaultCollateral_whenToppedUpAcrossFullRange_thenActualCreditAddsOnce]: depositCollateralIntegration.t.sol#L453
[test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized]: depositCollateral.t.sol#L1493
[test_givenExpiredGrant_whenOperatorActs_reverts]: depositCollateral.t.sol#L1028
[test_givenExpiredGrant_whenUnrelatedViewerQuotes]: depositCollateral.t.sol#L1604
[test_givenFirstUnrepresentableCredit_whenDeposited_reverts]: depositCollateral.t.sol#L1480
[test_givenGrantDeadline_whenUnrelatedViewerQuotes]: depositCollateral.t.sol#L1595
[test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified]: depositCollateral.t.sol#L1046
[test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins]: depositCollateral.t.sol#L1366
[test_givenIncomingOverReceipt_whenDeposited_thenExactTransferBoundaryRejects]: depositCollateral.t.sol#L626
[test_givenInexactCoreReceipt_whenDeposited_reverts]: depositCollateral.t.sol#L486
[test_givenManagerPullCallback_whenActionReentryCaught]: depositCollateralCallbacks.t.sol#L59
[test_givenManagerPullCallback_whenActionReentryPropagated]: depositCollateralCallbacks.t.sol#L75
[test_givenManagerPullCallback_whenCoreReentryCaught]: depositCollateralCallbacks.t.sol#L67
[test_givenManagerPullCallback_whenCoreReentryPropagated]: depositCollateralCallbacks.t.sol#L84
[test_givenMaximumActualCredit_whenDeposited_reverts]: depositCollateral.t.sol#L1347
[test_givenMaximumCollateral_whenAnotherUnitDeposited_thenSameOverflowAndRollback]: depositCollateral.t.sol#L589
[test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed]: depositCollateral.t.sol#L1236
[test_givenMaximumVaultCredit_whenFullyWithdrawn_thenFullWidthUnitsPreserved]: withdrawCollateralIntegration.t.sol#L218
[test_givenMaximumVaultCredit_whenUnderlyingFullyWithdrawn]: withdrawCollateralIntegration.t.sol#L515
[test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree]: depositCollateral.t.sol#L1317
[test_givenMinimumDeposit_whenImmediatelyBelowMinimum_reverts]: depositCollateral.t.sol#L1301
[test_givenMinimumDeposit_whenInputBelowMinimum_reverts]: depositCollateral.t.sol#L788
[test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached]: depositCollateral.t.sol#L1189
[test_givenNoGrant_whenUnrelatedViewerQuotes]: depositCollateral.t.sol#L1576
[test_givenNonUnitVaultRate_whenCreditIsMaximum_thenAllReturnsAndCustodyAgree]: depositCollateralIntegration.t.sol#L470
[test_givenNonUnitVaultRate_whenCreditIsOne_thenAllReturnsAndCustodyAgree]: depositCollateralIntegration.t.sol#L463
[test_givenNonUnitVaultRate_whenDepositedAcrossFullRange_thenActualCreditAndCustodyAgree]: depositCollateralIntegration.t.sol#L441
[test_givenOneRawVaultUnit_whenWithdrawn_thenExactOutput]: withdrawCollateralIntegration.t.sol#L223
[test_givenOneVaultUnit_whenSharesWithdrawn]: withdrawCollateralIntegration.t.sol#L520
[test_givenOnlyAnotherOperatorPeriod_whenDeposited_reverts]: depositCollateral.t.sol#L759
[test_givenOperatorFundedDeposit_whenCallbackCaught]: depositCollateralCallbacks.t.sol#L127
[test_givenOperatorFundedDeposit_whenCallbackPropagated]: depositCollateralCallbacks.t.sol#L135
[test_givenOperatorGrant_whenAtDeadline_thenDepositSucceeds]: depositCollateral.t.sol#L1228
[test_givenOperatorGrant_whenBeforeDeadline_thenAllDepositEffectsAgree]: depositCollateral.t.sol#L1215
[test_givenOriginationsDisabled_givenDebtFreePosition_whenTopUpQuoted_thenCreditReturned]: depositCollateral.t.sol#L263
[test_givenOriginationsDisabled_givenDebtFreePosition_whenToppedUp_thenExistingPositionCredited]: depositCollateral.t.sol#L273
[test_givenOriginationsDisabled_givenEmptyPosition_whenTopUpQuoted_thenExistenceAllowsDeposit]: depositCollateral.t.sol#L283
[test_givenOriginationsDisabled_givenEmptyPosition_whenToppedUp_thenSamePositionReused]: depositCollateral.t.sol#L293
[test_givenOriginationsDisabled_givenUnhealthyDebt_whenCuringTopUpQuoted]: depositCollateral.t.sol#L323
[test_givenOriginationsDisabled_givenUnhealthyDebt_whenPartialTopUpQuoted]: depositCollateral.t.sol#L303
[test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenHealthCuredWithoutNewDebt]: depositCollateral.t.sol#L333
[test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenPartialImprovementAllowed]: depositCollateral.t.sol#L313
[test_givenOriginationsDisabled_whenBorrowerFirstDeposits]: depositCollateral.t.sol#L184
[test_givenOriginationsDisabled_whenFirstDepositAmountSeeds]: depositCollateral.t.sol#L207
[test_givenOriginationsDisabled_whenOperatorFirstDeposits]: depositCollateral.t.sol#L195
[test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts]: depositCollateral.t.sol#L999
[test_givenOversizedActualCredit_whenDeposited_reverts]: depositCollateral.t.sol#L1326
[test_givenPayerPullCallback_whenActionReentryCaught]: depositCollateralCallbacks.t.sol#L25
[test_givenPayerPullCallback_whenActionReentryPropagated]: depositCollateralCallbacks.t.sol#L41
[test_givenPayerPullCallback_whenCoreReentryCaught]: depositCollateralCallbacks.t.sol#L33
[test_givenPayerPullCallback_whenCoreReentryPropagated]: depositCollateralCallbacks.t.sol#L50
[test_givenPreexistingCoreSurplus_whenIncomingReceiptIsShort_reverts]: depositCollateral.t.sol#L1273
[test_givenPreparationCallback_whenAuthRotatesAndReturns_reverts]: depositCollateralPriceCallbacks.t.sol#L24
[test_givenProjectedCreditEndpoints_whenPreviewed_reverts]: depositCollateral.t.sol#L1485
[test_givenProjectedZeroCredit_whenPreviewed_reverts]: depositCollateral.t.sol#L931
[test_givenPropagatedUnauthorizedCacheAction_whenDepositing_thenRollback]: depositCollateralPriceCallbacks.t.sol#L124
[test_givenReEnabledAction_whenDeposited_thenOperational]: depositCollateral.t.sol#L1352
[test_givenReactivatedAction_whenDeposited_thenOperational]: depositCollateral.t.sol#L1359
[test_givenRealCacheRefresh_whenFinalHealthReportFails_thenCacheAndSettlementRollBack]: depositCollateralIntegration.t.sol#L502
[test_givenRealStaleCache_whenToppedUp_thenRefreshAndCanonicalHealthAgree]: depositCollateralIntegration.t.sol#L227
[test_givenRealStalePrice_whenDepositExecuted_reverts]: depositCollateralIntegration.t.sol#L273
[test_givenReceiptApprovalCallback_whenActionReentryCaught]: depositCollateralCallbacks.t.sol#L144
[test_givenReceiptApprovalCallback_whenActionReentryPropagated]: depositCollateralCallbacks.t.sol#L167
[test_givenReceiptApprovalCallback_whenCoreReentryCaught]: depositCollateralCallbacks.t.sol#L185
[test_givenReceiptApprovalCallback_whenCoreReentryPropagated]: depositCollateralCallbacks.t.sol#L200
[test_givenReceiptBurnApprovalRejected_whenDeposited_thenFullRollback]: depositCollateral.t.sol#L891
[test_givenReportedKernelMismatch_whenDeposited_thenGetterIsNotRead]: depositCollateral.t.sol#L1101
[test_givenRevokedGrant_whenUnrelatedViewerQuotes]: depositCollateral.t.sol#L1617
[test_givenRoundedVaultCredit_whenHealthExactlyOne_thenAccepted]: depositCollateralIntegration.t.sol#L204
[test_givenRoundedVaultCredit_whenHealthyTopUp_thenRealHealthUsesActualCredit]: depositCollateralIntegration.t.sol#L102
[test_givenRoundedVaultCredit_whenPartialTopUp_thenRealHealthUsesActualCredit]: depositCollateralIntegration.t.sol#L108
[test_givenSettlementRoleRevoked_whenDepositing_thenBothPathsReject]: depositCollateral.t.sol#L1263
[test_givenStaleRealCache_whenPriceFeedFails_reverts]: depositCollateralIntegration.t.sol#L481
[test_givenSynchronousVault_whenSharesWithdrawn]: withdrawCollateralIntegration.t.sol#L507
[test_givenSynchronousVault_whenUnderlyingWithdrawn]: withdrawCollateralIntegration.t.sol#L499
[test_givenUnauthorizedAuthCallback_whenFailureCaught_thenOriginalGrantCompletes]: depositCollateralCallbacks.t.sol#L262
[test_givenUnauthorizedAuthCallback_whenFailurePropagated_thenFullRollback]: depositCollateralCallbacks.t.sol#L305
[test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins]: depositCollateral.t.sol#L1399
[test_givenUnhealthyDebt_whenPartialTopUpIsDeposited_thenUnhealthyHealthIsReturned]: depositCollateralIntegration.t.sol#L307
[test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts]: depositCollateral.t.sol#L949
[test_givenValidGrant_whenUnrelatedViewerQuotes]: depositCollateral.t.sol#L1587
[test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff]: depositCollateral.t.sol#L1415
[test_givenVaultCapZero_whenMaximumCredit_thenBothPathsReject]: depositCollateralIntegration.t.sol#L219
[test_givenVaultCap_whenOneOverRoom_thenBothPathsReject]: depositCollateralIntegration.t.sol#L211
[test_givenVaultDepositCallback_whenActionReentryCaught]: depositCollateralCallbacks.t.sol#L93
[test_givenVaultDepositCallback_whenActionReentryPropagated]: depositCollateralCallbacks.t.sol#L109
[test_givenVaultDepositCallback_whenCoreReentryCaught]: depositCollateralCallbacks.t.sol#L101
[test_givenVaultDepositCallback_whenCoreReentryPropagated]: depositCollateralCallbacks.t.sol#L118
[test_givenVaultDepositCap_whenActualCreditExceedsRoom_thenFullRollback]: depositCollateralIntegration.t.sol#L159
[test_givenVaultMisreportsShares_whenDeposited_thenReceiptDeltaEnforced]: depositCollateralIntegration.t.sol#L114
[test_givenVaultRounding_whenRawInputExceedsCapAndCreditEqualsCap_thenAccepted]: depositCollateralIntegration.t.sol#L350
[test_givenVaultRounding_whenRawInputExceedsCapAndCreditIsBelowCap_thenAccepted]: depositCollateralIntegration.t.sol#L343
[test_givenZeroDepositManagerCredit_whenDeposited_reverts]: depositCollateral.t.sol#L513
[test_whenAmountIsZero_reverts]: depositCollateral.t.sol#L146
[test_whenAnyViewerQuotesWithoutAuthorizationRead]: depositCollateral.t.sol#L1542
[test_whenAssetIsUnregistered_reverts]: depositCollateral.t.sol#L155
[test_whenBorrowerIsZero_thenPreviewAndExecutionReject]: depositCollateral.t.sol#L1247
[test_whenCallerIsUnauthorized_reverts]: depositCollateral.t.sol#L455
[test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree]: depositCollateral.t.sol#L1197
[test_whenMaximumDeposited_thenAllReturnsAndCustodyAgree]: depositCollateral.t.sol#L1210
[test_whenOneUnitDeposited_thenFullCredit]: depositCollateral.t.sol#L1205
[test_whenTransferFromReturnsFalse_thenNoCredit]: depositCollateral.t.sol#L831
[test_whenTransferFromReverts_thenExactErrorAndNoCredit]: depositCollateral.t.sol#L862
[test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted]: depositCollateral.t.sol#L1631
[test_whenZeroAsset_thenExactRegistrationError]: depositCollateral.t.sol#L1537
[test_givenDebtAndBackingPaused_whenCollateralChanged_revertsWithoutSettlement]: ./depositCollateral.t.sol#L1647
[test_givenDebtFreeAndBackingPaused_whenCollateralChanged]: ./depositCollateral.t.sol#L1686
[test_whenAnyViewerQuotesCompatibleCollateral]: ./depositCollateral.t.sol#L74
[test_whenDepositQuoteMaximumSeeds]: ./depositCollateral.t.sol#L85
[test_givenExistingCollateral_whenDepositQuoteReachesMaximum]: ./depositCollateral.t.sol#L90
[test_givenDebtAndRiskSnapshotUnavailable_whenDepositQuoted]: ./depositCollateral.t.sol#L120
[test_givenDebtAndRiskPointerUnavailable_whenDepositQuoted]: ./depositCollateral.t.sol#L133
[test_givenDebtAndPriceCachePaused_whenCollateralDeposited]: ./depositCollateralIntegration.t.sol#L34
[test_givenVaultLoss_whenExistingBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L30
[test_givenVaultLossAndOriginationsDisabled_whenExistingBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L38
[test_givenVaultLoss_whenNewBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L49
[test_givenVaultLossAndOriginationsDisabled_whenNewBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L58
[test_givenVaultLoss_whenAuthorizedOperatorDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L68
[test_givenDebtAndVaultLoss_whenTopUpRefreshesCache_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L107
[test_givenOneUnitDeficit_whenCollateralDeposited_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L148
[test_givenSolventCustody_whenVaultRealizesLossDuringDeposit_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L158
[test_givenPartialDonation_whenBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L175
[test_givenFullDonation_whenBorrowerDepositsAndWithdraws]: ./depositCollateralInsolvencyIntegration.t.sol#L194
[test_givenSolventCustodyBelowUnitExchangeRate_whenBorrowerDeposits]: ./depositCollateralInsolvencyIntegration.t.sol#L229
[test_givenOtherOperatorInsolvent_whenCoreDeposits]: ./depositCollateralInsolvencyIntegration.t.sol#L250
[test_givenSeparateShareVaultLoss_whenBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L279
[test_givenAsyncRedemptionVaultLoss_whenBorrowerDeposits_reverts]: ./depositCollateralInsolvencyIntegration.t.sol#L284
[test_givenOneUnitLoss_whenDepositRoundingRepairsCustody]: ./depositCollateralInsolvencyIntegration.t.sol#L289
