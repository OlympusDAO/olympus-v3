# BurnerLoansCore.settleDeposit coverage plan

Source: [settleDeposit](../../../policies/burnerloans/BurnerLoansCore.sol#L254). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-DEPOSIT` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_COLLATERAL_POLICY_ROLE`. Inputs: asset, amount:uint128, payer, borrower. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan. With originations disabled, deposits remain permitted for new collateral-only positions and existing positions, with or without debt. Borrowing and extension keep their separate gates.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-A01 | BL_COLLATERAL_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-DEPOSIT-A02 | Fuzz EOA/contracts excluding every BL_COLLATERAL_POLICY_ROLE holder | false | ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-DEPOSIT-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-DEPOSIT-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-L01 | BL_COLLATERAL_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-DEPOSIT-L02 | BL_COLLATERAL_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-DEPOSIT-L03 | BL_COLLATERAL_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-DEPOSIT-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-DEPOSIT-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-I01 | BL_COLLATERAL_POLICY_ROLE holder | DM actual credit=0 | BurnerLoansCore_ZeroCollateralCredit() | Unchanged; no committed logs | Covered: [test][test_givenZeroActualCredit_whenDeposited_reverts] |
| BLCORE-SETTLE-DEPOSIT-I02 | BL_COLLATERAL_POLICY_ROLE holder | Receipt manager=0 | Complete deposit; skip receipt-burn approval | Credit actual DepositManager output to FLOAN; no receipt approval call | Covered: [test][test_givenNoReceiptManager_whenDeposited] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-N01 | BL_COLLATERAL_POLICY_ROLE holder | DM actual credit fuzz MAX128+1..MAX256; seed both endpoints | SafeCastOverflowedUintDowncast(128,credit) | Covered: [test][test_givenCreditExceedsUint128_whenDeposited_reverts], [test][test_whenCreditOverflowBoundarySeeds_reverts] |

## Position transitions

First deposits and existing-position top-ups are permitted with originations enabled or disabled. Position existence comes from canonical FLOAN lookup, not a positive-debt or positive-collateral test. Remove origination checks from collateral-only position creation, collateral addition and the public deposit action/preview; borrowing and extension retain their own checks. DepositManager asset/period enablement, deposit caps and normal policy pauses still apply.

| ID | Caller | Prior position / operation | Originations enabled | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-P01 | BL_COLLATERAL_POLICY_ROLE holder | Registered market; canonical position absent; positive exact receipt/nonzero representable DM credit | true | Create then credit position; return actual credit and collateral | Core receipt/DM operator/FLOAN collateral deltas consistent | Covered: [test][test_whenCreditedDepositIsPositive], [test][test_whenDepositAmountSeeds], [invariant_canonicalDebtAndCustodyMatchIndependentModel][invariant_canonicalDebtAndCustodyMatchIndependentModel] |
| BLCORE-SETTLE-DEPOSIT-P02 | BL_COLLATERAL_POLICY_ROLE holder | Registered market; existing collateral-only position; positive actual credit | Fuzz false/true; seed both | Credit existing position | No duplicate position creation | Covered: [test][test_givenCollateralOnlyPosition_whenOriginationsArePaused], [test][test_whenCollateralOnlyTopUpOriginationStatesSeeded] |
| BLCORE-SETTLE-DEPOSIT-P07 | BL_COLLATERAL_POLICY_ROLE holder | Registered market; existing debt-bearing position; positive actual credit | Fuzz false/true; seed both | Credit existing position | Collateral increases by actual credit; principal/expiry unchanged; no debt origination or extension | Covered: [test][test_givenDebtBearingPosition_whenOriginationsArePaused], [test][test_whenDebtBearingTopUpOriginationStatesSeeded] |
| BLCORE-SETTLE-DEPOSIT-I03 | BL_COLLATERAL_POLICY_ROLE holder | Registered market; no canonical position; valid positive deposit | false | Create and credit a collateral-only position | Exact DM custody/credit and canonical collateral; one new position; zero debt/maturity | Covered: [test][test_givenOriginationsDisabledAndNoPosition_whenDeposited] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-P03 | BL_COLLATERAL_POLICY_ROLE holder | Core has preexisting donated collateral; incoming receipt exact | Success | Donation not counted as new credit; no residual-balance assertion | Covered: [test][test_givenPreexistingDonation_whenDeposited] |
| BLCORE-SETTLE-DEPOSIT-P04 | BL_COLLATERAL_POLICY_ROLE holder | Receipt approve returns false | BurnerLoansCore_ReceiptApprovalFailed(manager) | Unchanged; no committed logs | Covered: [test][test_givenRejectedReceiptApproval_whenDeposited_reverts] |
| BLCORE-SETTLE-DEPOSIT-P05 | BL_COLLATERAL_POLICY_ROLE holder | Incoming amount short | SafeERC20Exact_InexactTransferFrom(asset,Core,amount,received) | Unchanged; no committed logs | Covered: [test][test_givenShortIncomingReceipt_whenSettled_reverts] |
| BLCORE-SETTLE-DEPOSIT-P06 | BL_COLLATERAL_POLICY_ROLE holder | Incoming amount excessive | SafeERC20Exact_InexactTransferFrom(asset,Core,amount,received) | Unchanged; no committed logs | Covered: [test][test_givenExcessIncomingReceipt_whenSettled_reverts] |

## Transfers and dependency failures

Fixed for this table: Deposit succeeds; actual credit, FLOAN collateral and DepositManager liabilities increase once. Only the receipt approval branch varies.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-D03 | BL_COLLATERAL_POLICY_ROLE holder | Receipt allowance already MAX256 | Skip approval write | Covered: [test][test_givenExistingReceiptApproval_whenDeposited] |
| BLCORE-SETTLE-DEPOSIT-D04 | BL_COLLATERAL_POLICY_ROLE holder | Receipt allowance below MAX256; approve returns true | Deposit then approve MAX256 for receipt burning | Covered: [test][test_givenFreshReceiptApproval_whenDeposited] |

## Shared assertions

Assert actual payout and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-DEPOSIT-C01 | Selected same-Kernel active action with the matching settlement role | Collateral token transferFrom from payer into Core | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One outer deposit only; actual Q credited once to FLOAN and Core DM liabilities/receipts; payer funds debited once; unrelated borrower/operator unchanged | Covered: [test][test_givenSettlementCallback_whenCaught] |
| BLCORE-SETTLE-DEPOSIT-C02 | Selected same-Kernel active action with the matching settlement role | Collateral token transferFrom from payer into Core | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenSettlementCallback_whenPropagated] |

