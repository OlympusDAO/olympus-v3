# BurnerLoansDebt.repay coverage plan

Source: [repay](../../../policies/burnerloans/BurnerLoansDebt.sol#L171). Scenarios specify the required behavior; mappings identify existing test proof.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLDEBT-REPAY` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansDebt; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Permissionless payer, including unrelated third party without any grant. Defaults: nonzero borrower, existing position principal D>0, Inventory enabled, block later than lastBorrowBlock. Amount OHM uint128; MAX128 = type(uint128).max. D is current principal and A is the repayment amount, both in raw OHM units (9 decimals). Unchanged means authoritative position/market/global principal, collateral, maturity, borrower indexes, funding/provider claims, token balances and allowances, and dependency/cache state; a revert commits no logs.

`repay` and `previewRepay` return only outstanding OHM principal as `uint128`, including zero for full repayment. A caller that needs health reads canonical collateral/debt through `BurnerLoansLens.getPosition`, then calls `positionHealthFactor` separately. That read may fail during a pricing outage; repayment does not certify healthy remaining debt or extend maturity.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Both follow the same function-specific caller/input validation and quote outcome; no writes | Covered: [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting][test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting], [test_givenPolicyReactivated_whenRepayExecuted_thenSucceeds][test_givenPolicyReactivated_whenRepayExecuted_thenSucceeds], [test_givenReEnabled_whenRepayExecuted_thenSucceeds][test_givenReEnabled_whenRepayExecuted_thenSucceeds] |
| BLDEBT-REPAY-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-REPAY-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-REPAY-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified][test_givenCoreUnavailable_whenCalled_thenDependencyIdentified] |
| BLDEBT-REPAY-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-REPAY-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-REPAY-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-REPAY-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError][test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenDisabledDebtAction_whenCalled_thenPauseWins][test_givenDisabledDebtAction_whenCalled_thenPauseWins] |
| BLDEBT-REPAY-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |
| BLDEBT-REPAY-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError][test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError], [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified][test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified] |

## Caller and payer

EOAs and contracts are equally admitted without Kernel/status getters, settlement roles or operator grants. Public caller metadata does not establish authority. Funding and token rules remain separate where applicable.

Action and Core are active/enabled. Repayment is permissionless: fuzz all callers, including borrower, an operator and an unrelated address with no grant. The actual caller pays OHM; a valid grant to another operator neither authorizes a debit from that operator nor changes the payer.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-A01 | Fuzz all callers | Caller pays OHM for a nonzero borrower; no operator grant required; seed borrower, operator and unrelated caller | `Caller admitted by the public function` | Exact OHM collected only from msg.sender; borrower/operator wallets unchanged when distinct from payer; only borrower debt reduced | Same permissionless quote; no borrower/operator authorization check | Covered: [test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree][test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree], [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear][test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear], [test_whenPayerIsZero_thenQuoteSucceedsAndTokenRejectsAllowance][test_whenPayerIsZero_thenQuoteSucceedsAndTokenRejectsAllowance], [test_whenPayerIsInventory_thenQuoteSucceedsAndExactReceiptRejectsSelfTransfer][test_whenPayerIsInventory_thenQuoteSucceedsAndExactReceiptRejectsSelfTransfer], [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting][test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting], [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing][test_givenFullDebt_whenAnyPayerRepays_thenNoPricing] |

## Core settlement authorization

Operational action and Core; repayment is permissionless and the actual caller pays OHM. Core requires only the action's `BL_DEBT_POLICY_ROLE`, independently of any borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-A02 | Fuzz all callers | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test_givenActionRoleRevoked_whenRepaid_reverts][test_givenActionRoleRevoked_whenRepaid_reverts] |
| BLDEBT-REPAY-A03 | Fuzz all payers | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return remaining principal only | Collect OHM only from the actual payer; reduce borrower and Inventory principal once; no caller `kernel()` read | Same remaining-principal quote under unchanged debt; no caller metadata or pricing read, writes or logs | Covered: [test_givenActionReportedKernelMismatch_whenRepaid_thenGetterIsNotRead][test_givenActionReportedKernelMismatch_whenRepaid_thenGetterIsNotRead], [test_givenActionKernelGetterReverts_whenRepaid_thenGetterIsNotRead][test_givenActionKernelGetterReverts_whenRepaid_thenGetterIsNotRead] |

