# BurnerLoansDebt.extend coverage plan

Authorization migration: grants now live on the selected BurnerLoansAuth. The public caller is the actual operator. Zero operator identities reject with `OperatorAuth_InvalidIdentity`; other absent/cancelled authority rejects with `OperatorAuth_InvalidContext`; expired accepted grants reject with `OperatorAuth_ExpiredGrant(deadline)`. An expired grant does not block permissionless previews. Cancelled-grant fixtures use nonzero operators because zero-operator grants cannot be created. Canonical permissions bind the explicit market asset, including custom callback tokens.

> Referral scenarios below supplement the retained baseline. Their mappings identify the additional assertions for the extended API.

Source: [extend](../../../policies/burnerloans/BurnerLoansDebt.sol#L282). Scenarios specify the required behavior; mappings identify existing test proof.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLEXT-EXTEND` is retained for stable extension case IDs after moving this function to Debt.

Ownership: extend and previewExtend belong to BurnerLoansDebt alongside borrowing and repayment. Execution shares borrower authentication; quotes are permissionless. Both paths share Risk calculations and the Debt settlement role. Governance replaces these three actions together.

Own-policy admission: require Kernel-active BurnerLoansDebt; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Defaults: `onBehalfOf_` is the nonzero borrower; execution is authorized, originations enabled, DM solvent, principal D>0. terms uint16; proposed maturity M=oldMaturity+termLength\*terms; ceiling=min(now+maxMaturityHorizon,uint48.max).

Baseline fee cases use referrer=address(0) and Risk outputs (protocolFee,referralFee)=(F,0), unless a referral row overrides them. Core receives separate (F,address(0),0) allocation fields. Debt returns total fee F; Borrowed/Extended identify protocolFee=F, referrer=0 and referralFee=0. Payout means BurnerLoansPayout, separate from DepositManager collateral custody.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Preview is permissionless and validates `onBehalfOf_`/inputs; execution separately authenticates its caller; no quote writes | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled][test_givenRiskFee_whenExtended_thenExactFeeIsSettled], [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled][test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled], [test_givenPolicyReactivated_whenExtendExecuted_thenSucceeds][test_givenPolicyReactivated_whenExtendExecuted_thenSucceeds] |
| BLEXT-EXTEND-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLEXT-EXTEND-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLEXT-EXTEND-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLEXT-EXTEND-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDebtDisabled_whenExtended_reverts][test_givenDebtDisabled_whenExtended_reverts], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLEXT-EXTEND-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLEXT-EXTEND-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLEXT-EXTEND-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLEXT-EXTEND-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDebtInactive_whenExtended_reverts][test_givenDebtInactive_whenExtended_reverts], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLEXT-EXTEND-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |

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
| BLEXT-EXTEND-A01 | Borrower | caller=borrower; no operator grant | `Authorized` | Payer is the actual caller | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled][test_givenRiskFee_whenExtended_thenExactFeeIsSettled], [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled][test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLEXT-EXTEND-A02 | Delegated operator | caller=operator; grant issued at time1; independently fuzz deadline D in 2..MAX48 and now in 1..D-1; seed now=1,D-1 and D=MAX48 | `Authorized` | Borrower debt/maturity changes; actual caller funds any mandatory fee | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays][test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenBeforeDeadline_whenOperatorExtended_thenSuccessfulSettlement][test_givenBeforeDeadline_whenOperatorExtended_thenSuccessfulSettlement], [test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement][test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A03 | Delegated operator | caller=operator; now=deadline; grant nonzero | `Authorized` | Deadline equality accepted | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays][test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted][test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted], [test_givenAtDeadline_whenOperatorExtended_thenSuccessfulSettlement][test_givenAtDeadline_whenOperatorExtended_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A04 | Delegated operator | caller=operator; deadline=MAX48; now<=deadline | `Authorized` | No deadline narrowing | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays][test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted][test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted], [test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement][test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLEXT-EXTEND-A05 | Fuzz all callers | borrower=0; actual caller arbitrary | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerZero_thenExplicitError][test_whenBorrowerZero_thenExplicitError] |
| BLEXT-EXTEND-A06 | Fuzz callers excluding borrower | caller differs from borrower; no grant | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts][test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts], [test_givenNoGrant_whenUnrelatedCallerActs_reverts][test_givenNoGrant_whenUnrelatedCallerActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A07 | Fuzz callers excluding borrower | caller differs from borrower; grant cancelled to zero | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenCancelledGrant_whenOperatorActs_reverts][test_givenCancelledGrant_whenOperatorActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A08 | Delegated operator | caller=operator; grant nonzero; independently fuzz stored deadline D in 1..MAX48 and now in D+1..MAX256; seed D+1,MAX48+1,MAX256 | `OperatorAuth_ExpiredGrant(D)` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenExpiredGrant_whenOperatorActs_reverts][test_givenExpiredGrant_whenOperatorActs_reverts], [test_givenMaximumTimestamp_whenGrantExpired_reverts][test_givenMaximumTimestamp_whenGrantExpired_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A11 | Fuzz unrelated caller X | Borrower B has a valid grant to O; O differs from B; X differs from B and O and has no grant; independently fuzz deadline D in 2..MAX48 and now in 1..D; seed now=1,D and D=MAX48 | `OperatorAuth_InvalidContext()` | B→O grant unchanged; no position, balance or accounting change; no committed logs | X receives the same quote as B under equal economic state; the B→O grant does not restrict quoting | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts][test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts], [test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts][test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |

## Core settlement authorization

Operational action and Core; borrower/operator authorization passes. Core requires only the action's `BL_DEBT_POLICY_ROLE`, independently of the borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-A09 | Borrower | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test_givenDebtRoleRevoked_whenExtended_reverts][test_givenDebtRoleRevoked_whenExtended_reverts] |
| BLEXT-EXTEND-A10 | Borrower or authorized operator | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return ExtendPreview(fee,oldMaturity+termLength\*terms,H) | Advance maturity once and collect the exact accepted fee; principal and collateral unchanged; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenReportedKernelMismatch_whenExtended_thenGetterIsNotRead][test_givenReportedKernelMismatch_whenExtended_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenExtended_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenExtended_thenGetterIsNotRead] |

