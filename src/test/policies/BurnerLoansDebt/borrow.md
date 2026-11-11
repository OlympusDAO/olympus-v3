# BurnerLoansDebt.borrow coverage plan

Authorization migration: grants now live on the selected BurnerLoansAuth. The public caller is the actual operator. Zero operator identities reject with `OperatorAuth_InvalidIdentity`; other absent/cancelled authority rejects with `OperatorAuth_InvalidContext`; expired accepted grants reject with `OperatorAuth_ExpiredGrant(deadline)`. An expired grant does not block permissionless previews. Cancelled-grant fixtures use nonzero operators because zero-operator grants cannot be created. Canonical permissions bind the explicit market asset, including custom callback tokens.

> Referral scenarios below supplement the retained baseline. Their mappings identify the additional assertions for the extended API.

Source: [borrow](../../../policies/burnerloans/BurnerLoansDebt.sol#L60). Scenarios specify the required behavior; mappings identify existing test proof.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLDEBT-BORROW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansDebt; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Implemented recipient rule: reject recipient=address(this) with BurnerLoans_InvalidParam() before Risk refresh or Core settlement. User-facing actions accepting an explicit output recipient cannot pay their own address; unit tests prove that no fee collection, funding or debt creation occurs for this rejection.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Defaults: `onBehalfOf_` is the nonzero borrower; execution is authorized, collateral C>0, asset originations enabled, Inventory enabled; DM solvent. G is Inventory.availableCapacity(), bounded by global cap room and idle OHM plus mint approval; asset room A varies independently. amount OHM uint128, fee collateral uint256, health WAD, maturity uint48.

Baseline fee cases use referrer=address(0) and Risk outputs (protocolFee,referralFee)=(F,0), unless a referral row overrides them. Core receives separate (F,address(0),0) allocation fields. Debt returns total fee F; Borrowed/Extended identify protocolFee=F, referrer=0 and referralFee=0. Payout means BurnerLoansPayout, separate from DepositManager collateral custody.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

Inventory owns the capacity error: both this action/preview precheck and Inventory.draw use `IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity(requested,available)`. Check Inventory capacity before asset debt room; retain Inventory's authoritative draw-time enforcement.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Preview is permissionless and validates `onBehalfOf_`/inputs; execution separately authenticates its caller; no quote writes | Covered: [test_whenBorrowed_thenPrincipalAndMaturityAreCanonical][test_whenBorrowed_thenPrincipalAndMaturityAreCanonical], [test_givenPolicyReactivated_whenBorrowExecuted_thenSucceeds][test_givenPolicyReactivated_whenBorrowExecuted_thenSucceeds], [test_givenReEnabled_whenBorrowExecuted_thenSucceeds][test_givenReEnabled_whenBorrowExecuted_thenSucceeds] |
| BLDEBT-BORROW-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-BORROW-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-BORROW-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-BORROW-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-BORROW-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-BORROW-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-BORROW-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-BORROW-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-BORROW-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |

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
| BLDEBT-BORROW-A01 | Borrower | caller=borrower; no operator grant | `Authorized` | Payer is the actual caller | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_whenBorrowed_thenPrincipalAndMaturityAreCanonical][test_whenBorrowed_thenPrincipalAndMaturityAreCanonical], [test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLDEBT-BORROW-A02 | Delegated operator | caller=operator; grant issued at time1; independently fuzz deadline D in 2..MAX48 and now in 1..D-1; seed now=1,D-1 and D=MAX48 | `Authorized` | Borrower debt/maturity changes; actual caller funds any mandatory fee | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays][test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenBeforeDeadline_whenOperatorBorrowed_thenSuccessfulSettlement][test_givenBeforeDeadline_whenOperatorBorrowed_thenSuccessfulSettlement], [test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement][test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A03 | Delegated operator | caller=operator; now=deadline; grant nonzero | `Authorized` | Deadline equality accepted | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays][test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted][test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted], [test_givenAtDeadline_whenOperatorBorrowed_thenSuccessfulSettlement][test_givenAtDeadline_whenOperatorBorrowed_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A04 | Delegated operator | caller=operator; deadline=MAX48; now<=deadline | `Authorized` | No deadline narrowing | Any viewer quotes the same economics; no borrower/operator authorization read | Covered: [test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays][test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays], [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached][test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached], [test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted][test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted], [test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement][test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead] |
| BLDEBT-BORROW-A05 | Fuzz all callers | borrower=0; actual caller arbitrary | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerZero_thenExplicitError][test_whenBorrowerZero_thenExplicitError] |
| BLDEBT-BORROW-A06 | Fuzz callers excluding borrower | caller differs from borrower; no grant | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenNoGrant_whenUnrelatedCallerActs_reverts][test_givenNoGrant_whenUnrelatedCallerActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A07 | Fuzz callers excluding borrower | caller differs from borrower; grant cancelled to zero | `OperatorAuth_InvalidContext()` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_givenCancelledGrant_whenOperatorActs_reverts][test_givenCancelledGrant_whenOperatorActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A08 | Delegated operator | caller=operator; grant nonzero; independently fuzz stored deadline D in 1..MAX48 and now in D+1..MAX256; seed D+1,MAX48+1,MAX256 | `OperatorAuth_ExpiredGrant(D)` | Unchanged; no committed logs | Permissionless: ignore the grant and evaluate current input/economic checks; valid inputs return the quote | Covered: [test_whenAuthorizationEndpoints_thenAdmissionIsInclusive][test_whenAuthorizationEndpoints_thenAdmissionIsInclusive], [test_givenExpiredGrant_whenOperatorActs_reverts][test_givenExpiredGrant_whenOperatorActs_reverts], [test_givenMaximumTimestamp_whenGrantExpired_reverts][test_givenMaximumTimestamp_whenGrantExpired_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A11 | Fuzz unrelated caller X | Borrower B has a valid grant to O; O differs from B; X differs from B and O and has no grant; independently fuzz deadline D in 2..MAX48 and now in 1..D; seed now=1,D and D=MAX48 | `OperatorAuth_InvalidContext()` | B→O grant unchanged; no position, balance or accounting change; no committed logs | X receives the same quote as B under equal economic state; the B→O grant does not restrict quoting | Covered: [test_givenOtherOperatorGrant_whenUnrelatedCallerBorrows_reverts][test_givenOtherOperatorGrant_whenUnrelatedCallerBorrows_reverts], [test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts][test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts], [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes] |

## Core settlement authorization

Operational action and Core; borrower/operator authorization passes. Core requires only the action's `BL_DEBT_POLICY_ROLE`, independently of the borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-A09 | Borrower | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test_givenActionRoleRevoked_whenBorrowed_reverts][test_givenActionRoleRevoked_whenBorrowed_reverts] |
| BLDEBT-BORROW-A10 | Borrower or authorized operator | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return BorrowPreview(fee,D+amount,H,maturity) | Fund the requested OHM once; increase principal and collect the exact accepted fee; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead][test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead], [test_givenBorrower_whenActionReportedKernelMismatches][test_givenBorrower_whenActionReportedKernelMismatches], [test_givenOperator_whenActionReportedKernelMismatches][test_givenOperator_whenActionReportedKernelMismatches], [test_givenBorrower_whenActionKernelGetterReverts][test_givenBorrower_whenActionKernelGetterReverts], [test_givenOperator_whenActionKernelGetterReverts][test_givenOperator_whenActionKernelGetterReverts] |

## Dependency lifecycle

Action and Core active/enabled; borrower authorized; positive otherwise-valid amount and valid prices. Keep other dependencies ready while varying the named state. Every rejection leaves accounting and committed logs unchanged.

| ID | Caller | Originations enabled | Inventory active | Inventory enabled | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-D04 | Borrower | false | true | true | `BurnerLoansCore_AssetOriginationsDisabled(asset)` | Same error; no writes | Covered: [test_givenInventoryUnavailable_whenBorrowed_reverts][test_givenInventoryUnavailable_whenBorrowed_reverts], [test_givenOriginationsDisabled_whenBorrowed_reverts][test_givenOriginationsDisabled_whenBorrowed_reverts] |
| BLDEBT-BORROW-D05 | Borrower | true | true | false | `PolicyDependency_NotActive(Inventory)` | Same error; no writes | Covered: [test_givenInventoryUnavailable_whenBorrowed_reverts][test_givenInventoryUnavailable_whenBorrowed_reverts] |
| BLDEBT-BORROW-P06 | Borrower | true | false | true | `PolicyDependency_NotActive(Inventory)` | Same error even when idle OHM covers the requested amount | Covered: [test_givenInventoryUnavailable_whenBorrowed_reverts][test_givenInventoryUnavailable_whenBorrowed_reverts] |
| BLDEBT-BORROW-D06 | Borrower | true | false | false | `PolicyDependency_NotActive(Inventory)` | Same error; no writes | Covered: [test_givenInventoryUnavailable_whenBorrowed_reverts][test_givenInventoryUnavailable_whenBorrowed_reverts] |

P06 requires per-action Inventory admission even with idle funding; enable-time validation alone is insufficient.

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-I01 | Borrower | recipient=0; amount>0 | `BurnerLoans_ZeroAddress()` | Same BurnerLoans_ZeroAddress() | Covered: [test_whenRecipientZero_reverts][test_whenRecipientZero_reverts] |
| BLDEBT-BORROW-I02 | Borrower | recipient=BurnerLoansDebt (address(this)); positive amount and other inputs valid | `BurnerLoans_InvalidParam()` | Same BurnerLoans_InvalidParam() | Covered: [test_whenRecipientIsAction_reverts][test_whenRecipientIsAction_reverts] |
| BLDEBT-BORROW-I03 | Borrower | Snapshot refresh price invalid | `BurnerLoans_InvalidPrice()` | Require equivalent pricing validity and validation precedence for the same quote context; retain read-only behavior | Covered: [test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts][test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts] |
| BLDEBT-BORROW-I04 | Borrower | Position collateral=0 | `BurnerLoans_NoCollateral()` | Same BurnerLoans_NoCollateral() with all earlier preview checks satisfied; assert no writes | Covered: [test_givenNoCollateral_whenBorrowed_reverts][test_givenNoCollateral_whenBorrowed_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-N01 | Borrower | amount=0; recipient nonzero | `BurnerLoansCore_ZeroAmount()` | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAmountZero_reverts][test_whenAmountZero_reverts] |
| BLDEBT-BORROW-N02 | Borrower | Global room G<MAX128; fuzz amount G+1..MAX128; seed G+1,MAX128 | `BurnerLoansInventory_InsufficientCapacity(amount,G)` | Same BurnerLoansInventory_InsufficientCapacity(amount,G) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenGlobalCapacityEndpointsRejected_thenExactError][test_whenGlobalCapacityEndpointsRejected_thenExactError], [test_givenGlobalCap_whenRequestExceedsRoom_reverts][test_givenGlobalCap_whenRequestExceedsRoom_reverts] |
| BLDEBT-BORROW-N03 | Borrower | Global room sufficient; asset room A<MAX128; fuzz amount A+1..MAX128; seed A+1,MAX128 | `BurnerLoans_AssetDebtCapExceeded(asset,amount,A)` | Same BurnerLoans_AssetDebtCapExceeded(asset,amount,A) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAssetCapacityEndpointsRejected_thenExactError][test_whenAssetCapacityEndpointsRejected_thenExactError], [test_givenAssetCap_whenRequestExceedsRoom_reverts][test_givenAssetCap_whenRequestExceedsRoom_reverts] |
| BLDEBT-BORROW-N04 | Borrower | Fee F>0; fuzz maxFee 0..F-1; seed 0,F-1 | `BurnerLoans_FeeExceedsMax(F,maxFee)` | Same BurnerLoans_FeeExceedsMax(F,maxFee) | Covered: [test_whenFeeLimitEndpointsRejected_thenExactError][test_whenFeeLimitEndpointsRejected_thenExactError], [test_givenFee_whenMaxFeeTooLow_reverts][test_givenFee_whenMaxFeeTooLow_reverts] |