## Dependency lifecycle

Action and Core active/enabled; positive repayment for an existing debt-bearing position. Vary Inventory state independently, with all earlier checks passing. Repayment being permissionless does not bypass this dependency check.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-I03 | Fuzz all callers | true | false | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts][test_givenInventoryUnavailable_whenRepaid_reverts] |
| BLDEBT-REPAY-D08 | Fuzz all callers | false | true | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change, even with existing idle funds | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts][test_givenInventoryUnavailable_whenRepaid_reverts] |
| BLDEBT-REPAY-D09 | Fuzz all callers | false | false | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts][test_givenInventoryUnavailable_whenRepaid_reverts] |

## Invalid inputs

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-I01 | Fuzz actual payer | amount=0; borrower nonzero | `BurnerLoansCore_ZeroAmount()` | Unchanged; no committed logs | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAmountZero_reverts][test_whenAmountZero_reverts] |
| BLDEBT-REPAY-I02 | Fuzz actual payer | borrower=0; amount>0 | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerZero_reverts][test_whenBorrowerZero_reverts] |
| BLDEBT-REPAY-I04 | Fuzz actual payer | Position absent; price services may be unavailable | `BurnerLoans_NoCollateral()` | Unchanged; no committed logs | Same BurnerLoans_NoCollateral() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenPositionAbsent_reverts][test_whenPositionAbsent_reverts] |
| BLDEBT-REPAY-I05 | Fuzz actual payer | Existing position with principal=0; fuzz positive amount in 1..MAX128; seed 1,MAX128 | `BurnerLoans_RepayExceedsDebt(amount,0)` | Unchanged; no committed logs | Same BurnerLoans_RepayExceedsDebt(amount,0) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenZeroDebt_whenPositiveRepayment_reverts][test_givenZeroDebt_whenPositiveRepayment_reverts] |
| BLDEBT-REPAY-I06 | Fuzz actual payer | Existing debt D in 1..MAX128-1; fuzz amount D+1..MAX128; seed D+1,MAX128 | `BurnerLoans_RepayExceedsDebt(amount,D)` | Unchanged; no committed logs | Same BurnerLoans_RepayExceedsDebt(amount,D) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError][test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError], [test_whenRepaymentExceedsDebt_reverts][test_whenRepaymentExceedsDebt_reverts], [test_givenOneUnitDebt_whenRepaymentExceedsByOne_reverts][test_givenOneUnitDebt_whenRepaymentExceedsByOne_reverts], [test_givenNearMaximumDebt_whenMaximumRepaid_reverts][test_givenNearMaximumDebt_whenMaximumRepaid_reverts] |
| BLDEBT-REPAY-I07 | Fuzz actual payer | nowBlock<=lastBorrowBlock; otherwise valid debt/input | `BurnerLoans_SameBlockRepay(lastBorrowBlock)` | Unchanged; no committed logs | Same BurnerLoans_SameBlockRepay(lastBorrowBlock), including while pricing services fail; neither path attempts a price read | Covered: [test_givenLatestBorrowBlock_whenRepaid_reverts][test_givenLatestBorrowBlock_whenRepaid_reverts] |

