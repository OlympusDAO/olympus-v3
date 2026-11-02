# BurnerLoansDebt.extend coverage plan

Source: [extend](../../../policies/burnerloans/BurnerLoansDebt.sol#L251). Scenarios specify the required behavior; mappings identify existing test proof.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLEXT-EXTEND` is retained for stable extension case IDs after moving this function to Debt.

Ownership: extend and previewExtend belong to BurnerLoansDebt alongside borrowing and repayment. Execution shares borrower authentication; quotes are permissionless. Both paths share Risk calculations and the Debt settlement role. Governance replaces these three actions together. The combined runtime is 21,580 bytes at optimizer runs 400 without via IR.

Own-policy admission: require Kernel-active BurnerLoansDebt; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Defaults: `onBehalfOf_` is the nonzero borrower; execution is authorized, originations enabled, DM solvent, principal D>0. terms uint16; proposed maturity M=oldMaturity+termLength\*terms; ceiling=min(now+maxMaturityHorizon,uint48.max).

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Preview is permissionless and validates `onBehalfOf_`/inputs; execution separately authenticates its caller; no quote writes | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L159), [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L270), [test_givenPolicyReactivated_whenExtendExecuted_thenSucceeds](extend.t.sol#L1310) |
| BLEXT-EXTEND-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](extend.t.sol#L1132) |
| BLEXT-EXTEND-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](extend.t.sol#L1132) |
| BLEXT-EXTEND-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](extend.t.sol#L1132) |
| BLEXT-EXTEND-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1289), [test_givenDebtDisabled_whenExtended_reverts](extend.t.sol#L488), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](extend.t.sol#L1115) |
| BLEXT-EXTEND-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1289), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](extend.t.sol#L1115) |
| BLEXT-EXTEND-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1289), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](extend.t.sol#L1115) |
| BLEXT-EXTEND-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1289), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](extend.t.sol#L1115) |
| BLEXT-EXTEND-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenDebtInactive_whenExtended_reverts](extend.t.sol#L504), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |
| BLEXT-EXTEND-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](extend.t.sol#L1265), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](extend.t.sol#L1094) |

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
| BLEXT-EXTEND-A01 | Borrower | caller=borrower; no operator grant | `Authorized` | Payer is the actual caller | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L159), [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L270), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324) |
| BLEXT-EXTEND-A02 | Delegated operator | caller=operator; grant issued at time1; independently fuzz deadline D in 2..MAX48 and now in 1..D-1; seed now=1,D-1 and D=MAX48 | `Authorized` | Borrower debt/maturity changes; actual caller funds any mandatory fee | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays](extend.t.sol#L1152), [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive](extend.t.sol#L1177), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167), [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached](extend.t.sol#L980), [test_givenBeforeDeadline_whenOperatorExtended_thenSuccessfulSettlement](extend.t.sol#L1250), [test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement](extend.t.sol#L1260), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenValidGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1371) |
| BLEXT-EXTEND-A03 | Delegated operator | caller=operator; now=deadline; grant nonzero | `Authorized` | Deadline equality accepted | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays](extend.t.sol#L1152), [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive](extend.t.sol#L1177), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167), [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached](extend.t.sol#L980), [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted](extend.t.sol#L998), [test_givenAtDeadline_whenOperatorExtended_thenSuccessfulSettlement](extend.t.sol#L1255), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenGrantDeadline_whenUnrelatedViewerQuotes](extend.t.sol#L1380) |
| BLEXT-EXTEND-A04 | Delegated operator | caller=operator; deadline=MAX48; now<=deadline | `Authorized` | No deadline narrowing | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays](extend.t.sol#L1152), [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive](extend.t.sol#L1177), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167), [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached](extend.t.sol#L980), [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted](extend.t.sol#L998), [test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement](extend.t.sol#L1260), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324) |
| BLEXT-EXTEND-A05 | Fuzz all callers | borrower=0; actual caller arbitrary | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerZero_thenExplicitError](extend.t.sol#L1081) |
| BLEXT-EXTEND-A06 | Fuzz callers excluding borrower | caller differs from borrower; no grant | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts](extend.t.sol#L301), [test_givenNoGrant_whenUnrelatedCallerActs_reverts](extend.t.sol#L1048), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenNoGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1359) |
| BLEXT-EXTEND-A07 | Fuzz callers excluding borrower | caller differs from borrower; grant cancelled to zero | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenCancelledGrant_whenOperatorActs_reverts](extend.t.sol#L1034), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenRevokedGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1404) |
| BLEXT-EXTEND-A08 | Delegated operator | caller=operator; grant nonzero; independently fuzz stored deadline D in 1..MAX48 and now in D+1..MAX256; seed D+1,MAX48+1,MAX256 | `OperatorAuth_UnauthorizedOnBehalfOf()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive](extend.t.sol#L1177), [test_givenExpiredGrant_whenOperatorActs_reverts](extend.t.sol#L1006), [test_givenMaximumTimestamp_whenGrantExpired_reverts](extend.t.sol#L1029), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenExpiredGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1390) |
| BLEXT-EXTEND-A11 | Fuzz unrelated caller X | Borrower B has a valid grant to O; O differs from B; X differs from B and O and has no grant; independently fuzz deadline D in 2..MAX48 and now in 1..D; seed now=1,D and D=MAX48 | `OperatorAuth_UnauthorizedOnBehalfOf()` | B→O grant unchanged; no position, balance or accounting change; no committed logs | X receives the same quote as B under equal economic state; the B→O grant does not restrict quoting | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts](extend.t.sol#L301), [test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts](extend.t.sol#L1061), [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenValidGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1371) |

## Core settlement authorization

Operational action and Core; borrower/operator authorization passes. Core requires only the action's `BL_DEBT_POLICY_ROLE`, independently of the borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-A09 | Borrower | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test_givenDebtRoleRevoked_whenExtended_reverts](extend.t.sol#L320) |
| BLEXT-EXTEND-A10 | Borrower or authorized operator | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return ExtendPreview(fee,oldMaturity+termLength*terms,H) | Advance maturity once and collect the exact accepted fee; principal and collateral unchanged; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenReportedKernelMismatch_whenExtended_thenGetterIsNotRead](extend.t.sol#L681), [test_givenActionKernelGetterReverts_whenExtended_thenGetterIsNotRead](extend.t.sol#L693) |

## Dependency lifecycle

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-D04 | Borrower | Originations disabled | `BurnerLoansCore_AssetOriginationsDisabled(asset)` | Same BurnerLoansCore_AssetOriginationsDisabled(asset) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenOriginationsDisabled_whenExtended_reverts](extend.t.sol#L745) |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-I01 | Borrower | terms=0 | `BurnerLoansCore_ZeroAmount()` | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenTermsAreZero_reverts](extend.t.sol#L367) |
| BLEXT-EXTEND-I02 | Borrower | Snapshot invalid | `BurnerLoans_InvalidPrice()` | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts](extendIntegration.t.sol#L205) |
| BLEXT-EXTEND-I03 | Borrower | Debt=0 | `BurnerLoansCore_NoDebt()` | Same BurnerLoansCore_NoDebt() with all earlier preview checks satisfied; assert no writes | Covered: [test_givenNoDebt_whenExtended_reverts](extend.t.sol#L381), [test_givenCollateralWithNoDebt_whenExtended_reverts](extend.t.sol#L965) |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-N01 | Borrower | M>ceiling; fuzz accepted uint16 terms producing overrun | `BurnerLoans_MaturityHorizonExceeded(M,ceiling)` | Same BurnerLoans_MaturityHorizonExceeded(M,ceiling) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenTermsExceedHorizon_reverts](extend.t.sol#L423), [test_whenMaximumTermsExceedHorizon_reverts](extend.t.sol#L444) |
| BLEXT-EXTEND-N02 | Borrower | Fee F>0; fuzz maxFee 0..F-1 | `BurnerLoans_FeeExceedsMax(F,maxFee)` | Same BurnerLoans_FeeExceedsMax(F,maxFee) | Covered: [test_givenFeeAboveMaximum_whenExtended_reverts](extend.t.sol#L395), [test_givenRiskFee_whenLimitBelowFee_reverts](extend.t.sol#L828) |

## Successful execution

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-P01 | Borrower | DM payout insolvent | `BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed)` | Revert BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed); the quote fields do not explain payout insolvency | Covered: [test_givenCustodyInsolvent_whenExtended_reverts](extend.t.sol#L759) |
| BLEXT-EXTEND-P02 | Borrower | Resulting maturity M<now | `BurnerLoans_ExtensionMaturityNotFuture(M,now)` | Same BurnerLoans_ExtensionMaturityNotFuture(M,now) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenResultingExpiryNotFuture_whenExtended_reverts](extend.t.sol#L784) |
| BLEXT-EXTEND-P03 | Borrower | M=now | `BurnerLoans_ExtensionMaturityNotFuture(M,now)` | Same BurnerLoans_ExtensionMaturityNotFuture(M,now) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenResultingExpiryNotFuture_whenExtended_reverts](extend.t.sol#L784), [test_givenResultingExpiryEqualsNow_whenExtended_reverts](extend.t.sol#L802) |
| BLEXT-EXTEND-P04 | Borrower | Health H<1e18 | `BurnerLoans_UnhealthyPosition(H)` | Revert BurnerLoans_UnhealthyPosition(H) for health below 1e18 | Covered: [test_givenUnhealthyPosition_whenExtended_reverts](extend.t.sol#L807) |

## Numeric boundaries and successful extension

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-N03 | Borrower | M=ceiling; healthy position | `Success` | No maturity truncation; only maturity and fee accounting change | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted](extend.t.sol#L848), [test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation](extend.t.sol#L1199) |
| BLEXT-EXTEND-N04 | Borrower | H=1e18; fee=maxFee | `Success` | Both exact thresholds accepted | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted](extend.t.sol#L848) |
| BLEXT-EXTEND-N05 | Borrower or unexpired operator | H>1e18; Mock Risk returns arbitrary positive fee F; maxFee>F; funded payer approves Core; mock Custody.creditFee to accept without outgoing payout | `Return exactly F; success` | Core settlement fee=F; actual caller -F and selected Custody +F; one creditFee(asset,F); Extended caller/fee match; principal/collateral unchanged | Quote the same mocked F without collection or Custody calls; no local fee recalculation, rescaling or substitution of maxFee | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L159), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167), [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L270), [test_givenMaximumUint128Fee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L275), [test_givenMaximumFundableUint256Fee_whenExtended_thenExactReceipt](extend.t.sol#L673) |
| BLEXT-EXTEND-N06 | Borrower | terms=1; M future/in horizon | `Success` | M=oldMaturity+termLength | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L159), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167), [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L270), [test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation](extend.t.sol#L1199) |
| BLEXT-EXTEND-N07 | Borrower | terms=MAX16; construct representable future M inside clamped horizon | `Success` | Exact max-width multiplication/narrowing; otherwise use explicit over-horizon case | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenOneSecondTerm_whenMaximumTermsExtended_thenNoTruncation](extend.t.sol#L877) |
| BLEXT-EXTEND-N08 | Borrower | Inventory disabled; valid extension | `Success` | No Inventory gate; principal unchanged | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenInventoryDisabled_whenExtended_thenSucceeds](extend.t.sol#L280) |
| BLEXT-EXTEND-N09 | Borrower or unexpired operator | Mock Risk returns fee 0; payer collateral balance/allowance=0; valid term/health and maxFee=0 or MAX256 | `Return fee 0; success` | Maturity updated once; no fee transferFrom or Custody.creditFee; Extended fee=0; principal/collateral unchanged | Quote fee 0; no payer approval/balance requirement | Covered: [test_givenZeroFee_whenExtended_thenNoFeeHandoff](extend.t.sol#L246), [test_givenZeroFeeAndNoWalletFunds_whenOperatorExtends_thenNoCollection](extend.t.sol#L905), [test_givenZeroFeeAndNoWalletFunds_whenBorrowerExtends_thenNoCollection](extend.t.sol#L914), [test_givenZeroFeeAndMaximumLimit_whenExtended_thenNoCollection](extend.t.sol#L922), [test_givenZeroFeeAndMaximumLimit_whenOperatorExtends_thenNoCollection](extend.t.sol#L927) |

## Transfer and settlement failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T02 | Borrower | Mandatory incoming fee transfer fails | `Exact token transfer error; old maturity remains` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenCollateralCallback_whenExtended_revertsAtomically](extend.t.sol#L534) |
| BLEXT-EXTEND-T03 | Borrower | FLOAN rejects extension | `Exact FLOAN error; no fee collection` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenFloanRejectsExtension_whenExtended_thenNoFeeOrExpiryChange](extend.t.sol#L709) |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee and health. Assert Risk.fee receives the captured snapshot, asset, current principal and requested terms, and that its independently configured result F is used unchanged for maxFee validation, Core's fee instruction, payer→Custody collection, creditFee, return value and Extended. Vary F independently of term/position inputs and include one raw collateral unit; use the full fundable range with representable token supply. Real Core settlement plus mocked Custody.creditFee proves receipt and delegation without testing Treasury/distributor routing. Risk's arithmetic suite and real Risk integration separately prove calculation and rounding.

Existing maturity is not rewritten by Config; new term affects this call. The preview reverts with BurnerLoans_UnhealthyPosition(H) for an unhealthy position. Custody insolvency reverts with BurnerLoansCore_Insolvent and its accounting arguments. Keep BurnerLoansCore_NoDebt() for zero principal: extension has no requested repayment amount to exceed the debt. Cover price-refresh changes to maturity/debt separately from the single mandatory collateral-transfer reentrancy case below. Custody's own scenarios cover outgoing distribution, deferral, pending-fee sweeps and retries.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Carry forward exact use of Risk-returned fees, no fee handoff at zero, term changes preserving previous maturity until extension, aggregate top-up debt extension fees, expired-but-healthy extension based on old maturity and mandatory incoming-fee callbacks. Risk and integration tests cover one-unit rounding and 6/18/9 decimal combinations; Custody tests cover old reserves, deferred-fee sweeps and outgoing callbacks.

## Real Risk integration

Use extendIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Use a fixed borrower caller because authorization is covered in unit scenarios. Independently calculate the fee by rounding per term up before multiplying terms; assert real Risk, the action return/event, payer debit and incoming Custody transfer agree. Custody may subsequently distribute the fee, so its final balance need not retain it; destination/delivery assertions belong to Custody. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-P05 | Borrower | Valid real snapshot; compatible custody; independent fee rounding, term-count and decimal-scale boundaries | Successful operation | Independent fee calculation equals real Risk fee, action return/Extended fee, actual payer debit and incoming Custody transfer; maturity and WAD health match independent expectations; principal/collateral unchanged | Real fee and health agree under unchanged prices/configuration; no preview writes | Covered: [test_givenRealRisk_whenExtended_thenPerTermRoundingIsIndependent](extendIntegration.t.sol#L19), [test_givenRealRisk_whenOneTermExtended_then314063Fee](extendIntegration.t.sol#L27) |
| BLEXT-EXTEND-P06 | Borrower | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts](extendIntegration.t.sol#L205) |

## Additional economic regression coverage

Failure to receive the mandatory fee is intentionally blocking. A valid preview does not establish payer balance or allowance. Production PriceCache is selected by governance and provides price refresh, not an arbitrary borrower-action callback; the existing callback-cache cases use a synthetic adversarial dependency and explicit operator grants where required.

| ID | Caller | Pre-state / input | Expected outcome | Required accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T04 | Borrower or authorized operator | Positive fee F; payer allowance L in 0..F-1; balance sufficient; seed L=0,F-1 | ERC20InsufficientAllowance(Core,L,F) | Preview quotes F; failed execution preserves complete position including maturity, all accounting, balances and allowances | Covered: [test_givenInsufficientFeeAllowance_whenExtended_reverts](extend.t.sol#L40), [test_givenZeroFeeAllowance_whenBorrowerExtends_reverts](extend.t.sol#L119), [test_givenFeeAllowanceOneBelow_whenOperatorExtends_reverts](extend.t.sol#L124) |
| BLEXT-EXTEND-T05 | Borrower or authorized operator | Positive fee F; payer balance B in 0..F-1; allowance F; seed B=0,F-1 and F=MAX256 with an unfunded operator | ERC20InsufficientBalance(payer,B,F) | Preview quotes F; failed execution restores consumed allowance and complete position, accounting and balances | Covered: [test_givenInsufficientFeeBalance_whenExtended_reverts](extend.t.sol#L64), [test_givenZeroFeeBalance_whenBorrowerExtends_reverts](extend.t.sol#L129), [test_givenFeeBalanceOneBelow_whenOperatorExtends_reverts](extend.t.sol#L134), [test_givenMaximumUint256Fee_givenUnfundedOperator_whenExtended_reverts](extend.t.sol#L139) |
| BLEXT-EXTEND-P07 | Borrower | Real borrow 100 OHM, top-up 50 OHM, then extend two 30-day terms | Top-up fee 157032; extension fee 944532 raw units | Top-up preserves old maturity; extension charges all 150 OHM at 0.15% market utilization, rounding 472266 per term; principal/collateral/global debt unchanged by extension; exact fee debit and receipt | Covered: [test_givenRealTopUp_whenExtended](extendIntegration.t.sol#L38) |
| BLEXT-EXTEND-P08 | Borrower | Same top-up; governance changes term to 15 days, then extend two terms | Fee remains 944532; maturity increases by 30 days from old maturity | Configuration change preserves old expiry; preview and execution use current term length and all 150 OHM principal; no change to collateral or global debt | Covered: [test_givenRealTopUp_givenUpdatedTermLength_whenExtended](extendIntegration.t.sol#L48) |
| BLEXT-EXTEND-P09 | Borrower | Existing 100 OHM debt; quote extension with collateral USD 1; cache expires and fresh collateral price becomes USD 0.5 | One-term fee increases from 314063 to 628125 | Fresh preview agrees; production cache refreshed once; maturity advances once; exact payer debit; principal unchanged | Covered: [test_givenExpiredCacheAndChangedPrice_whenExtended](extendIntegration.t.sol#L84) |
| BLEXT-EXTEND-P10 | Borrower | Same price movement; maxFee remains original quoted 314063 | FeeExceedsMax(628125,314063) | Complete rollback including cache refresh, maturity, fee allowances, custody and debt | Covered: [test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts](extendIntegration.t.sol#L104) |

## Adversarial cache callbacks before settlement

These cases use the test-only BurnerLoansCallbackCache, not production PriceCache. The fixture selects it using admin authority, then separately grants it borrower operator authority for nested authorized actions. This probes a synthetic hostile dependency; it does not establish callback support as a cache integration requirement. Core's transfer guard is not entered during Risk.refreshSnapshot, so these existing cases describe current behavior before settlement.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C01 | Borrower | Cache callback repays the position; subsequent debt/maturity checks use reloaded principal and reject NoDebt when fully repaid | BurnerLoansCore_NoDebt(); nested full repayment and cache writes roll back | Successful call reflects actual state; rejected call restores Core/FLOAN/Inventory/DM/cache balances, allowances and logs | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheFullyRepays_whenExtensionReloads_thenNoDebtAndRollback](extendPriceCallbacks.t.sol#L18) |

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCaughtUnauthorizedCacheBorrow_whenExtending_thenOneExtension](extendPriceCallbacks.t.sol#L39) |
| BLEXT-EXTEND-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenPropagatedUnauthorizedCacheBorrow_whenExtending_thenRollback](extendPriceCallbacks.t.sol#L54) |

Retired BLEXT-EXTEND-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Transfer callbacks and reentrancy

Authorize an otherwise-valid nested extension so the collateral token callback reaches Core's guard during the mandatory fee transfer. Configure the existing callback token to propagate that rejection.

| ID | Caller | Transfer callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C06 | Borrower | Collateral asset attempts nested extension during payer→Custody transferFrom | Nested ReentrancyGuardReentrantCall(); outer ReentrantFeeToken.CallbackFailed() | Old maturity, payer/Custody balances and allowance restored; principal/collateral unchanged; no committed logs | Quote before arming callback; view performs no transfer and cannot predict token failure | Covered: [test_givenCollateralCallback_whenExtended_revertsAtomically](extend.t.sol#L534) |

## Payout dependency readiness

Other admission checks pass. Payout is selected on Core; direct IEnabler state can drift after Core/action enablement.

| ID | Caller | Payout active | Payout enabled | Execution | Preview | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-EXTEND-D01 | Borrower | true | false | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts](extend.t.sol#L1235) |
| BLDEBT-EXTEND-D02 | Borrower | false | true | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts](extend.t.sol#L1235) |
| BLDEBT-EXTEND-D03 | Borrower | false | false | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts](extend.t.sol#L1235) |

## Permissionless quote identities

| ID | Quote requester | Position owner | Execution caller / history | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-A12 | Fuzz every address; no authorization lookup allowed | Nonzero `onBehalfOf_`=B | Borrower or operator may execute later | Identical independently checked quote for B; no writes/logs; nonzero-fee quotes precede funding/approval of borrower or operator | Covered: [test_whenAnyViewerQuotesWithoutAuthorizationRead](extend.t.sol#L1324), [test_givenRiskFee_whenExtended_thenExactFeeIsSettled](extend.t.sol#L159), [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled](extend.t.sol#L167) |
| BLEXT-EXTEND-A13 | Unrelated viewer X | B | Prospective operator O before grant, while valid, at deadline, after expiry and after revocation | Quote remains independent of O's grant while economic state is valid; execution follows grant validity | Covered: [test_givenNoGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1359), [test_givenValidGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1371), [test_givenGrantDeadline_whenUnrelatedViewerQuotes](extend.t.sol#L1380), [test_givenExpiredGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1390), [test_givenRevokedGrant_whenUnrelatedViewerQuotes](extend.t.sol#L1404) |
| BLEXT-EXTEND-A14 | Unrelated viewer X | B | B has debt; X has no debt | Quote B succeeds; quoting X fails NoDebt; neither position changes | Covered: [test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted](extend.t.sol#L1419) |
