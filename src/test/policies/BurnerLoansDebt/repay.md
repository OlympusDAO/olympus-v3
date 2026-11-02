# BurnerLoansDebt.repay coverage plan

Source: [repay](../../../policies/burnerloans/BurnerLoansDebt.sol#L143). Scenarios specify the required behavior; mappings identify existing test proof.

Coverage records implemented domains and assertions independently of execution results. `Partial` identifies missing proof, not a production failure. New required behavior remains `Unmapped` until corresponding tests assert it.

## Domains and notation

Scenario scope: `BLDEBT-REPAY` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansDebt; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)` before body/input/idempotent work. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)`. Local activity is checked before local enablement and Core availability.

Permissionless payer, including unrelated third party without any grant. Defaults: nonzero borrower, existing position principal D>0, Inventory enabled, block later than lastBorrowBlock. Amount OHM uint128.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Use positive otherwise-valid operation inputs. Repeat failing gates with an invalid operation input to establish that admission wins. Action/Core roles and bindings otherwise remain valid.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-L01 | Fuzz all callers | true | true | true | true | Execute function-specific input/authorization cases | No state on admission rejection | Both follow the same function-specific caller/input validation and quote outcome; no writes | Covered: [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting](repay.t.sol#L42), [test_givenPolicyReactivated_whenRepayExecuted_thenSucceeds](repay.t.sol#L746), [test_givenReEnabled_whenRepayExecuted_thenSucceeds](repay.t.sol#L753) |
| BLDEBT-REPAY-D01 | Fuzz all callers | true | true | true | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](repay.t.sol#L458) |
| BLDEBT-REPAY-D02 | Fuzz all callers | true | true | false | true | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](repay.t.sol#L458) |
| BLDEBT-REPAY-D03 | Fuzz all callers | true | true | false | false | PolicyDependency_NotActive(Core) | No state on admission rejection | Same PolicyDependency_NotActive(Core); reject before presenting an executable quote | Covered: [test_givenCoreUnavailable_whenCalled_thenDependencyIdentified](repay.t.sol#L458) |
| BLDEBT-REPAY-L02 | Fuzz all callers | true | false | true | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L725), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](repay.t.sol#L441) |
| BLDEBT-REPAY-L03 | Fuzz all callers | true | false | true | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L725), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](repay.t.sol#L441) |
| BLDEBT-REPAY-L04 | Fuzz all callers | true | false | false | true | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L725), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](repay.t.sol#L441) |
| BLDEBT-REPAY-L05 | Fuzz all callers | true | false | false | false | NotEnabled() | No state on admission rejection | Same NotEnabled(); reject before presenting an executable quote | Covered: [test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L725), [test_givenDisabledDebtAction_whenCalled_thenPauseWins](repay.t.sol#L441) |
| BLDEBT-REPAY-L06 | Fuzz all callers | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L07 | Fuzz all callers | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L08 | Fuzz all callers | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L09 | Fuzz all callers | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L10 | Fuzz all callers | false | false | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L11 | Fuzz all callers | false | false | true | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L12 | Fuzz all callers | false | false | false | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |
| BLDEBT-REPAY-L13 | Fuzz all callers | false | false | false | false | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | No state on admission rejection | Same BurnerLoans_PolicyNotActive(BurnerLoansDebt); reject before presenting an executable quote | Covered: [test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError](repay.t.sol#L701), [test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified](repay.t.sol#L420) |

## Caller and payer

EOAs and contracts are equally admitted without Kernel/status getters, settlement roles or operator grants. Public caller metadata does not establish authority. Funding and token rules remain separate where applicable.

Action and Core are active/enabled. Repayment is permissionless: fuzz all callers, including borrower, an operator and an unrelated address with no grant. The actual caller pays OHM; a valid grant to another operator neither authorizes a debit from that operator nor changes the payer.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-A01 | Fuzz all callers | Caller pays OHM for a nonzero borrower; no operator grant required; seed borrower, operator and unrelated caller | `Caller admitted by the public function` | Exact OHM collected only from msg.sender; borrower/operator wallets unchanged when distinct from payer; only borrower debt reduced | Same permissionless quote; no borrower/operator authorization check | Covered: [test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree](repay.t.sol#L490), [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear](repay.t.sol#L541), [test_whenPayerIsZero_thenQuoteSucceedsAndTokenRejectsAllowance](repay.t.sol#L618), [test_whenPayerIsInventory_thenQuoteSucceedsAndExactReceiptRejectsSelfTransfer](repay.t.sol#L676), [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting](repay.t.sol#L42), [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing](repay.t.sol#L104) |

## Core settlement authorization

Operational action and Core; repayment is permissionless and the actual caller pays OHM. Core requires only the action's `BL_DEBT_POLICY_ROLE`, independently of any borrower grant.

The action retains its own active/enabled gates; Core retains its own lifecycle and settlement guard. Settlement caller code, Kernel membership, reported Kernel, local enablement and `core()` metadata are not additional admission checks. Execution and preview must not query the caller's metadata. Core settlement scenarios own the full caller-identity matrix; the row below is a representative action-to-Core wiring regression.

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-A02 | Fuzz all callers | Action settlement role revoked after public enablement | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Same ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test_givenActionRoleRevoked_whenRepaid_reverts](repay.t.sol#L387) |
| BLDEBT-REPAY-A03 | Fuzz all payers | Required settlement role retained; own activity/enabled state unchanged; external action `kernel()` reports another Kernel or reverts; seed both | Return (remainingPrincipal,resultingHealthFactor) | Collect OHM only from the actual payer; reduce borrower and Inventory principal once; no caller `kernel()` read | Same economic quote under unchanged prices/conversion; no caller metadata read, writes or logs | Covered: [test_givenActionReportedKernelMismatch_whenRepaid_thenGetterIsNotRead](repay.t.sol#L398), [test_givenActionKernelGetterReverts_whenRepaid_thenGetterIsNotRead](repay.t.sol#L411) |

## Dependency lifecycle

Action and Core active/enabled; positive repayment for an existing debt-bearing position. Vary Inventory state independently, with all earlier checks passing. Repayment being permissionless does not bypass this dependency check.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-I03 | Fuzz all callers | true | false | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts](repay.t.sol#L250) |
| BLDEBT-REPAY-D08 | Fuzz all callers | false | true | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change, even with existing idle funds | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts](repay.t.sol#L250) |
| BLDEBT-REPAY-D09 | Fuzz all callers | false | false | `PolicyDependency_NotActive(Inventory)` | No OHM collection or debt change | Same dependency error; no writes | Covered: [test_givenInventoryUnavailable_whenRepaid_reverts](repay.t.sol#L250) |

## Invalid inputs

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-I01 | Fuzz actual payer | amount=0; borrower nonzero | `BurnerLoansCore_ZeroAmount()` | Unchanged; no committed logs | Same BurnerLoansCore_ZeroAmount() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenAmountZero_reverts](repay.t.sol#L171) |
| BLDEBT-REPAY-I02 | Fuzz actual payer | borrower=0; amount>0 | `BurnerLoans_ZeroAddress()` | Unchanged; no committed logs | Same BurnerLoans_ZeroAddress() | Covered: [test_whenBorrowerZero_reverts](repay.t.sol#L181) |
| BLDEBT-REPAY-I04 | Fuzz actual payer | Position absent; pricing when reached valid | `BurnerLoans_NoCollateral()` | Unchanged; no committed logs | Same BurnerLoans_NoCollateral() with all earlier preview checks satisfied; assert no writes | Covered: [test_whenPositionAbsent_reverts](repay.t.sol#L191) |
| BLDEBT-REPAY-I05 | Fuzz actual payer | Existing position with principal=0; fuzz positive amount in 1..MAX128; seed 1,MAX128 | `BurnerLoans_RepayExceedsDebt(amount,0)` | Unchanged; no committed logs | Same BurnerLoans_RepayExceedsDebt(amount,0) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenZeroDebt_whenPositiveRepayment_reverts](repay.t.sol#L202) |
| BLDEBT-REPAY-I06 | Fuzz actual payer | Existing debt D in 1..MAX128-1; fuzz amount D+1..MAX128; seed D+1,MAX128 | `BurnerLoans_RepayExceedsDebt(amount,D)` | Unchanged; no committed logs | Same BurnerLoans_RepayExceedsDebt(amount,D) with all earlier preview checks satisfied; assert no writes | Covered: [test_givenAnyDebt_whenRepaymentExceedsIt_thenExactLiveDebtError](repay.t.sol#L641), [test_whenRepaymentExceedsDebt_reverts](repay.t.sol#L221), [test_givenOneUnitDebt_whenRepaymentExceedsByOne_reverts](repay.t.sol#L662), [test_givenNearMaximumDebt_whenMaximumRepaid_reverts](repay.t.sol#L667) |
| BLDEBT-REPAY-I07 | Fuzz actual payer | nowBlock<=lastBorrowBlock; otherwise valid debt/input | `BurnerLoans_SameBlockRepay(lastBorrowBlock)` | Unchanged; no committed logs | SameBlockRepay check precedes preview pricing; execution may fail earlier during partial-repay refresh; isolate each fault and cross them explicitly | Covered: [test_givenLatestBorrowBlock_whenRepaid_reverts](repay.t.sol#L236) |

## Numeric boundaries and servicing

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-N01 | Fuzz actual payer | Partial repayment; D>1; fuzz amount 1..D-1; seed 1,D-1 and MAX128 where representable | `(D-amount, actual remaining health)` | Exact OHM payer→Inventory; FLOAN and Inventory principal -amount; maturity/collateral unchanged; Repaid | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenAnyPrincipal_whenPartiallyRepaid_thenAggregatesAgree](repay.t.sol#L490), [test_givenPartialDebt_whenAnyPayerRepays_thenExactAccounting](repay.t.sol#L42), [test_whenOneRawUnitRepaid_thenExactRemainingDebt](repay.t.sol#L91), [test_whenAllButOneRawUnitRepaid_thenOneRemains](repay.t.sol#L96), [test_whenOneUnitPartialRepayment_thenNoNarrowing](repay.t.sol#L600), [test_whenMaximumPartialRepayment_thenNoNarrowing](repay.t.sol#L609) |
| BLDEBT-REPAY-N02 | Fuzz actual payer | Full repayment amount=D; seed D=1 and MAX128 | `(0,MAX256)` | No pricing calls; debt episode/index cleared, collateral retained | Quote (0,MAX256) with Risk configured to reject all calls; execution matches without pricing | Covered: [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear](repay.t.sol#L541), [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing](repay.t.sol#L104), [test_whenOneUnitFullRepayment_thenNoNarrowing](repay.t.sol#L587), [test_whenMaximumFullRepayment_thenNoNarrowing](repay.t.sol#L592) |
| BLDEBT-REPAY-N03 | Fuzz actual payer | Expired position; full repayment | `(0,MAX256)` | No maturity admission gate | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenExpiredDebt_whenFullyRepaid_thenAllowed](repay.t.sol#L137) |
| BLDEBT-REPAY-N04 | Fuzz actual payer | Unhealthy position; partial repayment with valid prices | `Resulting health can remain <1e18` | No minimum-health gate | Quote remaining principal and H<WAD; action returns same H without minimum-health rejection | Covered: [test_givenUnhealthyDebt_whenPartiallyRepaid_thenHelpfulRepaymentAllowed](repay.t.sol#L143) |
| BLDEBT-REPAY-N05 | Fuzz actual payer | Originations disabled | `Success` | Servicing remains open | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenOriginationsDisabled_whenRepaid_thenAllowed](repay.t.sol#L159) |
| BLDEBT-REPAY-N06 | Fuzz actual payer | Collateral payout insolvent; full repayment | `(0,MAX256)` | No DM solvency gate | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenInsolventCollateral_whenFullyRepaid_thenAllowed](repay.t.sol#L165) |
| BLDEBT-REPAY-N07 | Fuzz actual payer | Full repayment; Risk unavailable | `(0,MAX256)` | No Risk call | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenAnyPrincipal_whenFullyRepaid_thenEpisodeAndFundingClear](repay.t.sol#L541), [test_givenFullDebt_whenAnyPayerRepays_thenNoPricing](repay.t.sol#L104), [test_whenOneUnitFullRepayment_thenNoNarrowing](repay.t.sol#L587), [test_whenMaximumFullRepayment_thenNoNarrowing](repay.t.sol#L592) |

## Transfer and dependency failures

| ID | Caller | Input / pre-state | Execution / return | Accounting / events | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-D04 | Fuzz actual payer | Partial repayment; snapshot invalid | `BurnerLoans_InvalidPrice()` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenPartialDebt_whenPricingFails_reverts](repay.t.sol#L265), [test_givenRealStalePrice_whenRepayQuotedOrExecuted_reverts](repayIntegration.t.sol#L136) |
| BLDEBT-REPAY-D05 | Fuzz actual payer | OHM recipient delta differs from amount | `SafeERC20Exact_InexactTransferFrom(OHM,Inventory,amount,received)` | Unchanged; no committed logs | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_whenIncomingOhmInexact_thenDebtAndAllowanceRollBack](repay.t.sol#L276) |
| BLDEBT-REPAY-D06 | Fuzz actual payer | MINTR repayment burn fails | `Repayment succeeds` | OhmBurnFailed with exact failure data; burn amount remains surplus | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenMintrBurnFailure_whenRepaid_thenDebtReducedAndOhmRetained](repay.t.sol#L309) |
| BLDEBT-REPAY-D07 | Fuzz actual payer | MINTR approval restoration fails | `Repayment succeeds` | ApprovalRestorationFailed; safe funding-approval deficit remains | Quote without actual payer approval/receipt/transfer; compare conversion independently; only execution proves delivery, exact receipt and atomic rollback | Covered: [test_givenMintrApprovalFailure_whenRepaid_thenSafeApprovalDeficitRemains](repay.t.sol#L344) |

## Shared assertions

Action unit tests use mock Risk for snapshot, fee, health and reward responses used by this function. Assert exact method arguments and call counts, actual Core/FLOAN state and returned configured values; do not duplicate Risk arithmetic in action assertions. Debt-free or full-repayment price-free paths configure the mock to reject unexpected pricing calls. Risk’s suite independently proves math and rounding.

Compare preview and independently calculated principal and WAD health for valid calls. Partial repayment refreshes one snapshot before rereading the position and validating debt bounds/same-block restrictions; snapshot health calculation performs no second oracle read. Full repayment performs no pricing calls. Token transfers are not performed by the view. Zero-borrower validation follows the action rules. Assert borrower token balances do not pay for unrelated callers. Include a mandatory OHM-transfer callback that reaches Core’s guard and propagates failure; assert repayment and token/accounting rollback.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Real Risk integration

Use repayIntegration.t.sol with real Risk, pricing/cache/backing, Core, FLOAN and relevant Inventory/custody dependencies. Use a fixed unrelated payer because permissionless admission is covered in unit scenarios. Derive expected economics independently from prices, decimal scales and actual settlement state. Use existing legacy math/price tests cited below as regression inputs, without marking the rewritten integration Covered.

| ID | Caller | Integration condition | Execution | Required proof | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-P01 | Unrelated payer | Valid real snapshot; compatible custody and funding; independent economic boundary seeds from this function’s numeric rows | Successful operation | Actual balances, collateral/debt, WAD health match an independent calculation; preview agrees only with unchanged prices/conversion | Assert quote independently, then compare corresponding action return fields under equal stored/refreshed snapshots and unchanged conversion; no preview writes | Covered: [test_givenRealRisk_whenUnrelatedPayerPartiallyRepays_thenIndependentHealth](repayIntegration.t.sol#L106) |
| BLDEBT-REPAY-P02 | Unrelated payer | Pricing-dependent path; real feed/cache raises a configured failure; other admission checks pass | Exact configured dependency error | Atomic rollback of all affected contracts, allowances, events and cache writes; do not substitute a mock Risk error for real wiring proof | Real view pricing failure rejects preview; real refresh failure rejects execution; compare exact errors only when the same underlying dependency fails both paths | Covered: [test_givenRealStalePrice_whenRepayQuotedOrExecuted_reverts](repayIntegration.t.sol#L136) |

## Additional isolation coverage

| ID | Caller | Pre-state / input | Expected outcome | Required accounting / preview proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-P03 | Unrelated payer | Two borrowers owe 100 OHM each in one market; fully repay only the first | First debt and episode cleared; second position unchanged | Market/global principal 100 OHM; active borrower list contains only the second; both collateral claims retained; exact payer debit; preview agrees | Covered: [test_givenTwoBorrowers_whenOneFullyRepaid](repayIntegration.t.sol#L18) |
| BLDEBT-REPAY-P04 | Unrelated payer | Same borrower owes 100 OHM in each of two markets; repay 50 OHM in one | Target debt 50 OHM with health 32 WAD; other position unchanged | Market principals 50 and 100 OHM; Inventory principal 150 OHM; custody and both collateral claims retained; preview agrees | Covered: [test_givenTwoMarkets_whenOnePartiallyRepaid](repayIntegration.t.sol#L65) |

## Adversarial cache callbacks before settlement

These cases use the test-only BurnerLoansCallbackCache, not production PriceCache. The fixture selects it using admin authority, then separately grants it borrower operator authority for nested authorized actions. This probes a synthetic hostile dependency; it does not establish callback support as a cache integration requirement. Core's transfer guard is not entered during Risk.refreshSnapshot, so these existing cases describe current behavior before settlement.

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C01 | Borrower | Cache callback borrows for the same authorized borrower; lastBorrowBlock becomes this block; outer partial repay must reject SameBlockRepay and roll back nested debt/cache writes | BurnerLoans_SameBlockRepay(block.number); all nested/outer changes roll back | Successful call reflects actual state; rejected call restores Core/FLOAN/Inventory/DM/cache balances, allowances and logs | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheBorrows_whenPartialRepayRefreshes_thenLatestBorrowBlockRechecked](repayPriceCallbacks.t.sol#L17) |

| ID | Caller | Callback / operation | Execution | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C03 | Borrower | Nested cache action fails an authorization/input check; cache catches the exact nested error | Valid outer action succeeds | No nested mutation; one outer settlement | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCaughtUnauthorizedCacheBorrow_whenRepaying_thenOneRepayment](repayPriceCallbacks.t.sol#L110) |
| BLDEBT-REPAY-C04 | Borrower | Same nested route and fault; cache propagates failure | Exact propagated error rejects outer action | Cache changes, transfers and accounting fully roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenPropagatedUnauthorizedCacheBorrow_whenRepaying_thenRollback](repayPriceCallbacks.t.sol#L124) |

Retired BLDEBT-REPAY-C02 combined caught and propagated callback outcomes; the two independent cases above replace it.

## Post-refresh debt reductions

Use a one-shot cache callback with payer approvals. The outer request is a partial repayment before refresh; the nested repayment changes its debt boundary without requiring its own price refresh when full.

| ID | Caller | Nested operation / live state | Outer result | Effects | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C05 | Payer | Outer amount A>0; cache repays all remaining principal before outer reload | BurnerLoans_RepayExceedsDebt(A,0) | Nested OHM transfer/burn and FLOAN debt reduction roll back | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCacheFullyRepays_whenOuterReloads_thenExcessRepaymentRejected](repayPriceCallbacks.t.sol#L51) |
| BLDEBT-REPAY-C06 | Payer | Cache partially repays; outer amount A exceeds reloaded debt Dnew; nested refresh made one-shot | BurnerLoans_RepayExceedsDebt(A,Dnew) | No stale debt arithmetic; full rollback of cache and both repayments | Stored-snapshot quote; no mutating refresh callback; compare only if callback leaves relevant prices/position unchanged | Covered: [test_givenCachePartiallyRepays_whenOuterAmountTooLarge_thenLiveDebtRechecked](repayPriceCallbacks.t.sol#L83) |

## Transfer callbacks and reentrancy

Use an outer partial repayment and fund a nested repayment of the remaining debt so the callback passes input checks and reaches Core's guard. Repayment requires no operator grant. Configure the existing callback token to propagate the nested rejection.

| ID | Caller | Transfer callback | Execution | Accounting / rollback | Preview / consistency | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-REPAY-C08 | Fuzz all callers | Mandatory payer→Inventory OHM transferFrom attempts nested repayment | Nested `ReentrancyGuardReentrantCall()`; outer `ReentrantFeeToken.CallbackFailed()` | Exact pre-call OHM balances, FLOAN/Inventory principal, provider claims and payer allowance restored; no committed logs | Quote before arming callback; view performs no OHM transfer and cannot predict token failure | Covered: [test_givenOhmCallback_whenRepaid_thenMandatoryReceiptFailureRollsBack](repayCallbacks.t.sol#L15) |