## Position and solvency validation

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-P01 | Borrower | DM assets+borrowed < liabilities | `BurnerLoansCore_Insolvent(asset,liabilities,assets,borrowed)` | Same solvency error and accounting arguments; no writes | Covered: [test_givenInsolventOperatorCustody_whenBorrowed_reverts][test_givenInsolventOperatorCustody_whenBorrowed_reverts] |
| BLDEBT-BORROW-P02 | Borrower | Existing debt>0; expiry M=maturity; fuzz now in M..MAX256; seed M,M+1,MAX256 | `BurnerLoans_PositionExpired(maturity)` | Same BurnerLoans_PositionExpired(maturity) with all earlier preview checks satisfied; assert no writes | Covered: [test_whenExpiryEndpointsRejected_thenExactError][test_whenExpiryEndpointsRejected_thenExactError], [test_givenExpiredDebt_whenBorrowed_reverts][test_givenExpiredDebt_whenBorrowed_reverts] |
| BLDEBT-BORROW-P03 | Borrower | Both global and asset rooms insufficient | `BurnerLoansInventory_InsufficientCapacity(amount,G)` | Same BurnerLoansInventory_InsufficientCapacity(amount,G) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenGlobalCap_whenRequestExceedsRoom_reverts][test_givenGlobalCap_whenRequestExceedsRoom_reverts], [test_givenBothCapsInsufficient_whenBorrowed_reverts][test_givenBothCapsInsufficient_whenBorrowed_reverts] |
| BLDEBT-BORROW-P12 | Borrower | Global cap=MAX128, principal=0, idle=0; MINTR approval=50e9; request=51e9; asset room sufficient | `BurnerLoansInventory_InsufficientCapacity(51e9,50e9)` | Same Inventory error; unchanged quote state | Covered: [test_givenMintApprovalLimitsCapacity_whenBorrowed_reverts][test_givenMintApprovalLimitsCapacity_whenBorrowed_reverts] |
| BLDEBT-BORROW-P04 | Borrower | Current health H<1e18 | `BurnerLoans_UnhealthyPosition(H)` | Revert BurnerLoans_UnhealthyPosition(H) for current health below 1e18 | Covered: [test_givenUnhealthyCurrentPosition_whenBorrowed_reverts][test_givenUnhealthyCurrentPosition_whenBorrowed_reverts] |
| BLDEBT-BORROW-P05 | Borrower | Current health>=1e18; resulting health H<1e18 | `BurnerLoans_UnhealthyFinalPosition(H)` | Revert BurnerLoans_UnhealthyFinalPosition(H) for resulting health below 1e18 | Covered: [test_givenUnhealthyFinalPosition_whenBorrowed_reverts][test_givenUnhealthyFinalPosition_whenBorrowed_reverts] |

## Numeric boundaries and successful borrowing

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-N05 | Borrower | First debt episode; positive amount within both caps and health capacity; seed 1 and MAX128 when constructible | `Principal=amount; maturity=now+term; quoted fee/health` | FLOAN market/facility totals and Inventory active principal +amount; recipient receives amount; Borrowed | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_whenBorrowed_thenPrincipalAndMaturityAreCanonical][test_whenBorrowed_thenPrincipalAndMaturityAreCanonical], [test_whenOneRawOhmBorrowed_thenNoTruncation][test_whenOneRawOhmBorrowed_thenNoTruncation], [test_whenMaximumPrincipalBorrowed_thenNoTruncation][test_whenMaximumPrincipalBorrowed_thenNoTruncation] |
| BLDEBT-BORROW-N06 | Borrower | Active top-up; D+amount<=MAX128 | `Principal=D+amount; existing maturity unchanged` | Same accounting deltas; no new term | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExistingDebt_whenToppedUp_thenExpiryPreserved][test_givenExistingDebt_whenToppedUp_thenExpiryPreserved], [test_givenMaximumTopUp_whenBorrowed_thenNoPrincipalTruncation][test_givenMaximumTopUp_whenBorrowed_thenNoPrincipalTruncation], [test_givenLaterBlockTopUp_whenRepaidInThatBlock_reverts][test_givenLaterBlockTopUp_whenRepaidInThatBlock_reverts], [test_givenDebtBearingPosition_whenBorrowIsPreviewed_thenActionResultMatches][test_givenDebtBearingPosition_whenBorrowIsPreviewed_thenActionResultMatches] |
| BLDEBT-BORROW-N07 | Borrower | Previous episode fully repaid; collateral retained | `New maturity=now+currentTerm` | New debt episode with current risk/config | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenFullyRepaidEpisode_whenBorrowed_thenNewTermStartsNow][test_givenFullyRepaidEpisode_whenBorrowed_thenNewTermStartsNow] |
| BLDEBT-BORROW-N08 | Borrower | maxFee exactly equals mocked Risk fee F | `Success` | Collect exactly the F returned by Risk from actual caller | Quote the same mocked F; action returns and forwards F unchanged | Covered: [test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt][test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt] |
| BLDEBT-BORROW-N09 | Borrower | maxFee>F; fuzz F+1..MAX256 when F<MAX256 | `Success` | Never collect maxFee instead of F | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt][test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt], [test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt][test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt], [test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt][test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt] |