## Numeric boundaries and servicing

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-N01 | Fuzz actual payer | Partial repayment; fuzz D in 2..MAX128 and A in 1..D-1; seed A=1,D-1 and D=MAX128 with A=MAX128-1 | `D-amount` only | Exact OHM payer→Inventory; FLOAN and Inventory principal -amount; maturity/collateral unchanged; Repaid | Assert remaining principal independently as D-A, then compare the scalar execution return under unchanged debt; no preview writes or pricing reads | Covered: [test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree][test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree], [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting][test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting], [test_whenOneRawUnitRepaid_thenExactRemainingDebt][test_whenOneRawUnitRepaid_thenExactRemainingDebt], [test_whenAllButOneRawUnitRepaid_thenOneRemains][test_whenAllButOneRawUnitRepaid_thenOneRemains], [test_whenOneUnitPartialRepayment_thenNoNarrowing][test_whenOneUnitPartialRepayment_thenNoNarrowing], [test_whenMaximumPartialRepayment_thenNoNarrowing][test_whenMaximumPartialRepayment_thenNoNarrowing] |
| BLDEBT-REPAY-N02 | Fuzz actual payer | Full repayment amount=D; seed D=1 and MAX128 | `0` only | No pricing calls; debt episode/index cleared, collateral retained | Quote zero remaining principal with Risk configured to reject all calls; execution returns the same scalar without pricing | Covered: [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear][test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear], [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing][test_givenFullDebt_whenAnyPayerRepays_thenNoPricing], [test_whenOneUnitFullRepayment_thenNoNarrowing][test_whenOneUnitFullRepayment_thenNoNarrowing], [test_whenMaximumFullRepayment_thenNoNarrowing][test_whenMaximumFullRepayment_thenNoNarrowing] |
| BLDEBT-REPAY-N03 | Fuzz actual payer | Expired position; full repayment | `0` only | No maturity admission gate | Assert remaining principal independently as D-A, then compare the scalar execution return under unchanged debt; no preview writes or pricing reads | Covered: [test_givenExpiredDebt_whenFullyRepaid_thenAllowed][test_givenExpiredDebt_whenFullyRepaid_thenAllowed] |
| BLDEBT-REPAY-N04 | Fuzz actual payer | Unhealthy position; partial repayment; independent Lens reads before/after use valid prices | Return D-A only; repayment may leave health below 1e18 | Exact OHM collection and debt reduction; no minimum-health gate or price read by Debt | Quote D-A only; separately queried Lens health may remain below WAD and is not a repayment return | Covered: [payer fuzz and separate health][test_givenUnhealthyDebt_whenPartiallyRepaid_thenHelpfulRepaymentAllowed], [independent real health][test_givenRealUnhealthyPosition_whenPartiallyRepaid] |
| BLDEBT-REPAY-N05 | Fuzz actual payer | Originations disabled | `Success` | Servicing remains open | Assert remaining principal independently as D-A, then compare the scalar execution return under unchanged debt; no preview writes or pricing reads | Covered: [test_givenOriginationsDisabled_whenRepaid_thenAllowed][test_givenOriginationsDisabled_whenRepaid_thenAllowed] |
| BLDEBT-REPAY-N06 | Fuzz actual payer | Collateral payout insolvent; full repayment | `0` only | No DM solvency gate | Assert remaining principal independently as D-A, then compare the scalar execution return under unchanged debt; no preview writes or pricing reads | Covered: [test_givenInsolventCollateral_whenFullyRepaid_thenAllowed][test_givenInsolventCollateral_whenFullyRepaid_thenAllowed] |
| BLDEBT-REPAY-N07 | Fuzz actual payer | Full repayment; Risk unavailable | `0` only | No Risk call | Assert remaining principal independently as D-A, then compare the scalar execution return under unchanged debt; no preview writes or pricing reads | Covered: [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear][test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear], [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing][test_givenFullDebt_whenAnyPayerRepays_thenNoPricing], [test_whenOneUnitFullRepayment_thenNoNarrowing][test_whenOneUnitFullRepayment_thenNoNarrowing], [test_whenMaximumFullRepayment_thenNoNarrowing][test_whenMaximumFullRepayment_thenNoNarrowing] |