## Dependency lifecycle

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-D04 | Borrower | Originations disabled | `BurnerLoansCore_AssetOriginationsDisabled(asset)` | Same BurnerLoansCore_AssetOriginationsDisabled(asset) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenOriginationsDisabled_whenExtended_reverts][test_givenOriginationsDisabled_whenExtended_reverts] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-I01 | Borrower | terms=0 | `BurnerLoansCore_ZeroAmount()` | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenTermsAreZero_reverts][test_whenTermsAreZero_reverts] |
| BLEXT-EXTEND-I02 | Borrower | Snapshot invalid | `BurnerLoans_InvalidPrice()` | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts][test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts] |
| BLEXT-EXTEND-I03 | Borrower | Debt=0 | `BurnerLoansCore_NoDebt()` | Same BurnerLoansCore_NoDebt() with all earlier preview checks satisfied; assert no writes | Covered: [test_givenNoDebt_whenExtended_reverts][test_givenNoDebt_whenExtended_reverts], [test_givenCollateralWithNoDebt_whenExtended_reverts][test_givenCollateralWithNoDebt_whenExtended_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-N01 | Borrower | M>ceiling; fuzz accepted uint16 terms producing overrun | `BurnerLoans_MaturityHorizonExceeded(M,ceiling)` | Same BurnerLoans_MaturityHorizonExceeded(M,ceiling) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenTermsExceedHorizon_reverts][test_whenTermsExceedHorizon_reverts], [test_whenMaximumTermsExceedHorizon_reverts][test_whenMaximumTermsExceedHorizon_reverts] |
| BLEXT-EXTEND-N02 | Borrower | Fee F>0; fuzz maxFee 0..F-1 | `BurnerLoans_FeeExceedsMax(F,maxFee)` | Same BurnerLoans_FeeExceedsMax(F,maxFee) | Covered: [test_givenFeeAboveMaximum_whenExtended_reverts][test_givenFeeAboveMaximum_whenExtended_reverts], [test_givenRiskFee_whenLimitBelowFee_reverts][test_givenRiskFee_whenLimitBelowFee_reverts] |

## Successful execution

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-P01 | Borrower | DM payout insolvent | `BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed)` | Revert BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed); the quote fields do not explain payout insolvency | Covered: [test_givenCustodyInsolvent_whenExtended_reverts][test_givenCustodyInsolvent_whenExtended_reverts] |
| BLEXT-EXTEND-P02 | Borrower | Resulting maturity M<now | `BurnerLoans_ExtensionMaturityNotFuture(M,now)` | Same BurnerLoans_ExtensionMaturityNotFuture(M,now) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenResultingExpiryNotFuture_whenExtended_reverts][test_givenResultingExpiryNotFuture_whenExtended_reverts] |
| BLEXT-EXTEND-P03 | Borrower | M=now | `BurnerLoans_ExtensionMaturityNotFuture(M,now)` | Same BurnerLoans_ExtensionMaturityNotFuture(M,now) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenResultingExpiryNotFuture_whenExtended_reverts][test_givenResultingExpiryNotFuture_whenExtended_reverts], [test_givenResultingExpiryEqualsNow_whenExtended_reverts][test_givenResultingExpiryEqualsNow_whenExtended_reverts] |
| BLEXT-EXTEND-P04 | Borrower | Health H<1e18 | `BurnerLoans_UnhealthyPosition(H)` | Revert BurnerLoans_UnhealthyPosition(H) for health below 1e18 | Covered: [test_givenUnhealthyPosition_whenExtended_reverts][test_givenUnhealthyPosition_whenExtended_reverts] |

## Numeric boundaries and successful extension

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-N03 | Borrower | M=ceiling; healthy position | `Success` | No maturity truncation; only maturity and fee accounting change | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted][test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted], [test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation][test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation] |
| BLEXT-EXTEND-N04 | Borrower | H=1e18; fee=maxFee | `Success` | Both exact thresholds accepted | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted][test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted] |
| BLEXT-EXTEND-N05 | Borrower or unexpired operator | H>1e18; Mock Risk returns arbitrary positive fee F; maxFee>F; funded payer approves Core; mock Payout.creditFee to accept without outgoing payout | `Return exactly F; success` | Core settlement (protocolFee,referrer,referralFee)=(F,address(0),0); actual caller -F and selected Payout +F; one creditFee(asset,F,address(0),0); Extended caller and (protocolFee=F,referrer=0,referralFee=0) match; principal/collateral unchanged | Quote the same mocked F without collection or Payout credit; no local fee recalculation, rescaling or substitution of maxFee | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled][test_givenRiskFee_whenExtended_thenExactFeeIsSettled], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled][test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled], [test_givenMaximumUint128Fee_whenOperatorExtends_thenExactFeeIsSettled][test_givenMaximumUint128Fee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenMaximumFundableUint256Fee_whenExtended_thenExactReceipt][test_givenMaximumFundableUint256Fee_whenExtended_thenExactReceipt] |
| BLEXT-EXTEND-N06 | Borrower | terms=1; M future/in horizon | `Success` | M=oldMaturity+termLength | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRiskFee_whenExtended_thenExactFeeIsSettled][test_givenRiskFee_whenExtended_thenExactFeeIsSettled], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled], [test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled][test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled], [test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation][test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation] |
| BLEXT-EXTEND-N07 | Borrower | terms=MAX16; construct representable future M inside clamped horizon | `Success` | Exact max-width multiplication/narrowing; otherwise use explicit over-horizon case | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenOneSecondTerm_whenMaximumTermsExtended_thenNoTruncation][test_givenOneSecondTerm_whenMaximumTermsExtended_thenNoTruncation] |
| BLEXT-EXTEND-N08 | Borrower | Inventory disabled; valid extension | `Success` | No Inventory gate; principal unchanged | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenInventoryDisabled_whenExtended_thenSucceeds][test_givenInventoryDisabled_whenExtended_thenSucceeds] |
| BLEXT-EXTEND-N09 | Borrower or unexpired operator | Mock Risk returns fee 0; payer collateral balance/allowance=0; valid term/health and maxFee=0 or MAX256 | `Return fee 0; success` | Maturity updated once; no fee transferFrom or Payout.creditFee; Extended protocolFee=0,referrer=0,referralFee=0; principal/collateral unchanged | Quote fee 0; no payer approval/balance requirement | Covered: [test_givenZeroFee_whenExtended_thenNoFeeHandoff][test_givenZeroFee_whenExtended_thenNoFeeHandoff], [test_givenZeroFeeAndNoWalletFunds_whenOperatorExtends_thenNoCollection][test_givenZeroFeeAndNoWalletFunds_whenOperatorExtends_thenNoCollection], [test_givenZeroFeeAndNoWalletFunds_whenBorrowerExtends_thenNoCollection][test_givenZeroFeeAndNoWalletFunds_whenBorrowerExtends_thenNoCollection], [test_givenZeroFeeAndMaximumLimit_whenExtended_thenNoCollection][test_givenZeroFeeAndMaximumLimit_whenExtended_thenNoCollection], [test_givenZeroFeeAndMaximumLimit_whenOperatorExtends_thenNoCollection][test_givenZeroFeeAndMaximumLimit_whenOperatorExtends_thenNoCollection] |