[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleDeposit.t.sol#L108
[test_givenCallerInactive_whenSettled]: settleDeposit.t.sol#L95
[test_givenCollateralOnlyPosition_whenOriginationsArePaused]: settleDeposit.t.sol#L159
[test_givenCoreDisabled_whenSettled_reverts]: settleDeposit.t.sol#L70
[test_givenCoreInactive_whenSettled_reverts]: settleDeposit.t.sol#L80
[test_givenCreditExceedsUint128_whenDeposited_reverts]: settleDeposit.t.sol#L255
[test_givenDebtBearingPosition_whenOriginationsArePaused]: settleDeposit.t.sol#L179
[test_givenExcessIncomingReceipt_whenSettled_reverts]: settleDeposit.t.sol#L462
[test_givenExistingReceiptApproval_whenDeposited]: settleDeposit.t.sol#L297
[test_givenFreshReceiptApproval_whenDeposited]: settleDeposit.t.sol#L324
[test_givenNoReceiptManager_whenDeposited]: settleDeposit.t.sol#L285
[test_givenOnlySiblingRole_whenSettled_reverts]: settleDeposit.t.sol#L45
[test_givenOriginationsDisabledAndNoPosition_whenDeposited]: settleDeposit.t.sol#L216
[test_givenPreexistingDonation_whenDeposited]: settleDeposit.t.sol#L276
[test_givenRejectedReceiptApproval_whenDeposited_reverts]: settleDeposit.t.sol#L346
[test_givenRoleHoldingEOA_whenSettled]: settleDeposit.t.sol#L101
[test_givenSettlementCallback_whenCaught]: settleDeposit.t.sol#L369
[test_givenSettlementCallback_whenPropagated]: settleDeposit.t.sol#L400
[test_givenShortIncomingReceipt_whenSettled_reverts]: settleDeposit.t.sol#L431
[test_givenWrongKernelCaller_whenSettled]: settleDeposit.t.sol#L56
[test_givenZeroActualCredit_whenDeposited_reverts]: settleDeposit.t.sol#L241
[test_whenCallerLacksSettlementRole_reverts]: settleDeposit.t.sol#L33
[test_whenCollateralOnlyTopUpOriginationStatesSeeded]: settleDeposit.t.sol#L200
[test_whenCreditOverflowBoundarySeeds_reverts]: settleDeposit.t.sol#L493
[test_whenCreditedDepositIsPositive]: settleDeposit.t.sol#L124
[test_whenDebtBearingTopUpOriginationStatesSeeded]: settleDeposit.t.sol#L208
[test_whenDepositAmountSeeds]: settleDeposit.t.sol#L151

[invariant_canonicalDebtAndCustodyMatchIndependentModel]: settleSeize.t.sol#L963