## Transfer and dependency failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-D04 | Fuzz actual payer | Partial repayment; Risk snapshot/refresh/health calls are configured to revert | Success; return D-A only | Exact OHM collection; FLOAN/Inventory principal reduced once; no Risk calls or cache writes | Quote D-A without calling Risk; no preview writes | Covered: [unit no-call proof][test_givenPartialDebt_whenPricingUnavailable], [stale-price execution][test_givenStalePrices_whenPartialRepaymentExecuted], [stale-price preview][test_givenStalePrices_whenPartialRepaymentQuoted] |
| BLDEBT-REPAY-D05 | Fuzz actual payer | OHM recipient delta differs from amount | `SafeERC20Exact_InexactTransferFrom(OHM,Inventory,amount,received)` | Unchanged; no committed logs | Quote only remaining principal without payer funding/approval or pricing reads; only execution proves delivery, exact receipt and applicable rollback | Covered: [test_whenIncomingOhmInexact_thenDebtAndAllowanceRollBack][test_whenIncomingOhmInexact_thenDebtAndAllowanceRollBack] |
| BLDEBT-REPAY-D06 | Fuzz actual payer | MINTR repayment burn fails | `Repayment succeeds` | OhmBurnFailed with exact failure data; burn amount remains surplus | Quote only remaining principal without payer funding/approval or pricing reads; only execution proves delivery, exact receipt and applicable rollback | Covered: [test_givenMintrBurnFailure_whenRepaid_thenDebtReducedAndOhmRetained][test_givenMintrBurnFailure_whenRepaid_thenDebtReducedAndOhmRetained] |
| BLDEBT-REPAY-D07 | Fuzz actual payer | MINTR approval restoration fails | `Repayment succeeds` | ApprovalRestorationFailed; safe funding-approval deficit remains | Quote only remaining principal without payer funding/approval or pricing reads; only execution proves delivery, exact receipt and applicable rollback | Covered: [test_givenMintrApprovalFailure_whenRepaid_thenSafeApprovalDeficitRemains][test_givenMintrApprovalFailure_whenRepaid_thenSafeApprovalDeficitRemains] |

## Pricing independence after dependency drift

Action, Core and Inventory are active/enabled with the required settlement role. Drift Risk after successful activation; vary its Kernel activity and local enablement independently. Use partial repayment with D=100e9 and A=50e9. Payer funding and allowance are sufficient. No pricing service or health getter may be called in either preview or execution, including Core's `risk()` getter. These states do not relax action/Core/Inventory admission.

| ID | Caller | Risk active | Risk enabled | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-D12 | Unrelated payer | true | true | Success; return 50e9 only, even when snapshot, refresh and health entry points revert | Exact payer debit and one 50e9 principal reduction; no pricing/cache effects | Quote 50e9; no Risk pointer/status/pricing reads or writes | Covered: [lifecycle fuzz][test_givenRiskLifecycleDrift_whenPartiallyRepaid], [exact state][test_givenRiskActiveEnabled_whenPartiallyRepaid] |
| BLDEBT-REPAY-D13 | Unrelated payer | true | false | Success; return 50e9 only | Same exact settlement; no Risk lifecycle read | Quote 50e9; no writes | Covered: [lifecycle fuzz][test_givenRiskLifecycleDrift_whenPartiallyRepaid], [exact state][test_givenRiskActiveDisabled_whenPartiallyRepaid] |
| BLDEBT-REPAY-D14 | Unrelated payer | false | true | Success; return 50e9 only | Same exact settlement; no Risk lifecycle read | Quote 50e9; no writes | Covered: [lifecycle fuzz][test_givenRiskLifecycleDrift_whenPartiallyRepaid], [exact state][test_givenRiskInactiveEnabled_whenPartiallyRepaid] |
| BLDEBT-REPAY-D15 | Unrelated payer | false | false | Success; return 50e9 only | Same exact settlement; no Risk lifecycle read | Quote 50e9; no writes | Covered: [lifecycle fuzz][test_givenRiskLifecycleDrift_whenPartiallyRepaid], [exact state][test_givenRiskInactiveDisabled_whenPartiallyRepaid] |

## Shared assertions