## Transfer and settlement failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T02 | Borrower | Mandatory incoming fee transfer fails | `Exact token transfer error; old maturity remains` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenCollateralCallback_whenExtended_revertsAtomically][test_givenCollateralCallback_whenExtended_revertsAtomically] |
| BLEXT-EXTEND-T03 | Borrower | FLOAN rejects extension | `Exact FLOAN error; no fee collection` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenFloanRejectsExtension_whenExtended_thenNoFeeOrExpiryChange][test_givenFloanRejectsExtension_whenExtended_thenNoFeeOrExpiryChange] |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee and health. Assert Risk.fee receives the captured snapshot, canonical market ID, current principal, requested terms and zero referrer. Its independently configured outputs (F,0) determine maxFee validation and the total result F. Core receives protocolFee=F, referrer=0 and referralFee=0, collects F directly from the payer into Payout, then calls creditFee(asset,F,address(0),0); Extended reports that split. Vary F independently of term/position inputs and include one raw collateral unit; use the full fundable range with representable token supply. Real Core settlement plus mocked Payout.creditFee proves receipt and delegation without testing Treasury/distributor routing. Risk's arithmetic suite and real Risk integration separately prove calculation and rounding.

Existing maturity is not rewritten by Config; new term affects this call. The preview reverts with BurnerLoans_UnhealthyPosition(H) for an unhealthy position. Custody insolvency reverts with BurnerLoansCore_Insolvent and its accounting arguments. Keep BurnerLoansCore_NoDebt() for zero principal: extension has no requested repayment amount to exceed the debt. Cover price-refresh changes to maturity/debt separately from the single mandatory collateral-transfer reentrancy case below. Payout's own scenarios cover outgoing distribution, deferral, pending-fee sweeps and retries.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Carry forward exact use of Risk-returned fees, no fee handoff at zero, term changes preserving previous maturity until extension, aggregate top-up debt extension fees, expired-but-healthy extension based on old maturity and mandatory incoming-fee callbacks. Risk and integration tests cover one-unit rounding and 6/18/9 decimal combinations; Payout tests cover old reserves, deferred-fee sweeps and outgoing callbacks.

## Real Risk integration

Use extendIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Use a fixed borrower caller because authorization is covered in unit scenarios. Independently calculate the fee by rounding per term up before multiplying terms; assert real Risk, the action return/event, payer debit and incoming Payout transfer agree. Payout may subsequently distribute the fee, so its final balance need not retain it; destination/delivery assertions belong to Payout. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-P05 | Borrower | Valid real snapshot; compatible custody; independent fee rounding, term-count and decimal-scale boundaries | Successful operation | Independent fee calculation equals real Risk fee, action total return/Extended protocolFee, actual payer debit and incoming Payout transfer; maturity and WAD health match independent expectations; principal/collateral unchanged | Real fee and health agree under unchanged prices/configuration; no preview writes | Covered: [test_givenRealRisk_whenExtended_thenPerTermRoundingIsIndependent][test_givenRealRisk_whenExtended_thenPerTermRoundingIsIndependent], [test_givenRealRisk_whenOneTermExtended_then314063Fee][test_givenRealRisk_whenOneTermExtended_then314063Fee] |
| BLEXT-EXTEND-P06 | Borrower | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts][test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts] |

## Additional economic regression coverage

Failure to receive the mandatory fee is intentionally blocking. A valid preview does not establish payer balance or allowance. Production PriceCache is selected by governance and provides price refresh, not an arbitrary borrower-action callback; the existing callback-cache cases use a synthetic adversarial dependency and explicit operator grants where required.

| ID | Caller | Pre-state / input | Expected outcome | Required accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T04 | Borrower or authorized operator | Positive fee F; payer allowance L in 0..F-1; balance sufficient; seed L=0,F-1 | ERC20InsufficientAllowance(Core,L,F) | Preview quotes F; failed execution preserves complete position including maturity, all accounting, balances and allowances | Covered: [test_givenInsufficientFeeAllowance_whenExtended_reverts][test_givenInsufficientFeeAllowance_whenExtended_reverts], [test_givenZeroFeeAllowance_whenBorrowerExtends_reverts][test_givenZeroFeeAllowance_whenBorrowerExtends_reverts], [test_givenFeeAllowanceOneBelow_whenOperatorExtends_reverts][test_givenFeeAllowanceOneBelow_whenOperatorExtends_reverts] |
| BLEXT-EXTEND-T05 | Borrower or authorized operator | Positive fee F; payer balance B in 0..F-1; allowance F; seed B=0,F-1 and F=MAX256 with an unfunded operator | ERC20InsufficientBalance(payer,B,F) | Preview quotes F; failed execution restores consumed allowance and complete position, accounting and balances | Covered: [test_givenInsufficientFeeBalance_whenExtended_reverts][test_givenInsufficientFeeBalance_whenExtended_reverts], [test_givenZeroFeeBalance_whenBorrowerExtends_reverts][test_givenZeroFeeBalance_whenBorrowerExtends_reverts], [test_givenFeeBalanceOneBelow_whenOperatorExtends_reverts][test_givenFeeBalanceOneBelow_whenOperatorExtends_reverts], [test_givenMaximumUint256Fee_givenUnfundedOperator_whenExtended_reverts][test_givenMaximumUint256Fee_givenUnfundedOperator_whenExtended_reverts] |
| BLEXT-EXTEND-P07 | Borrower | Real borrow 100 OHM, top-up 50 OHM, then extend two 30-day terms | Top-up fee 157032; extension fee 944532 raw units | Top-up preserves old maturity; extension charges all 150 OHM at 0.15% market utilization, rounding 472266 per term; principal/collateral/global debt unchanged by extension; exact fee debit and receipt | Covered: [test_givenRealTopUp_whenExtended][test_givenRealTopUp_whenExtended] |
| BLEXT-EXTEND-P08 | Borrower | Same top-up; governance changes term to 15 days, then extend two terms | Fee remains 944532; maturity increases by 30 days from old maturity | Configuration change preserves old expiry; preview and execution use current term length and all 150 OHM principal; no change to collateral or global debt | Covered: [test_givenRealTopUp_givenUpdatedTermLength_whenExtended][test_givenRealTopUp_givenUpdatedTermLength_whenExtended] |
| BLEXT-EXTEND-P09 | Borrower | Existing 100 OHM debt; quote extension with collateral USD 1; cache expires and fresh collateral price becomes USD 0.5 | One-term fee increases from 314063 to 628125 | Fresh preview agrees; production cache refreshed once; maturity advances once; exact payer debit; principal unchanged | Covered: [test_givenExpiredCacheAndChangedPrice_whenExtended][test_givenExpiredCacheAndChangedPrice_whenExtended] |
| BLEXT-EXTEND-P10 | Borrower | Same price movement; maxFee remains original quoted 314063 | FeeExceedsMax(628125,314063) | Complete rollback including cache refresh, maturity, fee allowances, custody and debt | Covered: [test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts][test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts] |