## Risk fee and Payout handoff

Mock Risk.fee to return (F,0) in native collateral-token units with referrer=address(0). Hold the borrow amount, snapshot and market configuration fixed while varying F; use values unrelated to the real formula, including one raw collateral unit. Assert that Debt calls Risk.fee with the captured snapshot, canonical market ID, requested OHM amount, one term and zero referrer. Its Core BorrowRequest carries protocolFee=F, referrer=0 and referralFee=0; the result returns total F and Borrowed reports the same split. Debt must not recalculate, rescale, round or replace F with maxFee.

For collection assertions, use real Core settlement and mock only Payout.creditFee to accept the handoff without an outgoing payout. Assert the actual caller's balance decreases by F, selected Payout's balance increases by F, and Core calls Payout.creditFee(asset,F,address(0),0) exactly once after receipt. This proves delivery to Custody and delegation of distribution without testing its destination selection or payout implementation. Fuzz payer between borrower and a distinct unexpired operator; guarantee both. An operator-funded borrow preserves the borrower's wallet. Keep principal recipient independent. Fuzz positive F over the fixture's full fundable range with representable token supply; seed 1 and the maximum fundable F. Fee=MAX256 with insufficient funds belongs to T06; maxFee=MAX256 is independently covered by N09.

| ID | Caller / payer | Mock Risk fee / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-P09 | Fuzz borrower or unexpired operator | Arbitrary F>0; maxFee>=F; otherwise fixed valid economics; Payout handoff accepts | Return exactly Risk's F; borrow succeeds | Core instruction (protocolFee,referrer,referralFee)=(F,address(0),0); payer -F; selected Payout +F and one creditFee(asset,F,address(0),0) call; Borrowed caller and (protocolFee=F,referrer=0,referralFee=0) match; principal funded once; collateral credit and DM liabilities unchanged | Preview returns the same mocked F without transfers or Payout credit | Covered: [test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody], [test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt][test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt], [test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt][test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt], [test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt][test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt] |
| BLDEBT-BORROW-P11 | Fuzz borrower or unexpired operator | Risk returns F=0; payer collateral balance/allowance=0; maxFee=0 or MAX256 | Return fee 0; borrow succeeds | Core instruction (protocolFee,referrer,referralFee)=(0,address(0),0); no fee transferFrom or Payout.creditFee call; Borrowed protocolFee=0,referrer=0,referralFee=0; principal funded once | Quote fee 0; no collateral approval/balance requirement | Covered: [test_givenZeroFee_whenBorrowed_thenNoApprovalOrFeeHandoff][test_givenZeroFee_whenBorrowed_thenNoApprovalOrFeeHandoff], [test_givenZeroFee_whenOperatorBorrows_thenNoApprovalOrFeeHandoff][test_givenZeroFee_whenOperatorBorrows_thenNoApprovalOrFeeHandoff] |

N04, N08 and N09 compare maxFee against the mocked Risk result: reject below F, accept equality and accept larger limits through MAX256 while collecting only F. [Risk.fee scenarios](../BurnerLoansRisk/fee.md) prove the actual formula and rounding; real Risk integration below proves calculation and wiring together. [Payout.creditFee scenarios](../BurnerLoansPayout/creditFee.md) own Treasury/distributor selection, outgoing delivery, accumulated pending fees and retries.