Action unit tests configure Risk and pricing methods to reject unexpected calls for both partial and full repayment. Assert zero pricing calls, actual Core/FLOAN/Inventory state, exact scalar returns and one settlement. Do not call the preview or Risk arithmetic to generate expected principal; derive D-A independently. Existing Risk and Lens suites retain ownership of health arithmetic.

Compare preview and independently calculated remaining principal for valid calls, including one-unit repayment, all-but-one repayment, D=MAX128 and full repayment. Neither preview nor execution calculates health or refreshes prices. Assert Repaid(payer,asset,borrower,A,remainingPrincipal), canonical position/market/global debt deltas, funding settlement and retained collateral/maturity for partial repayment; full repayment clears the debt episode/index. Preview does not transfer tokens, write state, or require payer funds/allowance. Assert borrower/operator wallets are unchanged when distinct from the actual payer. Preserve exact invalid-input, same-block and settlement errors even with pricing services unavailable. Preserve the mandatory OHM-transfer callback that reaches Core’s guard and propagates failure, with complete token/accounting rollback.

## Real Risk integration

Use repayIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Use a fixed unrelated payer because permissionless admission is covered in unit scenarios. Establish real debt with valid prices before introducing each outage; assert settlement directly rather than using the preview as the only oracle. For a separate health check, use Lens after reading canonical position amounts. Neither that read nor its failure is part of repayment settlement.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-P01 | Unrelated payer | Real pricing available; debt 100e9 OHM, collateral 2000e6; repay 50e9 from an unrelated payer | Success; return 50e9 principal only | Actual payer debit 50e9; canonical debt 50e9 and retained collateral 2000e6; separate Lens health is 32e18 (collateral USD 2000 / required backing USD 62.5); do not return health from repayment | Quote 50e9 independently, with no writes; a separate Lens read under valid prices reports health | Covered: [test_givenRealRisk_whenUnrelatedPayerPartiallyRepays_thenIndependentHealth][test_givenRealRisk_whenUnrelatedPayerPartiallyRepays_thenIndependentHealth] |
| BLDEBT-REPAY-P02 | Unrelated payer | Real PRICE timestamps exceed the freshness limit; all repayment admission and token checks pass | Partial repayment succeeds; return D-A only | Exact payer debit, FLOAN/Inventory debt reduction and unchanged collateral/cache; a separate Lens health read reverts with BurnerLoans_InvalidPrice without undoing the successful repayment | Quote D-A despite stale prices; preview is read-only and agrees with successful settlement | Covered: [execution and separate health failure][test_givenStalePrices_whenPartialRepaymentExecuted], [read-only preview][test_givenStalePrices_whenPartialRepaymentQuoted] |

## Additional isolation coverage

| ID | Caller | Pre-state / input | Expected outcome | Required accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-P03 | Unrelated payer | Two borrowers owe 100 OHM each in one market; fully repay only the first | First debt and episode cleared; second position unchanged | Market/global principal 100 OHM; active borrower list contains only the second; both collateral claims retained; exact payer debit; preview agrees | Covered: [test_givenTwoBorrowers_whenOneFullyRepaid][test_givenTwoBorrowers_whenOneFullyRepaid] |
| BLDEBT-REPAY-P04 | Unrelated payer | Same borrower owes 100 OHM in each of two markets; repay 50 OHM in one | Return target debt 50e9 only; other position unchanged | Market principals 50e9 and 100e9; Inventory principal 150e9; custody and both collateral claims retained; preview agrees; separate Lens health for the target is 32e18 | Covered: [test_givenTwoMarkets_whenOnePartiallyRepaid][test_givenTwoMarkets_whenOnePartiallyRepaid] |

## Adversarial cache callbacks are unreachable from repayment

Retain the existing test-only BurnerLoansCallbackCache setups and their borrower grants/funding. Arm each callback only after opening debt. Repayment must not invoke Risk.refreshSnapshot, Risk.snapshot, Risk.health or any cache entry point, so the armed nested operation cannot run. Preview must leave callback/cache state unchanged. For each row assert exact outer settlement once, unchanged cache callback state and unchanged nested-payer balances/allowances. The linked tests assert no pricing calls and successful outer settlement for each retained callback setup.