## Adversarial cache callbacks before settlement

These cases use the test-only BurnerLoansCallbackCache, not production PriceCache. The fixture selects it using admin authority, then separately grants it borrower operator authority for nested authorized actions. This probes a synthetic hostile dependency; it does not establish callback support as a cache integration requirement. Core's transfer guard is not entered during Risk.refreshSnapshot, so these existing cases describe current behavior before settlement.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C01 | Borrower | Cache callback repays the position; subsequent debt/maturity checks use reloaded principal and reject NoDebt when fully repaid | BurnerLoansCore_NoDebt(); nested full repayment and cache writes roll back | Successful call reflects actual state; rejected call restores Core/FLOAN/Inventory/DM/cache balances, allowances and logs | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheFullyRepays_whenExtensionReloads_thenNoDebtAndRollback][test_givenCacheFullyRepays_whenExtensionReloads_thenNoDebtAndRollback] |

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCaughtUnauthorizedCacheBorrow_whenExtending_thenOneExtension][test_givenCaughtUnauthorizedCacheBorrow_whenExtending_thenOneExtension] |
| BLEXT-EXTEND-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenPropagatedUnauthorizedCacheBorrow_whenExtending_thenRollback][test_givenPropagatedUnauthorizedCacheBorrow_whenExtending_thenRollback] |

Retired BLEXT-EXTEND-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Transfer callbacks and reentrancy

Authorize an otherwise-valid nested extension so the collateral token callback reaches Core's guard during the mandatory fee transfer. Configure the existing callback token to propagate that rejection.

| ID | Caller | Transfer callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-C06 | Borrower | Collateral asset attempts nested extension during payer→Payout transferFrom | Nested ReentrancyGuardReentrantCall(); outer ReentrantFeeToken.CallbackFailed() | Old maturity, payer/Payout balances and allowance restored; principal/collateral unchanged; no committed logs | Quote before arming callback; view performs no transfer and cannot predict token failure | Covered: [test_givenCollateralCallback_whenExtended_revertsAtomically][test_givenCollateralCallback_whenExtended_revertsAtomically] |

## Payout dependency readiness

Other admission checks pass. Payout is selected on Core; direct IEnabler state can drift after Core/action enablement.

| ID | Caller | Payout active | Payout enabled | Execution | Preview | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-EXTEND-D01 | Borrower | true | false | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |
| BLDEBT-EXTEND-D02 | Borrower | false | true | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |
| BLDEBT-EXTEND-D03 | Borrower | false | false | PolicyDependency_NotActive(Payout) for fee-bearing extension | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |

## Permissionless quote identities

| ID | Quote requester | Position owner | Execution caller / history | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-A12 | Fuzz every address; no authorization lookup allowed | Nonzero `onBehalfOf_`=B | Borrower or operator may execute later | Identical independently checked quote for B; no writes/logs; nonzero-fee quotes precede funding/approval of borrower or operator | Covered: [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenRiskFee_whenExtended_thenExactFeeIsSettled][test_givenRiskFee_whenExtended_thenExactFeeIsSettled], [test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled][test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled] |
| BLEXT-EXTEND-A13 | Unrelated viewer X | B | Prospective operator O before grant, while valid, at deadline, after expiry and after revocation | Quote remains independent of O's grant while economic state is valid; execution follows grant validity | Covered: [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLEXT-EXTEND-A14 | Unrelated viewer X | B | B has debt; X has no debt | Quote B succeeds; quoting X fails NoDebt; neither position changes | Covered: [test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted][test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted] |

## Referral fee sharing

R1-R6,R9-R16,R18,R20; AE1-AE21,AE34. The API appends an explicit referrer to extend and its corresponding preview; BorrowPreview/ExtendPreview retain only the total fee F=P+R and existing position fields; neither exposes the protocol or referral component. Debt emits Borrowed/Extended with referrer, protocolFee P and referralFee R for the current operation; total F is their sum. Payout emits only delivery/defer events. Charge all current principal for requested terms; extend maturity only and preserve principal/collateral.

Defaults: borrower B has eligible collateral/debt, healthy pricing and usable services; O is B's current authorized operator; X differs from B,O with no grant. Actual execution caller pays F; borrowed OHM recipient is independently chosen for borrow. Referrer is never inferred from caller, borrower, principal recipient or an earlier operation. Unchanged includes Core/FLOAN/Inventory/DepositManager/cache, all token balances/allowances and every Payout category/index; rejected transactions commit no logs.

Debt is the Risk caller. extend and its preview call Risk.fee(snapshot,market,principal,terms,referrer) once for the two named outputs protocolFee P and referralFee R. Risk owns gross-curve math, whitelist validation and percentage allocation. Debt computes checked total F=P+R for maxFee and its existing total-fee result field, then passes P,r,R separately to Core. For extend, the Risk inputs use all current principal and requested extension terms.