## Transfer and funding failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-T02 | Borrower | Fee collection into Custody returns false | `SafeERC20FailedOperation(asset)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_whenFeeTransferReturnsFalse_thenDebtRollsBack][test_whenFeeTransferReturnsFalse_thenDebtRollsBack] |
| BLDEBT-BORROW-T03 | Borrower | Custody fee receipt inexact | `SafeERC20Exact_InexactTransferFrom(asset,Custody,fee,received)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_whenFeeReceiptInexact_thenDebtRollsBack][test_whenFeeReceiptInexact_thenDebtRollsBack] |
| BLDEBT-BORROW-T04 | Fuzz borrower or unexpired operator | F>0 transferred to Custody and credited, then Inventory draw fails | `Exact injected Inventory error` | Fee receipt/credit, FLOAN debt/maturity and payer/Custody/Inventory balances and allowances roll back; no committed logs | Quote F without actual collection; execution alone proves transfer rollback | Covered: [test_givenFeeDelivered_whenFundingFails_thenEverythingRollsBack][test_givenFeeDelivered_whenFundingFails_thenEverythingRollsBack] |
| BLDEBT-BORROW-T05 | Fuzz borrower or unexpired operator | F>0; payer→Core allowance L in 0..F-1; seed 0,F-1; sufficient payer balance; standard OZ token | `ERC20InsufficientAllowance(Core,L,F)` | No fee delivery, debt, funding, pending-bucket or allowance change; no committed logs | Quote F without token collection; action alone checks allowance at transferFrom | Covered: [test_whenFeeCollectionEndpoints_thenCompleteRollback][test_whenFeeCollectionEndpoints_thenCompleteRollback], [test_givenInsufficientAllowance_whenEitherPayerBorrows_thenFullFeeDomainRollsBack][test_givenInsufficientAllowance_whenEitherPayerBorrows_thenFullFeeDomainRollsBack], [test_givenInsufficientFeeAllowance_whenBorrowed_reverts][test_givenInsufficientFeeAllowance_whenBorrowed_reverts], [test_givenOperatorAllowanceOneBelowFee_whenBorrowed_reverts][test_givenOperatorAllowanceOneBelowFee_whenBorrowed_reverts] |
| BLDEBT-BORROW-T06 | Fuzz borrower or unexpired operator | F>0; payer balance B in 0..F-1 with representable total supply; seed 0,F-1 when constructible and F=MAX256; sufficient allowance; standard OZ token | `ERC20InsufficientBalance(payer,B,F)` | No fee, debt, funding or pending-bucket change; any allowance debit rolls back | Quote F without token collection; action alone checks actual balance at transferFrom | Covered: [test_whenFeeCollectionEndpoints_thenCompleteRollback][test_whenFeeCollectionEndpoints_thenCompleteRollback], [test_givenMaximumFee_whenPayerUnfunded_reverts][test_givenMaximumFee_whenPayerUnfunded_reverts], [test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack][test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack], [test_givenMaximumFeeAndZeroBalance_whenOperatorBorrows_reverts][test_givenMaximumFeeAndZeroBalance_whenOperatorBorrows_reverts] |
| BLDEBT-BORROW-T07 | Fuzz borrower or unexpired operator | Mock Risk.fee rejects; earlier lifecycle, position and health checks pass | Exact configured Risk error | No Core settlement, fee collection, debt change or funding; no committed logs | Same configured fee-calculation error from preview | Covered: [test_givenRiskFeeFailure_whenBorrowed_reverts][test_givenRiskFeeFailure_whenBorrowed_reverts] |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee and health responses. Use the independently configured mock fee F as the expectation for maxFee validation, Core's settlement instruction, actual collection, Payout.creditFee, the return value and Borrowed. Checking only action-versus-preview equality is insufficient: both must equal F. Risk's own suite proves arithmetic; real Risk integration proves the complete calculation path.

Test operator=recipient, borrower=recipient and independent recipient. The preview validates the same operation context. Health validation reverts with the same error and calculated health argument as the action. Token transfers remain execution-only. Same-block top-up updates lastBorrowBlock; later repayment in that block is rejected. Mandatory transfer callbacks must reject an otherwise-valid nested settlement and roll back the outer transaction when the token propagates the failure. Custody's suite owns fail-soft outgoing payout assertions.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Retain operator payer isolation, unchanged maturity when governance lowers the horizon below an existing loan maturity, same-block top-ups and MINTR callbacks in action tests. Port pre-borrow utilization at the kink, market-versus-global utilization, one-raw-OHM-unit fees and collateral/OHM/PRICE decimal combinations to Risk's arithmetic suite and real Risk integration. Custody's suite owns zero credits preserving old reserves and pending-fee sweeps.

## Real Risk integration

Use borrowIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/payout dependencies. Use a fixed borrower caller because authorization is covered in unit scenarios. Independently calculate the fee from prices, decimal scales, pre-borrow utilization and rounding; assert the real Risk result, Debt return/event, payer debit and incoming Payout transfer all equal that fee. Observe the incoming transfer even if real Custody subsequently distributes it; its final balance need not retain the fee. Destination and payout outcomes remain Custody's responsibility. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-P07 | Borrower | Valid real snapshot; compatible payout/funding; fee kink/rounding and decimal-scale boundary seeds from legacy math tests | Successful operation | Independently calculated fee equals real Risk.fee, Debt total return/Borrowed protocolFee, actual payer debit and incoming Payout transfer; principal/collateral and WAD health also match independent expectations | Same real fee and health under unchanged prices, utilization and conversion; no preview writes | Covered: [test_givenRealRisk_whenBorrowed_thenIndependentFeesAndHealth][test_givenRealRisk_whenBorrowed_thenIndependentFeesAndHealth], [test_givenPreBorrowUtilizationAtKink_whenBorrowed_then125Bps][test_givenPreBorrowUtilizationAtKink_whenBorrowed_then125Bps], [test_givenPreBorrowUtilizationAboveKink_whenBorrowed_then575Bps][test_givenPreBorrowUtilizationAboveKink_whenBorrowed_then575Bps], [test_givenGlobalUtilizationAtKink_whenMarketBelowKink_thenMarketRate][test_givenGlobalUtilizationAtKink_whenMarketBelowKink_thenMarketRate], [test_givenOneRawOhmUnit_whenBorrowed_thenFeeRoundsUpToOneCollateralUnit][test_givenOneRawOhmUnit_whenBorrowed_thenFeeRoundsUpToOneCollateralUnit], [test_givenEightDecimalCollateralAndPrice_whenBorrowed_thenNativeFeeUnits][test_givenEightDecimalCollateralAndPrice_whenBorrowed_thenNativeFeeUnits] |
| BLDEBT-BORROW-P08 | Borrower | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts][test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts] |

## Additional economic regression coverage

Use real Risk, Core, FLOAN and Inventory. Governance selects the production PriceCache; the borrower does not select or authorize it. Its refresh has no arbitrary borrower-action callback. Existing callback-cache cases are adversarial tests using a synthetic implementation and, where needed, a separate explicit borrower operator grant; they are not a supported cache integration requirement.

| ID | Caller | Pre-state / input | Expected outcome | Required accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-P13 | Second borrower | First borrower owes 100 OHM in the same market; second borrows 100 OHM | Fee 314063 raw collateral units at pre-borrow market utilization 0.1% | First position unchanged; second debt 100 OHM; market/global debt 200 OHM; custody covers both; preview and execution agree | Covered: [test_givenAnotherBorrowerDebt_whenBorrowed][test_givenAnotherBorrowerDebt_whenBorrowed] |
| BLDEBT-BORROW-P14 | Second borrower | Same-market cap 150 OHM; first owes 100; request 51 | AssetDebtCapExceeded(asset,51e9,50e9) | Both positions, market/global totals, balances and allowances unchanged; preview rejects identically | Covered: [test_givenAnotherBorrowerDebt_whenSharedMarketCapExceeded_reverts][test_givenAnotherBorrowerDebt_whenSharedMarketCapExceeded_reverts] |
| BLDEBT-BORROW-P15 | Borrower | Another market already owes 100 OHM; global cap 150; request 51 in a market with room | Inventory InsufficientCapacity(51e9,50e9) | Both markets and wallets unchanged; preview rejects identically | Covered: [test_givenAnotherMarketDebt_whenSharedGlobalCapExceeded_reverts][test_givenAnotherMarketDebt_whenSharedGlobalCapExceeded_reverts] |
| BLDEBT-BORROW-P16 | Borrower | Another market owes 100 OHM; this market has zero debt and identical configuration | Borrow 100 OHM for fee 312500 raw units | Market utilization excludes other markets; unrelated position unchanged; each market owes 100 OHM and Inventory owes 200 | Covered: [test_givenAnotherMarketDebt_whenBorrowed][test_givenAnotherMarketDebt_whenBorrowed] |
| BLDEBT-BORROW-P17 | Borrower | Quote 100 OHM with collateral at USD 1; cache expires and fresh PRICE collateral becomes USD 0.5 | Execute for fee 625000 with maxFee 625000 | Read-only fresh preview agrees; real cache refreshed once; debt/funding applied once; exact fee debit | Covered: [test_givenExpiredCacheAndChangedPrice_whenBorrowed][test_givenExpiredCacheAndChangedPrice_whenBorrowed] |
| BLDEBT-BORROW-P18 | Borrower | Same price movement; retain original quoted maxFee 312500 | FeeExceedsMax(625000,312500) | Preview rejects without cache writes; execution rolls back refresh, positions, balances, allowances and funding | Covered: [test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts][test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts] |

## Adversarial cache callbacks before settlement

These cases use the test-only BurnerLoansCallbackCache, not production PriceCache. The fixture selects it using admin authority, then separately grants it borrower operator authority for nested authorized actions. This probes a synthetic hostile dependency; it does not establish callback support as a cache integration requirement. Core's transfer guard is not entered during Risk.refreshSnapshot, so these existing cases describe current behavior before settlement.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenUnauthorizedCacheAction_whenCaught_thenOuterSucceeds][test_givenUnauthorizedCacheAction_whenCaught_thenOuterSucceeds] |
| BLDEBT-BORROW-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenUnauthorizedCacheAction_whenPropagated_thenOuterRollsBack][test_givenUnauthorizedCacheAction_whenPropagated_thenOuterRollsBack] |

Retired BLDEBT-BORROW-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Post-refresh position and cap checks

Retired BLDEBT-BORROW-C01 grouped different outcomes. Configure a one-shot cache callback that can borrow using a valid grant and exact fee/funding approvals. All other checks pass; amounts below are positive and independently fuzzed within representable accounting.

| ID | Caller | Nested operation / live state | Outer result | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-C05 | Borrower | Nested borrow succeeds but leaves global available capacity R below outer amount A; asset room and health sufficient | BurnerLoansInventory_InsufficientCapacity(A,R) | Nested debt/funding/fee/cache writes and logs roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheBorrows_whenGlobalRoomConsumed_thenOuterRechecksAndRollsBack][test_givenCacheBorrows_whenGlobalRoomConsumed_thenOuterRechecksAndRollsBack] |
| BLDEBT-BORROW-C06 | Borrower | Nested borrow leaves asset room R below outer A; global room and health sufficient | BurnerLoans_AssetDebtCapExceeded(asset,A,R) | Entire nested and outer transaction rolls back | Stored-snapshot quote has no refresh callback; compare only when relevant prices, position and caps remain unchanged | Covered: [test_givenCacheBorrows_whenAssetRoomConsumed_thenOuterRechecksAndRollsBack][test_givenCacheBorrows_whenAssetRoomConsumed_thenOuterRechecksAndRollsBack] |
| BLDEBT-BORROW-C07 | Borrower | Nested borrow fits both caps and health; outer A fits remaining capacity | Success with debt D+nested+A; preserve existing maturity | Health/fee use current principal; exact two settlements, no stale overwrite | Stored-snapshot quote has no refresh callback; compare only when relevant prices, position and caps remain unchanged | Covered: [test_givenCacheBorrows_whenRoomRemains_thenBothSettlementsUseLiveDebt][test_givenCacheBorrows_whenRoomRemains_thenBothSettlementsUseLiveDebt] |

## Transfer callbacks and reentrancy

Use one otherwise-valid authorized nested borrow with sufficient caps, health and fee approval so it reaches Core's guard. Configure the existing callback token to propagate its nested failure. No ADMIN mutation, recovery or callback-routing cross-product is needed here.

| ID | Caller | Transfer callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-C09 | Borrower | Positive mandatory payer→Payout fee transfer attempts nested borrow | Nested `ReentrancyGuardReentrantCall()`; outer `ReentrantFeeToken.CallbackFailed()` | Entire borrow reverts: payer/recipient/Custody balances, fee liabilities, FLOAN principal/maturity and Inventory funding unchanged | Quote before arming callback; views do not predict token callback failures | Covered: [test_givenFeeTokenCallback_whenBorrowed_thenMandatoryReceiptFailureRollsBack][test_givenFeeTokenCallback_whenBorrowed_thenMandatoryReceiptFailureRollsBack] |
| BLDEBT-BORROW-C11 | Borrower | Inventory→recipient OHM delivery attempts nested borrow | Nested `ReentrancyGuardReentrantCall()`; outer `ReentrantFeeToken.CallbackFailed()` | Earlier fee receipt/credit and debt/funding writes all roll back; no principal or fee paid twice | Quote before arming callback; views do not transfer OHM | Covered: [test_givenOhmDeliveryCallback_whenBorrowed_thenFeeAndFundingRollBack][test_givenOhmDeliveryCallback_whenBorrowed_thenFeeAndFundingRollBack] |

## Payout dependency readiness

Other admission checks pass. Payout is selected on Core; direct IEnabler state can drift after Core/action enablement.

| ID | Caller | Payout active | Payout enabled | Execution | Preview | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-D07 | Borrower | true | false | PolicyDependency_NotActive(Payout) for fee-bearing borrow | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |
| BLDEBT-BORROW-D08 | Borrower | false | true | PolicyDependency_NotActive(Payout) for fee-bearing borrow | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |
| BLDEBT-BORROW-D09 | Borrower | false | false | PolicyDependency_NotActive(Payout) for fee-bearing borrow | Same error | No accounting/transfers | Covered: [test_givenPayoutUnavailable_whenFeeBearingOperation_reverts][test_givenPayoutUnavailable_whenFeeBearingOperation_reverts] |
| BLDEBT-BORROW-D10 | Borrower | true | true; reports another Kernel | PolicyDependency_KernelMismatch(Payout, expected, reported) for fee-bearing borrow | Same error | No accounting/transfers | Covered: [test_givenPayoutReportsAnotherKernel_whenFeeBearingOperation_reverts][test_givenPayoutReportsAnotherKernel_whenFeeBearingOperation_reverts] |

## Permissionless quote identities

| ID | Quote requester | Position owner | Execution caller / history | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-A12 | Fuzz every address; no authorization lookup allowed | Nonzero `onBehalfOf_`=B | Borrower or operator may execute later | Identical independently checked quote for B; no writes/logs; nonzero-fee quotes precede funding/approval of borrower or operator | Covered: [test_whenAnyViewerQuotesWithoutAuthorizationRead][test_whenAnyViewerQuotesWithoutAuthorizationRead], [test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody], [test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody][test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody] |
| BLDEBT-BORROW-A13 | Unrelated viewer X | B | Prospective operator O before grant, while valid, at deadline, after expiry and after revocation | Quote remains independent of O's grant while economic state is valid; execution follows grant validity | Covered: [test_givenNoGrant_whenUnrelatedViewerQuotes][test_givenNoGrant_whenUnrelatedViewerQuotes], [test_givenValidGrant_whenUnrelatedViewerQuotes][test_givenValidGrant_whenUnrelatedViewerQuotes], [test_givenGrantDeadline_whenUnrelatedViewerQuotes][test_givenGrantDeadline_whenUnrelatedViewerQuotes], [test_givenExpiredGrant_whenUnrelatedViewerQuotes][test_givenExpiredGrant_whenUnrelatedViewerQuotes], [test_givenRevokedGrant_whenUnrelatedViewerQuotes][test_givenRevokedGrant_whenUnrelatedViewerQuotes] |
| BLDEBT-BORROW-A14 | Unrelated viewer X | B | B has collateral; X has no position; separate OHM recipient | Quote B succeeds with explicit recipient; quoting X fails NoCollateral; no position changes | Covered: [test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted][test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted] |

## Referral fee sharing

R1-R6,R9-R16,R18,R20; AE1-AE21,AE34. The API appends an explicit referrer to borrow and its corresponding preview; BorrowPreview/ExtendPreview retain only the total fee F=P+R and existing position fields; neither exposes the protocol or referral component. Debt emits Borrowed/Extended with referrer, protocolFee P and referralFee R for the current operation; total F is their sum. Payout emits only delivery/defer events. Fresh debt charges only requested OHM with terms=1; top-ups charge only added principal and preserve existing maturity.

Defaults: borrower B has eligible collateral/debt, healthy pricing and usable services; O is B's current authorized operator; X differs from B,O with no grant. Actual execution caller pays F; borrowed OHM recipient is independently chosen for borrow. Referrer is never inferred from caller, borrower, principal recipient or an earlier operation. Unchanged includes Core/FLOAN/Inventory/DepositManager/cache, all token balances/allowances and every Payout category/index; rejected transactions commit no logs.

Debt is the Risk caller. borrow and its preview call Risk.fee(snapshot,market,principal,terms,referrer) once for the two named outputs protocolFee P and referralFee R. Risk owns gross-curve math, whitelist validation and percentage allocation. Debt computes checked total F=P+R for maxFee and its existing total-fee result field, then passes P,r,R separately to Core. For borrow, the Risk inputs use requested principal increment and terms=1.

Unit forwarding tests mock the two Risk outputs independently of loan economics (including splits that differ from any stored BPS setting) and mock only Core's settlement call. Assert exact snapshot, market, principal, terms, referrer and component arguments. The unit mock performs no fee transfer; real Core/Payout integration owns the cash-flow assertions. If Risk.fee reverts, Debt propagates its exact bytes and never calls Core settlement or Payout. Direct Core settlement does not call Risk. F,P,R are raw uint256 collateral units; referrer r is an address. No percentage or whitelist getter is read by Debt.

Retained baseline rows own grant expiry/revocation, mandatory fee-transfer failures, exact receipt and existing settlement guards. Risk.fee owns rounding/full-share examples; Payout.creditFee and transferPendingPayout own optional-delivery/callback accounting. New action cases below prove forwarding and loan-specific effects rather than repeating those suites.

Existing mappings above retain the baseline coverage after adapting the call signatures. Referral-specific mappings below identify the additional split, attribution, rejection and accounting assertions.

### Caller and referrer independence

All economic checks otherwise pass. Vary caller and attribution independently; existing baseline rows retain the deadline/expiry domains. Positive-referral success cases exclude the selected Payout address; its rejection and zero-allocation exception are covered below. Mock returned components P,R independently of loan economics; compute F=P+R for the total charge. Guarantee P=0 and R=0 on separate valid seeds. Referrer zero always pairs with R=0; a nonzero referrer can pair with R=0. Preview and execution return only total F and existing position fields; execution passes P,r,R and the actual payer unchanged to Core. BorrowPreview has four ABI fields and ExtendPreview has three, with no split fields.

| ID | Caller | Referrer | Operator grant | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-A15 | Borrower B or O; guarantee each | Allowed R, including R=B/O and unrelated frontend | B direct or valid B→O | Permissionless viewer quotes same total F without split fields | Success | Core instruction has payer=actual caller and the exact P,r,R returned by Risk; unit mock performs no transfers | Covered: [test_whenRiskReturnsComponents][test_whenRiskReturnsComponents], [test_whenZeroComponents][test_whenZeroComponents], [test_whenOneProtocolUnit][test_whenOneProtocolUnit], [test_whenOneReferralUnit][test_whenOneReferralUnit], [test_whenLiteralSplit][test_whenLiteralSplit], [test_whenMaximumProtocolComponent][test_whenMaximumProtocolComponent], [test_whenMaximumReferralComponent][test_whenMaximumReferralComponent], [test_whenReferrerIsBorrower][test_whenReferrerIsBorrower], [test_whenReferrerIsOperator][test_whenReferrerIsOperator], [test_whenReferrerVaries][test_whenReferrerVaries], [test_givenRealRisk_whenOperatorBorrows][test_givenRealRisk_whenOperatorBorrows] |
| BLDEBT-BORROW-A16 | Unrelated X≠B,O | Allowed R≠Payout; seed X=R | Only B→O valid; no B→X | X may quote B without authorization reads | IOperatorAuth.OperatorAuth_InvalidContext() | Unchanged; whitelist grants no execution authority | Covered: [test_givenOnlyOtherOperatorAuthorized_whenReferrerBorrows_reverts][test_givenOnlyOtherOperatorAuthorized_whenReferrerBorrows_reverts] |

### Risk results and combined fee limit

Own/action/dependency admission and earlier health checks pass. Risk.fee supplies both components directly. ReferrerNotAllowed is a Risk error propagated through the same call, not a local Debt or Core whitelist check. Risk's own fee matrix owns zero-share/zero-total eligibility rules; the real removal-between-preview-and-execution case below proves action wiring.

| ID | Caller | Referrer r | Risk.fee return | maxFee | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-I08 | B or O | Nonzero r | P≥0,R>0,F=P+R≤MAX256 | P≤maxFee<F; seed P,F-1 and fundable F maximum | BurnerLoans_FeeExceedsMax(F,maxFee) | Compare with combined charge F, not protocolFee alone; no settlement or Payout credit; Unchanged | Covered: [test_whenMaxFeeExcludesReferral_reverts][test_whenMaxFeeExcludesReferral_reverts], [test_whenFeeLimitEqualsProtocol_reverts][test_whenFeeLimitEqualsProtocol_reverts], [test_whenFeeLimitImmediatelyBelowTotal_reverts][test_whenFeeLimitImmediatelyBelowTotal_reverts], [test_whenMaximumTotalExceedsFeeLimit_reverts][test_whenMaximumTotalExceedsFeeLimit_reverts] |
| BLDEBT-BORROW-P19 | B or O | Zero | Return P=F,R=0; F fuzz0..fundable MAX256 | F or MAX256; seed equality | Returns total fee F without split fields | Core instruction carries P=F,r=0,R=0; retain existing zero-total skipping | Covered: [test_whenZeroReferrer][test_whenZeroReferrer] |
| BLDEBT-BORROW-P20 | B or O | Nonzero r accepted by Risk | Return P=R=0 | 0 | Total fee=0 without split fields | Risk.fee still called with r; Core instruction has both components zero; real settlement makes no fee transfer/Payout credit | Covered: [test_whenZeroComponents][test_whenZeroComponents], [test_givenZeroGrossFee_whenAllowedReferrerBorrowed][test_givenZeroGrossFee_whenAllowedReferrerBorrowed] |
| BLDEBT-BORROW-N12 | B or O | Nonzero r | Mock P fuzz1..MAX256 and R fuzz(MAX256-P+1)..MAX256; seed1/MAX256 and first overflow | MAX256 | Panic(0x11) from checked P+R | No Core settlement or Payout call; total must not wrap to bypass maxFee | Covered: [test_whenComponentSumOverflows_reverts][test_whenComponentSumOverflows_reverts], [test_whenMinimumProtocolOverflows_reverts][test_whenMinimumProtocolOverflows_reverts], [test_whenMaximumProtocolOverflows_reverts][test_whenMaximumProtocolOverflows_reverts] |

### Referral destination admission

All existing caller and lifecycle admission applies. Risk remains the calculator and whitelist owner.
Debt calls the selected Payout.validatePayoutRecipient(referrer) for positive referral allocations
in its shared quote path. Payout owns destination admission and uses that validator in settlement.
Debt does not duplicate destination, whitelist or percentage rules.

| ID | Caller | Referrer | Fee inputs | Preview | Execution and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-I10 | B or O; permissionless quote | Selected Payout; whitelisted for real integration | Mock P=0,R fuzz1..MAX256; seed1,MAX256; maxFee=MAX256. Real share=10000 with positive total | BurnerLoansPayout_InvalidRecipient(Payout) | Same error before Core settlement; Unchanged | Covered: [test_whenReferrerIsPayout_whenAllocationPositive_reverts][test_whenReferrerIsPayout_whenAllocationPositive_reverts], [test_whenOneUnitSelfReferral_reverts][test_whenOneUnitSelfReferral_reverts], [test_whenMaximumSelfReferral_reverts][test_whenMaximumSelfReferral_reverts], [test_givenWhitelistedPayout_whenPositiveReferral_reverts][test_givenWhitelistedPayout_whenPositiveReferral_reverts] |
| BLDEBT-BORROW-P24 | B or O; permissionless quote | Selected Payout; whitelisted for real integration | R=0,P fuzz0..MAX256; seed0,MAX256; maxFee=P. Real share=0 with positive total | Return total P | Forward unchanged P and zero R; real protocol payment succeeds; no self referral entitlement | Covered: [test_whenReferrerIsPayout_whenAllocationZero][test_whenReferrerIsPayout_whenAllocationZero], [test_whenSelfReferrerZeroFee][test_whenSelfReferrerZeroFee], [test_whenSelfReferrerMaximumProtocolFee][test_whenSelfReferrerMaximumProtocolFee], [test_givenWhitelistedPayout_whenReferralShareZero][test_givenWhitelistedPayout_whenReferralShareZero] |

### Successive operations and real integration

Use real Risk/Core/Payout for the rows in this section; whitelist/settings are actual state here. Core receives P,r,R separately and already has asset/borrower. It forwards creditFee(asset,P,r,R) to Payout without borrower metadata; Debt records the borrower and current fee allocation in its loan event. For token funding C=P+R, assert payer debit C, exact Payout receipt C, protocol allocation P and fixed-original referral allocation R. Neither Core nor Payout calls Risk for fees or whitelist validation.

Use real Risk/Core/Payout for accounting rows. Fuzz across the existing principal/terms domain with explicit type maxima retained in baseline cases; seed one raw fee unit and full fundable fee endpoints independently.

| ID | Caller | Prior attribution / configuration | Current attribution / change | Preview | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-P21 | B then O | No prior position-level referral | R1 on first call, R2 on next, then zero; seed nonzero distinct R1,R2 | Each quote uses only supplied address | All three succeed | No stored position referrer; rewards separately assigned; baseline debt/maturity math preserved | Covered: [test_whenSuccessiveBorrowsChooseDifferentReferrers][test_whenSuccessiveBorrowsChooseDifferentReferrers] |
| BLDEBT-BORROW-P22 | B or O | Quote allowed R at S1 | Execute after ADMIN/BLRCT changes S1→S2 | Fresh quote uses S2 | Current split at S2; gross unaffected | Returns F; Debt event records new P2,r,R2; settles P2,R2; prior pending R1 amount fixed | Covered: [test_givenPendingReferralFee_whenShareChangesAfterQuote][test_givenPendingReferralFee_whenShareChangesAfterQuote] |
| BLDEBT-BORROW-I09 | B or O | Successful quote while R allowed | Removal executes before transaction | Original quote was valid; fresh quote rejects | BurnerLoansRisk_ReferrerNotAllowed(R) | Unchanged; caller can submit a new operation with zero | Covered: [test_givenReferrerRemovedAfterQuote_whenBorrowed_reverts][test_givenReferrerRemovedAfterQuote_whenBorrowed_reverts] |
| BLDEBT-BORROW-P23 | Fixed borrower B | Real prices / canonical market fee | F=101,S=2500 or real 6/18-decimal market | Independent total F | Success | Payer debit F; incoming Payout receipt F; exact original referrer and protocol remainder; Debt loan event identifies B, referrer and the new protocol/referral allocations P,R | Covered: [test_givenRealRisk_whenOperatorBorrows][test_givenRealRisk_whenOperatorBorrows] |

### Live Risk eligibility and upstream independence

All lending services are otherwise ready; caller B or O is authorized. These use real Risk rather than a membership-aware Debt mock.

| ID | Caller | Referrer | Risk configuration / upstream | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-D12 | B or O | Approved nonzero r | BLRCT paused/inactive or Risk operator changed; Risk operational; share configured | Same independently checked total F | Success; Risk uses its stored settings without upstream lifecycle lookup; Core/Payout have no Risk fee/whitelist call | Covered: [test_givenRiskOperatorChanged_whenBorrowed][test_givenRiskOperatorChanged_whenBorrowed], [test_givenRiskQueueLifecycle_whenBorrowed][test_givenRiskQueueLifecycle_whenBorrowed], [test_givenRiskQueueOperational_whenBorrowed][test_givenRiskQueueOperational_whenBorrowed], [test_givenRiskQueuePaused_whenBorrowed][test_givenRiskQueuePaused_whenBorrowed], [test_givenRiskQueueInactive_whenBorrowed][test_givenRiskQueueInactive_whenBorrowed], [test_givenRiskQueueInactivePaused_whenBorrowed][test_givenRiskQueueInactivePaused_whenBorrowed] |

### Transfer failures and callbacks

Token delivery is execution-only. Preview does not require payer funds/approval and cannot predict an outgoing delivery failure. Keep legacy mandatory fee callback cases and authorize nested calls enough to reach the guard.

| ID | Caller | Transfer / callback | Preview | Execution | Required proof | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-T12 | B or O | Referral paid or deferred, then Inventory.draw raises configured FundingFailed() | Pre-funding economic quote valid | Exact configured FundingFailed() | All debt, principal delivery, payer allowance, referral recipient transfer/pending reward and cache writes roll back together | Covered: [test_givenReferralDeliveredOrDeferred_whenPrincipalFundingFails_reverts][test_givenReferralDeliveredOrDeferred_whenPrincipalFundingFails_reverts] |
| BLDEBT-BORROW-T09 | B or O | Outgoing referral transfer rejected; protocol route accepts | Quotes total F | Success | Actual payer -F; funded pending referral R; protocol P delivered; no change in gross fee or action success | Covered: [test_givenPendingReferralFee_whenShareChangesAfterQuote][test_givenPendingReferralFee_whenShareChangesAfterQuote] |

### Risk-call failure propagation

Earlier borrower/action/health admission passes. Configure the reached Risk.fee selector to revert with independent bytes E: fuzz arbitrary revert payloads and guarantee empty data, BurnerLoansRisk_ReferrerNotAllowed(r), a custom error with arguments, and Panic(0x11). No translation, swallowing, zero-fee fallback, Core settlement, or Payout credit is permitted. A prior refreshSnapshot write must roll back with the failed outer execution. Preview performs no refresh and bubbles the same configured fee error under equal admission state.

| ID | Caller | Risk call | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-BORROW-T13 | B or O | fee(snapshot,market,principal,terms,r) reverts with E | Bubble exact E | Bubble exact E | No Core settlement, token collection or Payout call; rollback earlier refresh and all state/logs | Covered: [test_whenRiskFeeReverts_reverts][test_whenRiskFeeReverts_reverts], [test_whenEmptyRiskError_reverts][test_whenEmptyRiskError_reverts], [test_whenTypedRiskError_reverts][test_whenTypedRiskError_reverts], [test_whenPanicRiskError_reverts][test_whenPanicRiskError_reverts], [test_givenStaleCache_whenRiskFeeFails_reverts][test_givenStaleCache_whenRiskFeeFails_reverts] |

- [x] Review the referral cases before writing tests.

## Authorization completion callbacks

| ID | Trigger | Expected result | Test |
| --- | --- | --- | --- |
| BLDEBT-BORROW-AUTH-C20 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts][test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts] |
| BLDEBT-BORROW-AUTH-C21 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts][test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts] |
| BLDEBT-BORROW-AUTH-C22 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenPrincipalDeliveryCallback_whenOriginalGrantCancelled_reverts][test_givenPrincipalDeliveryCallback_whenOriginalGrantCancelled_reverts] |
| BLDEBT-BORROW-AUTH-C23 | Actual token transfer callback | Cancel or accept identical permissions at a newer epoch; original captured authority fails completion and restores all accounting/token/epoch changes | [test_givenPrincipalDeliveryCallback_whenIdenticalGrantReaccepted_reverts][test_givenPrincipalDeliveryCallback_whenIdenticalGrantReaccepted_reverts] |

[test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead]: borrow.t.sol#L864
[test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead]: borrow.t.sol#L852
[test_givenActionRoleRevoked_whenBorrowed_reverts]: borrow.t.sol#L840
[test_givenAnotherBorrowerDebt_whenBorrowed]: borrowIntegration.t.sol#L20
[test_givenAnotherBorrowerDebt_whenSharedMarketCapExceeded_reverts]: borrowIntegration.t.sol#L71
[test_givenAnotherMarketDebt_whenBorrowed]: borrowIntegration.t.sol#L121
[test_givenAnotherMarketDebt_whenSharedGlobalCapExceeded_reverts]: borrowIntegration.t.sol#L96
[test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts]: borrow.t.sol#L999
[test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody]: borrow.t.sol#L109
[test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody]: borrow.t.sol#L117
[test_givenAssetCap_whenRequestExceedsRoom_reverts]: borrow.t.sol#L417
[test_givenAtDeadline_whenOperatorBorrowed_thenSuccessfulSettlement]: borrow.t.sol#L1285
[test_givenBeforeDeadline_whenOperatorBorrowed_thenSuccessfulSettlement]: borrow.t.sol#L1280
[test_givenBorrower_whenActionKernelGetterReverts]: borrow.t.sol#L889
[test_givenBorrower_whenActionReportedKernelMismatches]: borrow.t.sol#L879
[test_givenBothCapsInsufficient_whenBorrowed_reverts]: borrow.t.sol#L376
[test_givenCacheBorrows_whenAssetRoomConsumed_thenOuterRechecksAndRollsBack]: borrowPriceCallbacks.t.sol#L65
[test_givenCacheBorrows_whenGlobalRoomConsumed_thenOuterRechecksAndRollsBack]: borrowPriceCallbacks.t.sol#L18
[test_givenCacheBorrows_whenRoomRemains_thenBothSettlementsUseLiveDebt]: borrowPriceCallbacks.t.sol#L103
[test_givenCancelledGrant_whenOperatorActs_reverts]: borrow.t.sol#L972
[test_givenCoreUnavailable_whenCalled_thenDependencyIdentified]: borrow.t.sol#L1073
[test_givenDebtBearingPosition_whenBorrowIsPreviewed_thenActionResultMatches]: borrowIntegration.t.sol#L347
[test_givenDisabledDebtAction_whenCalled_thenPauseWins]: borrow.t.sol#L1055
[test_givenEightDecimalCollateralAndPrice_whenBorrowed_thenNativeFeeUnits]: borrowIntegration.t.sol#L243
[test_givenExistingDebt_whenToppedUp_thenExpiryPreserved]: borrow.t.sol#L484
[test_givenExpiredCacheAndChangedPrice_whenBorrowed]: borrowIntegration.t.sol#L140
[test_givenExpiredCacheAndChangedPrice_whenOldFeeLimitUsed_reverts]: borrowIntegration.t.sol#L166
[test_givenExpiredDebt_whenBorrowed_reverts]: borrow.t.sol#L468
[test_givenExpiredGrant_whenOperatorActs_reverts]: borrow.t.sol#L935
[test_givenExpiredGrant_whenUnrelatedViewerQuotes]: borrow.t.sol#L1506
[test_givenFeeCollectionCallback_whenIdenticalGrantReaccepted_reverts]: borrowAuthorizationCallbacks.t.sol#L21
[test_givenFeeCollectionCallback_whenOriginalGrantCancelled_reverts]: borrowAuthorizationCallbacks.t.sol#L16
[test_givenFeeDelivered_whenFundingFails_thenEverythingRollsBack]: borrow.t.sol#L533
[test_givenFeeTokenCallback_whenBorrowed_thenMandatoryReceiptFailureRollsBack]: borrowCallbacks.t.sol#L82
[test_givenFee_whenMaxFeeTooLow_reverts]: borrow.t.sol#L337
[test_givenFullyRepaidEpisode_whenBorrowed_thenNewTermStartsNow]: borrow.t.sol#L739
[test_givenGlobalCap_whenRequestExceedsRoom_reverts]: borrow.t.sol#L355
[test_givenGlobalUtilizationAtKink_whenMarketBelowKink_thenMarketRate]: borrowIntegration.t.sol#L234
[test_givenGrantDeadline_whenUnrelatedViewerQuotes]: borrow.t.sol#L1496
[test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified]: borrow.t.sol#L1033
[test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError]: borrow.t.sol#L1295
[test_givenInsolventOperatorCustody_whenBorrowed_reverts]: borrow.t.sol#L631
[test_givenInsufficientAllowance_whenEitherPayerBorrows_thenFullFeeDomainRollsBack]: borrow.t.sol#L1354
[test_givenInsufficientFeeAllowance_whenBorrowed_reverts]: borrow.t.sol#L562
[test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack]: borrow.t.sol#L1187
[test_givenInventoryUnavailable_whenBorrowed_reverts]: borrow.t.sol#L439
[test_givenLaterBlockTopUp_whenRepaidInThatBlock_reverts]: borrow.t.sol#L1416
[test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted]: borrow.t.sol#L927
[test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement]: borrow.t.sol#L1290
[test_givenMaximumFeeAndZeroBalance_whenOperatorBorrows_reverts]: borrow.t.sol#L1402
[test_givenMaximumFee_whenPayerUnfunded_reverts]: borrow.t.sol#L592
[test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt]: borrow.t.sol#L899
[test_givenMaximumTimestamp_whenGrantExpired_reverts]: borrow.t.sol#L967
[test_givenMaximumTopUp_whenBorrowed_thenNoPrincipalTruncation]: borrow.t.sol#L1411
[test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt]: borrow.t.sol#L228
[test_givenMintApprovalLimitsCapacity_whenBorrowed_reverts]: borrow.t.sol#L395
[test_givenNoCollateral_whenBorrowed_reverts]: borrow.t.sol#L726
[test_givenNoGrant_whenUnrelatedCallerActs_reverts]: borrow.t.sol#L987
[test_givenNoGrant_whenUnrelatedViewerQuotes]: borrow.t.sol#L1474
[test_givenOhmDeliveryCallback_whenBorrowed_thenFeeAndFundingRollBack]: borrowCallbacks.t.sol#L18
[test_givenOneRawOhmUnit_whenBorrowed_thenFeeRoundsUpToOneCollateralUnit]: borrowIntegration.t.sol#L258
[test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt]: borrow.t.sol#L223
[test_givenOnlyOtherOperatorAuthorized_whenReferrerBorrows_reverts]: borrowReferral.t.sol#L291
[test_givenOperatorAllowanceOneBelowFee_whenBorrowed_reverts]: borrow.t.sol#L1393
[test_givenOperator_whenActionKernelGetterReverts]: borrow.t.sol#L894
[test_givenOperator_whenActionReportedKernelMismatches]: borrow.t.sol#L884
[test_givenOriginationsDisabled_whenBorrowed_reverts]: borrow.t.sol#L1094
[test_givenOtherOperatorGrant_whenUnrelatedCallerBorrows_reverts]: borrow.t.sol#L459
[test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError]: borrow.t.sol#L1319
[test_givenPayoutReportsAnotherKernel_whenFeeBearingOperation_reverts]: borrow.t.sol#L1261
[test_givenPayoutUnavailable_whenFeeBearingOperation_reverts]: borrow.t.sol#L1246
[test_givenPendingReferralFee_whenShareChangesAfterQuote]: borrowReferralIntegration.t.sol#L194
[test_givenPolicyReactivated_whenBorrowExecuted_thenSucceeds]: borrow.t.sol#L1340
[test_givenPreBorrowUtilizationAboveKink_whenBorrowed_then575Bps]: borrowIntegration.t.sol#L226
[test_givenPreBorrowUtilizationAtKink_whenBorrowed_then125Bps]: borrowIntegration.t.sol#L218
[test_givenPrincipalDeliveryCallback_whenIdenticalGrantReaccepted_reverts]: borrowAuthorizationCallbacks.t.sol#L31
[test_givenPrincipalDeliveryCallback_whenOriginalGrantCancelled_reverts]: borrowAuthorizationCallbacks.t.sol#L26
[test_givenReEnabled_whenBorrowExecuted_thenSucceeds]: borrow.t.sol#L1347
[test_givenRealRisk_whenBorrowed_thenIndependentFeesAndHealth]: borrowIntegration.t.sol#L204
[test_givenRealRisk_whenOperatorBorrows]: borrowReferralIntegration.t.sol#L94
[test_givenRealStalePrice_whenBorrowQuotedOrExecuted_reverts]: borrowIntegration.t.sol#L321
[test_givenReferralDeliveredOrDeferred_whenPrincipalFundingFails_reverts]: borrowReferralIntegration.t.sol#L317
[test_givenReferrerRemovedAfterQuote_whenBorrowed_reverts]: borrowReferralIntegration.t.sol#L153
[test_givenRevokedGrant_whenUnrelatedViewerQuotes]: borrow.t.sol#L1521
[test_givenRiskFeeFailure_whenBorrowed_reverts]: borrow.t.sol#L615
[test_givenRiskOperatorChanged_whenBorrowed]: borrowReferralIntegration.t.sol#L398
[test_givenRiskQueueInactivePaused_whenBorrowed]: borrowReferralIntegration.t.sol#L548
[test_givenRiskQueueInactive_whenBorrowed]: borrowReferralIntegration.t.sol#L543
[test_givenRiskQueueLifecycle_whenBorrowed]: borrowReferralIntegration.t.sol#L468
[test_givenRiskQueueOperational_whenBorrowed]: borrowReferralIntegration.t.sol#L533
[test_givenRiskQueuePaused_whenBorrowed]: borrowReferralIntegration.t.sol#L538
[test_givenStaleCache_whenRiskFeeFails_reverts]: borrowReferralIntegration.t.sol#L360
[test_givenUnauthorizedCacheAction_whenCaught_thenOuterSucceeds]: borrowPriceCallbacks.t.sol#L152
[test_givenUnauthorizedCacheAction_whenPropagated_thenOuterRollsBack]: borrowPriceCallbacks.t.sol#L174
[test_givenUnhealthyCurrentPosition_whenBorrowed_reverts]: borrow.t.sol#L657
[test_givenUnhealthyFinalPosition_whenBorrowed_reverts]: borrow.t.sol#L691
[test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached]: borrow.t.sol#L908
[test_givenValidGrant_whenUnrelatedViewerQuotes]: borrow.t.sol#L1487
[test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays]: borrow.t.sol#L1144
[test_givenWhitelistedPayout_whenPositiveReferral_reverts]: borrowReferralIntegration.t.sol#L31
[test_givenWhitelistedPayout_whenReferralShareZero]: borrowReferralIntegration.t.sol#L55
[test_givenZeroFee_whenBorrowed_thenNoApprovalOrFeeHandoff]: borrow.t.sol#L236
[test_givenZeroFee_whenOperatorBorrows_thenNoApprovalOrFeeHandoff]: borrow.t.sol#L241
[test_givenZeroGrossFee_whenAllowedReferrerBorrowed]: borrowReferralIntegration.t.sol#L418
[test_whenAmountZero_reverts]: borrow.t.sol#L284
[test_whenAnyViewerQuotesWithoutAuthorizationRead]: borrow.t.sol#L1439
[test_whenAssetCapacityEndpointsRejected_thenExactError]: borrow.t.sol#L1120
[test_whenAuthorizationEndpoints_thenAdmissionIsInclusive]: borrow.t.sol#L1165
[test_whenBorrowed_thenPrincipalAndMaturityAreCanonical]: borrow.t.sol#L45
[test_whenBorrowerZero_thenExplicitError]: borrow.t.sol#L1020
[test_whenComponentSumOverflows_reverts]: borrowReferral.t.sol#L232
[test_whenEmptyRiskError_reverts]: borrowReferral.t.sol#L355
[test_whenExpiryEndpointsRejected_thenExactError]: borrow.t.sol#L1136
[test_whenFeeCollectionEndpoints_thenCompleteRollback]: borrow.t.sol#L1227
[test_whenFeeLimitEndpointsRejected_thenExactError]: borrow.t.sol#L1128
[test_whenFeeLimitEqualsProtocol_reverts]: borrowReferral.t.sol#L398
[test_whenFeeLimitImmediatelyBelowTotal_reverts]: borrowReferral.t.sol#L403
[test_whenFeeReceiptInexact_thenDebtRollsBack]: borrow.t.sol#L807
[test_whenFeeTransferReturnsFalse_thenDebtRollsBack]: borrow.t.sol#L780
[test_whenGlobalCapacityEndpointsRejected_thenExactError]: borrow.t.sol#L1109
[test_whenLiteralSplit]: borrowReferral.t.sol#L334
[test_whenMaxFeeExcludesReferral_reverts]: borrowReferral.t.sol#L204
[test_whenMaximumPrincipalBorrowed_thenNoTruncation]: borrow.t.sol#L104
[test_whenMaximumProtocolComponent]: borrowReferral.t.sol#L339
[test_whenMaximumProtocolOverflows_reverts]: borrowReferral.t.sol#L418
[test_whenMaximumReferralComponent]: borrowReferral.t.sol#L344
[test_whenMaximumSelfReferral_reverts]: borrowReferral.t.sol#L74
[test_whenMaximumTotalExceedsFeeLimit_reverts]: borrowReferral.t.sol#L408
[test_whenMinimumProtocolOverflows_reverts]: borrowReferral.t.sol#L413
[test_whenOneProtocolUnit]: borrowReferral.t.sol#L324
[test_whenOneRawOhmBorrowed_thenNoTruncation]: borrow.t.sol#L99
[test_whenOneReferralUnit]: borrowReferral.t.sol#L329
[test_whenOneUnitSelfReferral_reverts]: borrowReferral.t.sol#L69
[test_whenPanicRiskError_reverts]: borrowReferral.t.sol#L370
[test_whenRecipientIsAction_reverts]: borrow.t.sol#L306
[test_whenRecipientZero_reverts]: borrow.t.sol#L295
[test_whenReferrerIsBorrower]: borrowReferral.t.sol#L375
[test_whenReferrerIsOperator]: borrowReferral.t.sol#L381
[test_whenReferrerIsPayout_whenAllocationPositive_reverts]: borrowReferral.t.sol#L25
[test_whenReferrerIsPayout_whenAllocationZero]: borrowReferral.t.sol#L79
[test_whenReferrerVaries]: borrowReferral.t.sol#L389
[test_whenRiskFeeReverts_reverts]: borrowReferral.t.sol#L251
[test_whenRiskReturnsComponents]: borrowReferral.t.sol#L100
[test_whenSelfReferrerMaximumProtocolFee]: borrowReferral.t.sol#L93
[test_whenSelfReferrerZeroFee]: borrowReferral.t.sol#L88
[test_whenSuccessiveBorrowsChooseDifferentReferrers]: borrowReferralIntegration.t.sol#L265
[test_whenTypedRiskError_reverts]: borrowReferral.t.sol#L360
[test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted]: borrow.t.sol#L1537
[test_whenZeroComponents]: borrowReferral.t.sol#L319
[test_whenZeroReferrer]: borrowReferral.t.sol#L349