| ID | Caller | Armed cache callback | Execution / return | Accounting / callback proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C01 | Borrower | Authorized same-borrower borrow; previously changed lastBorrowBlock during refresh | Success; return D-A only | No nested borrow or latest-borrow-block mutation; exact outer repayment; cache not called | Quote D-A without callback | Covered: [test][test_givenAuthorizedBorrowCacheCallback_whenPartiallyRepaid] |
| BLDEBT-REPAY-C03 | Borrower | Unauthorized nested borrow; cache configured to catch failure | Success; return D-A only | Nested action is never attempted; no caught rejection data; one outer settlement | Quote D-A without callback | Covered: [test][test_givenCatchingUnauthorizedCacheCallback_whenPartiallyRepaid] |
| BLDEBT-REPAY-C04 | Borrower | Unauthorized nested borrow; cache configured to propagate failure | Success; return D-A only | No propagated cache error because cache is not called; one outer settlement | Quote D-A without callback | Covered: [test][test_givenPropagatingUnauthorizedCacheCallback_whenPartiallyRepaid] |
| BLDEBT-REPAY-C05 | Borrower | Funded cache would fully repay the same position | Success; return D-A only | Nested full repayment is never attempted; nested payer funds/allowance retained; only outer principal reduced | Quote D-A without callback | Covered: [test][test_givenFullRepaymentCacheCallback_whenPartiallyRepaid] |
| BLDEBT-REPAY-C06 | Borrower | Funded cache would partially repay and make outer amount exceed nested remaining debt | Success; return D-A only | Nested partial repayment is never attempted; no nested debt/allowance/balance changes; only outer principal reduced | Quote D-A without callback | Covered: [test][test_givenPartialRepaymentCacheCallback_whenPartiallyRepaid] |

Retired BLDEBT-REPAY-C02 combined caught and propagated callback outcomes; C03 and C04 retain those separate setups.

## Transfer callbacks and reentrancy

Use an outer partial repayment and fund a nested repayment of the remaining debt so the callback passes input checks and reaches Core's guard. Repayment requires no operator grant. Configure the existing callback token to propagate the nested rejection.

| ID | Caller | Transfer callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C08 | Fuzz all callers | Mandatory payer→Inventory OHM transferFrom attempts nested repayment | Nested `ReentrancyGuardReentrantCall()`; outer `ReentrantFeeToken.CallbackFailed()` | Exact pre-call OHM balances, FLOAN/Inventory principal, provider claims and payer allowance restored; no committed logs | Quote before arming callback; view performs no OHM transfer and cannot predict token failure | Covered: [test_givenOhmCallback_whenRepaid_thenMandatoryReceiptFailureRollsBack][test_givenOhmCallback_whenRepaid_thenMandatoryReceiptFailureRollsBack] |

## Backing and cache availability regressions

Debt, Core and Inventory are active/enabled with a sufficient funded unrelated payer. Introduce each fault after opening real debt. Repayment and preview must not access the faulting service. Settlement succeeds once; independent health reads remain price-dependent.

| ID | Caller | Scenario | Expected execution and preview | Required effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-D10 | Unrelated payer | Debt=100e9, repay=50e9, backing oracle disabled | Return 50e9 principal only | Exact 50e9 payer debit and debt reduction; collateral retained; no backing reads | Covered: [execution][test_givenPausedBacking_whenPartialRepaymentExecuted], [preview][test_givenPausedBacking_whenPartialRepaymentQuoted] |
| BLDEBT-REPAY-D11 | Unrelated payer | Debt=100e9, repay=100e9, backing oracle disabled | Return zero principal only | Exact full repayment; episode/index cleared; collateral retained; no health sentinel or backing reads | Covered: [full repayment][test_givenBackingPaused_whenFullyRepaid_thenDebtCloses] |
| BLDEBT-REPAY-D16 | Unrelated payer | Operational cache configured to revert on pricing/cache reads; partial repayment | Return D-A principal only | Exact OHM collection and debt reduction; no cache call or cache writes | Covered: [test][test_givenOperationalCacheFailure_whenPartiallyRepaid] |
| BLDEBT-REPAY-D17 | Unrelated payer | Backing oracle operational but backing() reverts; partial repayment | Return D-A principal only | Exact OHM collection and debt reduction; no backing call | Covered: [test][test_givenBackingReadFailure_whenPartiallyRepaid] |