Unit forwarding tests mock the two Risk outputs independently of loan economics (including splits that differ from any stored BPS setting) and mock only Core's settlement call. Assert exact snapshot, market, principal, terms, referrer and component arguments. The unit mock performs no fee transfer; real Core/Payout integration owns the cash-flow assertions. If Risk.fee reverts, Debt propagates its exact bytes and never calls Core settlement or Payout. Direct Core settlement does not call Risk. F,P,R are raw uint256 collateral units; referrer r is an address. No percentage or whitelist getter is read by Debt.

Retained baseline rows own grant expiry/revocation, mandatory fee-transfer failures, exact receipt and existing settlement guards. Risk.fee owns rounding/full-share examples; Payout.creditFee and transferPendingPayout own optional-delivery/callback accounting. New action cases below prove forwarding and loan-specific effects rather than repeating those suites.

Existing mappings above retain the baseline coverage after adapting the call signatures. Referral-specific mappings below identify the additional split, attribution, rejection and accounting assertions.

### Caller and referrer independence

All economic checks otherwise pass. Vary caller and attribution independently; existing baseline rows retain the deadline/expiry domains. Positive-referral success cases exclude the selected Payout address; its rejection and zero-allocation exception are covered below. Mock returned components P,R independently of loan economics; compute F=P+R for the total charge. Guarantee P=0 and R=0 on separate valid seeds. Referrer zero always pairs with R=0; a nonzero referrer can pair with R=0. Preview and execution return only total F and existing position fields; execution passes P,r,R and the actual payer unchanged to Core. BorrowPreview has four ABI fields and ExtendPreview has three, with no split fields.

| ID | Caller | Referrer | Operator grant | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-A15 | Borrower B or O; guarantee each | Allowed R, including R=B/O and unrelated frontend | B direct or valid B→O | Permissionless viewer quotes same total F without split fields | Success | Core instruction has payer=actual caller and the exact P,r,R returned by Risk; unit mock performs no transfers | Covered: [test_whenRiskReturnsComponents][test_whenRiskReturnsComponents], [test_whenZeroComponents][test_whenZeroComponents], [test_whenOneProtocolUnit][test_whenOneProtocolUnit], [test_whenOneReferralUnit][test_whenOneReferralUnit], [test_whenLiteralSplit][test_whenLiteralSplit], [test_whenMaximumProtocolComponent][test_whenMaximumProtocolComponent], [test_whenMaximumReferralComponent][test_whenMaximumReferralComponent], [test_whenReferrerIsBorrower][test_whenReferrerIsBorrower], [test_whenReferrerIsOperator][test_whenReferrerIsOperator], [test_whenReferrerVaries][test_whenReferrerVaries], [test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer][test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer] |
| BLEXT-EXTEND-A16 | Unrelated X≠B,O | Allowed R≠Payout; seed X=R | Only B→O valid; no B→X | X may quote B without authorization reads | IOperatorAuth.OperatorAuth_InvalidContext() | Unchanged; whitelist grants no execution authority | Covered: [test_givenOnlyOtherOperatorAuthorized_whenReferrerExtends_reverts][test_givenOnlyOtherOperatorAuthorized_whenReferrerExtends_reverts] |

### Risk results and combined fee limit

Own/action/dependency admission and earlier health checks pass. Risk.fee supplies both components directly. ReferrerNotAllowed is a Risk error propagated through the same call, not a local Debt or Core whitelist check. Risk's own fee matrix owns zero-share/zero-total eligibility rules; the real removal-between-preview-and-execution case below proves action wiring.

| ID | Caller | Referrer r | Risk.fee return | maxFee | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-I07 | B or O | Nonzero r | P≥0,R>0,F=P+R≤MAX256 | P≤maxFee<F; seed P,F-1 and fundable F maximum | BurnerLoans_FeeExceedsMax(F,maxFee) | Compare with combined charge F, not protocolFee alone; no settlement or Payout credit; Unchanged | Covered: [test_whenMaxFeeExcludesReferral_reverts][test_whenMaxFeeExcludesReferral_reverts], [test_whenFeeLimitEqualsProtocol_reverts][test_whenFeeLimitEqualsProtocol_reverts], [test_whenFeeLimitImmediatelyBelowTotal_reverts][test_whenFeeLimitImmediatelyBelowTotal_reverts], [test_whenMaximumTotalExceedsFeeLimit_reverts][test_whenMaximumTotalExceedsFeeLimit_reverts] |
| BLEXT-EXTEND-P11 | B or O | Zero | Return P=F,R=0; F fuzz0..fundable MAX256 | F or MAX256; seed equality | Returns total fee F without split fields | Core instruction carries P=F,r=0,R=0; retain existing zero-total skipping | Covered: [test_whenZeroReferrer][test_whenZeroReferrer] |
| BLEXT-EXTEND-P12 | B or O | Nonzero r accepted by Risk | Return P=R=0 | 0 | Total fee=0 without split fields | Risk.fee still called with r; Core instruction has both components zero; real settlement makes no fee transfer/Payout credit | Covered: [test_whenZeroComponents][test_whenZeroComponents], [test_givenZeroGrossFee_whenAllowedReferrerExtended][test_givenZeroGrossFee_whenAllowedReferrerExtended] |
| BLEXT-EXTEND-N12 | B or O | Nonzero r | Mock P fuzz1..MAX256 and R fuzz(MAX256-P+1)..MAX256; seed1/MAX256 and first overflow | MAX256 | Panic(0x11) from checked P+R | No Core settlement or Payout call; total must not wrap to bypass maxFee | Covered: [test_whenComponentSumOverflows_reverts][test_whenComponentSumOverflows_reverts], [test_whenMinimumProtocolOverflows_reverts][test_whenMinimumProtocolOverflows_reverts], [test_whenMaximumProtocolOverflows_reverts][test_whenMaximumProtocolOverflows_reverts] |

### Referral destination admission

All existing caller and lifecycle admission applies. Risk remains the calculator and whitelist owner.
Debt calls the selected Payout.validatePayoutRecipient(referrer) for positive referral allocations
in its shared quote path. Payout owns destination admission and uses that validator in settlement.
Debt does not duplicate destination, whitelist or percentage rules.

| ID | Caller | Referrer | Fee inputs | Preview | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-I09 | B or O; permissionless quote | Selected Payout; whitelisted for real integration | Mock P=0,R fuzz1..MAX256; seed1,MAX256; maxFee=MAX256. Real share=10000 with positive total | BurnerLoansPayout_InvalidRecipient(Payout) | Same error before Core settlement; Unchanged | Covered: [test_whenReferrerIsPayout_whenAllocationPositive_reverts][test_whenReferrerIsPayout_whenAllocationPositive_reverts], [test_whenOneUnitSelfReferral_reverts][test_whenOneUnitSelfReferral_reverts], [test_whenMaximumSelfReferral_reverts][test_whenMaximumSelfReferral_reverts], [test_givenWhitelistedPayout_whenPositiveReferral_reverts][test_givenWhitelistedPayout_whenPositiveReferral_reverts] |
| BLEXT-EXTEND-P17 | B or O; permissionless quote | Selected Payout; whitelisted for real integration | R=0,P fuzz0..MAX256; seed0,MAX256; maxFee=P. Real share=0 with positive total | Return total P | Forward unchanged P and zero R; real protocol payment succeeds; no self referral entitlement | Covered: [test_whenReferrerIsPayout_whenAllocationZero][test_whenReferrerIsPayout_whenAllocationZero], [test_whenSelfReferrerZeroFee][test_whenSelfReferrerZeroFee], [test_whenSelfReferrerMaximumProtocolFee][test_whenSelfReferrerMaximumProtocolFee], [test_givenWhitelistedPayout_whenReferralShareZero][test_givenWhitelistedPayout_whenReferralShareZero] |

### Successive operations and real integration

Use real Risk/Core/Payout for the rows in this section; whitelist/settings are actual state here. Core receives P,r,R separately and already has asset/borrower. It forwards creditFee(asset,P,r,R) to Payout without borrower metadata; Debt records the borrower and current fee allocation in its loan event. For token funding C=P+R, assert payer debit C, exact Payout receipt C, protocol allocation P and fixed-original referral allocation R. Neither Core nor Payout calls Risk for fees or whitelist validation.

Use real Risk/Core/Payout for accounting rows. Fuzz across the existing principal/terms domain with explicit type maxima retained in baseline cases; seed one raw fee unit and full fundable fee endpoints independently.

| ID | Caller | Prior attribution / configuration | Current attribution / change | Preview | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-P16 | B on borrow then O on extend | Borrow used approved R1; old R1 reward pending | Extension explicitly supplies approved R2≠R1 | Extension quotes current principal/terms and R2 only | Success | New extension reward belongs only to R2; old R1 unchanged; no position attribution state | Covered: [test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer][test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer] |
| BLEXT-EXTEND-P14 | B or O | Quote allowed R at S1 | Execute after ADMIN/BLRCT changes S1→S2 | Fresh quote uses S2 | Current split at S2; gross unaffected | Returns F; Debt event records new P2,r,R2; settles P2,R2; prior pending R1 amount fixed | Covered: [test_givenOldQuote_whenShareChangesBeforeExtension][test_givenOldQuote_whenShareChangesBeforeExtension] |
| BLEXT-EXTEND-I08 | B or O | Successful quote while R allowed | Removal executes before transaction | Original quote was valid; fresh quote rejects | BurnerLoansRisk_ReferrerNotAllowed(R) | Unchanged; caller can submit a new operation with zero | Covered: [test_givenReferrerRemovedAfterQuote_whenExtended_reverts][test_givenReferrerRemovedAfterQuote_whenExtended_reverts] |
| BLEXT-EXTEND-P15 | Fixed borrower B | Real prices / canonical market fee | F=101,S=2500 or real 6/18-decimal market | Independent total F | Success | Payer debit F; incoming Payout receipt F; exact original referrer and protocol remainder; Debt loan event identifies B, referrer and the new protocol/referral allocations P,R | Covered: [test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer][test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer] |

### Live Risk eligibility and upstream independence

All lending services are otherwise ready; caller B or O is authorized. These use real Risk rather than a membership-aware Debt mock.

| ID | Caller | Referrer | Risk configuration / upstream | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-D06 | B or O | Approved nonzero r | BLRCT paused/inactive or Risk operator changed; Risk operational; share configured | Same independently checked total F | Success; Risk uses its stored settings without upstream lifecycle lookup; Core/Payout have no Risk fee/whitelist call | Covered: [test_givenRiskOperatorChanged_whenExtended][test_givenRiskOperatorChanged_whenExtended], [test_givenRiskQueueLifecycle_whenExtended][test_givenRiskQueueLifecycle_whenExtended], [test_givenRiskQueueOperational_whenExtended][test_givenRiskQueueOperational_whenExtended], [test_givenRiskQueuePaused_whenExtended][test_givenRiskQueuePaused_whenExtended], [test_givenRiskQueueInactive_whenExtended][test_givenRiskQueueInactive_whenExtended], [test_givenRiskQueueInactivePaused_whenExtended][test_givenRiskQueueInactivePaused_whenExtended] |

### Transfer failures and callbacks

Token delivery is execution-only. Preview does not require payer funds/approval and cannot predict an outgoing delivery failure. Keep legacy mandatory fee callback cases and authorize nested calls enough to reach the guard.

| ID | Caller | Transfer / callback | Preview | Execution | Required proof | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T07 | B or O | Outgoing referral transfer rejected; protocol route accepts | Quotes total F | Success | Actual payer -F; funded pending referral R; protocol P delivered; no change in gross fee or action success | Covered: [test_givenReferralDeliveryRejected_whenExtended][test_givenReferralDeliveryRejected_whenExtended] |

### Risk-call failure propagation

Earlier borrower/action/health admission passes. Configure the reached Risk.fee selector to revert with independent bytes E: fuzz arbitrary revert payloads and guarantee empty data, BurnerLoansRisk_ReferrerNotAllowed(r), a custom error with arguments, and Panic(0x11). No translation, swallowing, zero-fee fallback, Core settlement, or Payout credit is permitted. A prior refreshSnapshot write must roll back with the failed outer execution. Preview performs no refresh and bubbles the same configured fee error under equal admission state.

| ID | Caller | Risk call | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLEXT-EXTEND-T10 | B or O | fee(snapshot,market,principal,terms,r) reverts with E | Bubble exact E | Bubble exact E | No Core settlement, token collection or Payout call; rollback earlier refresh and all state/logs | Covered: [test_whenRiskFeeReverts_reverts][test_whenRiskFeeReverts_reverts], [test_whenEmptyRiskError_reverts][test_whenEmptyRiskError_reverts], [test_whenTypedRiskError_reverts][test_whenTypedRiskError_reverts], [test_whenPanicRiskError_reverts][test_whenPanicRiskError_reverts], [test_givenStaleCache_whenRiskFeeFails_reverts][test_givenStaleCache_whenRiskFeeFails_reverts] |