## Scalar return contract

Use raw return data to prove both functions encode exactly one ABI word (32 bytes), decoded as uint128 remaining principal. This detects a leftover second health return, including on full repayment. Function input selectors are unchanged by removing return values; existing integrations expecting two words must update their ABI and decoding.

| ID | Caller | Input / pre-state | Execution / return | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-P05 | Unrelated payer | D=100e9, A=50e9; valid funding | Exactly 32 return bytes, decoded principal=50e9; normal exact settlement | Exactly 32 return bytes, decoded remainingPrincipal=50e9; no writes | Covered: [test][test_givenPartialRepayment_whenReturnDataInspected] |
| BLDEBT-REPAY-P06 | Unrelated payer | D=100e9, A=100e9; pricing unavailable | Exactly 32 return bytes, decoded principal=0; no additional health sentinel | Exactly 32 return bytes, decoded remainingPrincipal=0; no writes | Covered: [test][test_givenFullRepayment_whenReturnDataInspected] |

[test_givenActionKernelGetterReverts_whenRepaid_thenGetterIsNotRead]: repay.t.sol#L443
[test_givenActionReportedKernelMismatch_whenRepaid_thenGetterIsNotRead]: repay.t.sol#L430
[test_givenActionRoleRevoked_whenRepaid_reverts]: repay.t.sol#L419
[test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError]: repay.t.sol#L661
[test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear]: repay.t.sol#L568
[test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree]: repay.t.sol#L522
[test_givenAuthorizedBorrowCacheCallback_whenPartiallyRepaid]: repayPriceCallbacks.t.sol#L16
[test_givenFullRepaymentCacheCallback_whenPartiallyRepaid]: repayPriceCallbacks.t.sol#L34
[test_givenPartialRepaymentCacheCallback_whenPartiallyRepaid]: repayPriceCallbacks.t.sol#L45
[test_givenCatchingUnauthorizedCacheCallback_whenPartiallyRepaid]: repayPriceCallbacks.t.sol#L56
[test_givenCoreUnavailable_whenCalled_thenDependencyIdentified]: repay.t.sol#L490
[test_givenDisabledDebtAction_whenCalled_thenPauseWins]: repay.t.sol#L473
[test_givenExpiredDebt_whenFullyRepaid_thenAllowed]: repay.t.sol#L121
[test_givenFullDebt_whenAnyPayerRepays_thenNoPricing]: repay.t.sol#L99
[test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified]: repay.t.sol#L452
[test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError]: repay.t.sol#L721
[test_givenInsolventCollateral_whenFullyRepaid_thenAllowed]: repay.t.sol#L165
[test_givenInventoryUnavailable_whenRepaid_reverts]: repay.t.sol#L252
[test_givenLatestBorrowBlock_whenRepaid_reverts]: repay.t.sol#L237
[test_givenMintrApprovalFailure_whenRepaid_thenSafeApprovalDeficitRemains]: repay.t.sol#L368
[test_givenMintrBurnFailure_whenRepaid_thenDebtReducedAndOhmRetained]: repay.t.sol#L325
[test_givenNearMaximumDebt_whenMaximumRepaid_reverts]: repay.t.sol#L687
[test_givenOhmCallback_whenRepaid_thenMandatoryReceiptFailureRollsBack]: repayCallbacks.t.sol#L15
[test_givenOneUnitDebt_whenRepaymentExceedsByOne_reverts]: repay.t.sol#L682
[test_givenOriginationsDisabled_whenRepaid_thenAllowed]: repay.t.sol#L159
[test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting]: repay.t.sol#L42
[test_givenPartialDebt_whenPricingUnavailable]: repay.t.sol#L267
[test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError]: repay.t.sol#L745
[test_givenPolicyReactivated_whenRepayExecuted_thenSucceeds]: repay.t.sol#L766
[test_givenPropagatingUnauthorizedCacheCallback_whenPartiallyRepaid]: repayPriceCallbacks.t.sol#L63
[test_givenReEnabled_whenRepayExecuted_thenSucceeds]: repay.t.sol#L773
[test_givenRealRisk_whenUnrelatedPayerPartiallyRepays_thenIndependentHealth]: repayIntegration.t.sol#L107
[test_givenStalePrices_whenPartialRepaymentExecuted]: repayIntegration.t.sol#L154
[test_givenTwoBorrowers_whenOneFullyRepaid]: repayIntegration.t.sol#L21
[test_givenTwoMarkets_whenOnePartiallyRepaid]: repayIntegration.t.sol#L67
[test_givenUnhealthyDebt_whenPartiallyRepaid_thenHelpfulRepaymentAllowed]: repay.t.sol#L127
[test_givenZeroDebt_whenPositiveRepayment_reverts]: repay.t.sol#L203
[test_whenAllButOneRawUnitRepaid_thenOneRemains]: repay.t.sol#L91
[test_whenAmountZero_reverts]: repay.t.sol#L171
[test_whenBorrowerZero_reverts]: repay.t.sol#L181
[test_whenIncomingOhmInexact_thenDebtAndAllowanceRollBack]: repay.t.sol#L284
[test_whenMaximumFullRepayment_thenNoNarrowing]: repay.t.sol#L612
[test_whenMaximumPartialRepayment_thenNoNarrowing]: repay.t.sol#L629
[test_whenOneRawUnitRepaid_thenExactRemainingDebt]: repay.t.sol#L86
[test_whenOneUnitFullRepayment_thenNoNarrowing]: repay.t.sol#L607
[test_whenOneUnitPartialRepayment_thenNoNarrowing]: repay.t.sol#L620
[test_whenPayerIsInventory_thenQuoteSucceedsAndExactReceiptRejectsSelfTransfer]: repay.t.sol#L696
[test_whenPayerIsZero_thenQuoteSucceedsAndTokenRejectsAllowance]: repay.t.sol#L638
[test_whenPositionAbsent_reverts]: repay.t.sol#L191
[test_whenRepaymentExceedsDebt_reverts]: repay.t.sol#L222

[test_givenPausedBacking_whenPartialRepaymentExecuted]: ./repayIntegration.t.sol#L198

[test_givenBackingPaused_whenFullyRepaid_thenDebtCloses]: ./repayIntegration.t.sol#L140

[test_givenStalePrices_whenPartialRepaymentQuoted]: repayIntegration.t.sol#L182

[test_givenPausedBacking_whenPartialRepaymentQuoted]: repayIntegration.t.sol#L212

[test_givenRealUnhealthyPosition_whenPartiallyRepaid]: repayIntegration.t.sol#L275

[test_givenRiskLifecycleDrift_whenPartiallyRepaid]: repay.t.sol#L780

[test_givenRiskActiveEnabled_whenPartiallyRepaid]: repay.t.sol#L804

[test_givenRiskActiveDisabled_whenPartiallyRepaid]: repay.t.sol#L809

[test_givenRiskInactiveEnabled_whenPartiallyRepaid]: repay.t.sol#L814

[test_givenRiskInactiveDisabled_whenPartiallyRepaid]: repay.t.sol#L819

[test_givenOperationalCacheFailure_whenPartiallyRepaid]: repayIntegration.t.sol#L305

[test_givenBackingReadFailure_whenPartiallyRepaid]: repayIntegration.t.sol#L338

[test_givenPartialRepayment_whenReturnDataInspected]: repayIntegration.t.sol#L228

[test_givenFullRepayment_whenReturnDataInspected]: repayIntegration.t.sol#L251