- [x] Review the referral cases before writing tests.

## Authorization completion callbacks

| ID | Trigger | Expected result | Test |
| --- | --- | --- | --- |
| BLEXT-EXTEND-AUTH-C20 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts][test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts] |
| BLEXT-EXTEND-AUTH-C21 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts][test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts] |

[test_givenActionKernelGetterReverts_whenExtended_thenGetterIsNotRead]: extend.t.sol#L747
[test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts]: extend.t.sol#L1125
[test_givenAtDeadline_whenOperatorExtended_thenSuccessfulSettlement]: extend.t.sol#L1316
[test_givenBeforeDeadline_whenOperatorExtended_thenSuccessfulSettlement]: extend.t.sol#L1311
[test_givenBorrowReferrer_whenOperatorExtendsWithAnotherReferrer]: extendReferralIntegration.t.sol#L94
[test_givenCacheFullyRepays_whenExtensionReloads_thenNoDebtAndRollback]: extendPriceCallbacks.t.sol#L18
[test_givenCancelledGrant_whenOperatorActs_reverts]: extend.t.sol#L1103
[test_givenCaughtUnauthorizedCacheBorrow_whenExtending_thenOneExtension]: extendPriceCallbacks.t.sol#L39
[test_givenClampedHorizon_whenExpiryIsMaximum_thenNoTruncation]: extend.t.sol#L1258
[test_givenCollateralCallback_whenExtended_revertsAtomically]: extend.t.sol#L592
[test_givenCollateralWithNoDebt_whenExtended_reverts]: extend.t.sol#L1026
[test_givenCoreUnavailable_whenCalled_thenDependencyIdentified]: extend.t.sol#L1191
[test_givenCustodyInsolvent_whenExtended_reverts]: extend.t.sol#L814
[test_givenDebtDisabled_whenExtended_reverts]: extend.t.sol#L521
[test_givenDebtInactive_whenExtended_reverts]: extend.t.sol#L537
[test_givenDebtRoleRevoked_whenExtended_reverts]: extend.t.sol#L339
[test_givenDisabledDebtAction_whenCalled_thenPauseWins]: extend.t.sol#L1174
[test_givenExactHealthAndExpiryThresholds_whenExtended_thenAccepted]: extend.t.sol#L903
[test_givenExpiredCacheAndChangedPrice_whenExtended]: extendIntegration.t.sol#L85
[test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts]: extendIntegration.t.sol#L105
[test_givenExpiredGrant_whenOperatorActs_reverts]: extend.t.sol#L1067
[test_givenExpiredGrant_whenUnrelatedViewerQuotes]: extend.t.sol#L1452
[test_givenFeeAboveMaximum_whenExtended_reverts]: extend.t.sol#L426
[test_givenFeeAllowanceOneBelow_whenOperatorExtends_reverts]: extend.t.sol#L125
[test_givenFeeBalanceOneBelow_whenOperatorExtends_reverts]: extend.t.sol#L135
[test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts]: extendAuthorizationCallbacks.t.sol#L21
[test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts]: extendAuthorizationCallbacks.t.sol#L16
[test_givenFloanRejectsExtension_whenExtended_thenNoFeeOrExpiryChange]: extend.t.sol#L763
[test_givenGrantDeadline_whenUnrelatedViewerQuotes]: extend.t.sol#L1442
[test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified]: extend.t.sol#L1153
[test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError]: extend.t.sol#L1326
[test_givenInsufficientFeeAllowance_whenExtended_reverts]: extend.t.sol#L40
[test_givenInsufficientFeeBalance_whenExtended_reverts]: extend.t.sol#L64
[test_givenInventoryDisabled_whenExtended_thenSucceeds]: extend.t.sol#L298
[test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted]: extend.t.sol#L1059
[test_givenMaximumDeadline_whenOperatorExtended_thenSuccessfulSettlement]: extend.t.sol#L1321
[test_givenMaximumFundableUint256Fee_whenExtended_thenExactReceipt]: extend.t.sol#L727
[test_givenMaximumTimestamp_whenGrantExpired_reverts]: extend.t.sol#L1098
[test_givenMaximumUint128Fee_whenOperatorExtends_thenExactFeeIsSettled]: extend.t.sol#L293
[test_givenMaximumUint256Fee_givenUnfundedOperator_whenExtended_reverts]: extend.t.sol#L140
[test_givenNoDebt_whenExtended_reverts]: extend.t.sol#L412
[test_givenNoGrant_whenUnrelatedCallerActs_reverts]: extend.t.sol#L1117
[test_givenNoGrant_whenUnrelatedViewerQuotes]: extend.t.sol#L1421
[test_givenOldQuote_whenShareChangesBeforeExtension]: extendReferralIntegration.t.sol#L212
[test_givenOneSecondTerm_whenMaximumTermsExtended_thenNoTruncation]: extend.t.sol#L934
[test_givenOneUnitFee_whenExtended_thenExactFeeIsSettled]: extend.t.sol#L288
[test_givenOnlyOtherOperatorAuthorized_whenReferrerExtends_reverts]: extendReferral.t.sol#L250
[test_givenOriginationsDisabled_whenExtended_reverts]: extend.t.sol#L800
[test_givenOtherOperatorGrant_whenUnrelatedCallerExtends_reverts]: extend.t.sol#L320
[test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError]: extend.t.sol#L1350
[test_givenPayoutUnavailable_whenFeeBearingOperation_reverts]: extend.t.sol#L1296
[test_givenPolicyReactivated_whenExtendExecuted_thenSucceeds]: extend.t.sol#L1371
[test_givenPropagatedUnauthorizedCacheBorrow_whenExtending_thenRollback]: extendPriceCallbacks.t.sol#L55
[test_givenRealRisk_whenExtended_thenPerTermRoundingIsIndependent]: extendIntegration.t.sol#L19
[test_givenRealRisk_whenOneTermExtended_then314063Fee]: extendIntegration.t.sol#L27
[test_givenRealStalePrice_whenExtendQuotedOrExecuted_reverts]: extendIntegration.t.sol#L210
[test_givenRealTopUp_givenUpdatedTermLength_whenExtended]: extendIntegration.t.sol#L48
[test_givenRealTopUp_whenExtended]: extendIntegration.t.sol#L38
[test_givenReferralDeliveryRejected_whenExtended]: extendReferralIntegration.t.sol#L260
[test_givenReferrerRemovedAfterQuote_whenExtended_reverts]: extendReferralIntegration.t.sol#L186
[test_givenReportedKernelMismatch_whenExtended_thenGetterIsNotRead]: extend.t.sol#L735
[test_givenResultingExpiryEqualsNow_whenExtended_reverts]: extend.t.sol#L857
[test_givenResultingExpiryNotFuture_whenExtended_reverts]: extend.t.sol#L839
[test_givenRevokedGrant_whenUnrelatedViewerQuotes]: extend.t.sol#L1466
[test_givenRiskFee_whenExtended_thenExactFeeIsSettled]: extend.t.sol#L160
[test_givenRiskFee_whenLimitBelowFee_reverts]: extend.t.sol#L883
[test_givenRiskFee_whenOperatorExtends_thenExactFeeIsSettled]: extend.t.sol#L168
[test_givenRiskOperatorChanged_whenExtended]: extendReferralIntegration.t.sol#L325
[test_givenRiskQueueInactivePaused_whenExtended]: extendReferralIntegration.t.sol#L480
[test_givenRiskQueueInactive_whenExtended]: extendReferralIntegration.t.sol#L475
[test_givenRiskQueueLifecycle_whenExtended]: extendReferralIntegration.t.sol#L402
[test_givenRiskQueueOperational_whenExtended]: extendReferralIntegration.t.sol#L465
[test_givenRiskQueuePaused_whenExtended]: extendReferralIntegration.t.sol#L470
[test_givenStaleCache_whenRiskFeeFails_reverts]: extendReferralIntegration.t.sol#L294
[test_givenUnhealthyPosition_whenExtended_reverts]: extend.t.sol#L862
[test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached]: extend.t.sol#L1041
[test_givenValidGrant_whenUnrelatedViewerQuotes]: extend.t.sol#L1433
[test_givenValidOperatorGrant_whenExtended_thenActualOperatorPays]: extend.t.sol#L1211
[test_givenWhitelistedPayout_whenPositiveReferral_reverts]: extendReferralIntegration.t.sol#L36
[test_givenWhitelistedPayout_whenReferralShareZero]: extendReferralIntegration.t.sol#L57
[test_givenZeroFeeAllowance_whenBorrowerExtends_reverts]: extend.t.sol#L120
[test_givenZeroFeeAndMaximumLimit_whenExtended_thenNoCollection]: extend.t.sol#L981
[test_givenZeroFeeAndMaximumLimit_whenOperatorExtends_thenNoCollection]: extend.t.sol#L986
[test_givenZeroFeeAndNoWalletFunds_whenBorrowerExtends_thenNoCollection]: extend.t.sol#L973
[test_givenZeroFeeAndNoWalletFunds_whenOperatorExtends_thenNoCollection]: extend.t.sol#L964
[test_givenZeroFeeBalance_whenBorrowerExtends_reverts]: extend.t.sol#L130
[test_givenZeroFee_whenExtended_thenNoFeeHandoff]: extend.t.sol#L263
[test_givenZeroGrossFee_whenAllowedReferrerExtended]: extendReferralIntegration.t.sol#L349
[test_whenAnyViewerQuotesWithoutAuthorizationRead]: extend.t.sol#L1385
[test_whenAuthorizationEndpoints_thenAdmissionIsInclusive]: extend.t.sol#L1236
[test_whenBorrowerZero_thenExplicitError]: extend.t.sol#L1140
[test_whenComponentSumOverflows_reverts]: extendReferral.t.sol#L205
[test_whenEmptyRiskError_reverts]: extendReferral.t.sol#L314
[test_whenFeeLimitEqualsProtocol_reverts]: extendReferral.t.sol#L357
[test_whenFeeLimitImmediatelyBelowTotal_reverts]: extendReferral.t.sol#L362
[test_whenLiteralSplit]: extendReferral.t.sol#L293
[test_whenMaxFeeExcludesReferral_reverts]: extendReferral.t.sol#L177
[test_whenMaximumProtocolComponent]: extendReferral.t.sol#L298
[test_whenMaximumProtocolOverflows_reverts]: extendReferral.t.sol#L377
[test_whenMaximumReferralComponent]: extendReferral.t.sol#L303
[test_whenMaximumSelfReferral_reverts]: extendReferral.t.sol#L62
[test_whenMaximumTermsExceedHorizon_reverts]: extend.t.sol#L475
[test_whenMaximumTotalExceedsFeeLimit_reverts]: extendReferral.t.sol#L367
[test_whenMinimumProtocolOverflows_reverts]: extendReferral.t.sol#L372
[test_whenOneProtocolUnit]: extendReferral.t.sol#L283
[test_whenOneReferralUnit]: extendReferral.t.sol#L288
[test_whenOneUnitSelfReferral_reverts]: extendReferral.t.sol#L57
[test_whenPanicRiskError_reverts]: extendReferral.t.sol#L329
[test_whenReferrerIsBorrower]: extendReferral.t.sol#L334
[test_whenReferrerIsOperator]: extendReferral.t.sol#L340
[test_whenReferrerIsPayout_whenAllocationPositive_reverts]: extendReferral.t.sol#L27
[test_whenReferrerIsPayout_whenAllocationZero]: extendReferral.t.sol#L67
[test_whenReferrerVaries]: extendReferral.t.sol#L348
[test_whenRiskFeeReverts_reverts]: extendReferral.t.sol#L217
[test_whenRiskReturnsComponents]: extendReferral.t.sol#L86
[test_whenSelfReferrerMaximumProtocolFee]: extendReferral.t.sol#L81
[test_whenSelfReferrerZeroFee]: extendReferral.t.sol#L76
[test_whenTermsAreZero_reverts]: extend.t.sol#L398
[test_whenTermsExceedHorizon_reverts]: extend.t.sol#L454
[test_whenTypedRiskError_reverts]: extendReferral.t.sol#L319
[test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted]: extend.t.sol#L1481
[test_whenZeroComponents]: extendReferral.t.sol#L278
[test_whenZeroReferrer]: extendReferral.t.sol#L308
