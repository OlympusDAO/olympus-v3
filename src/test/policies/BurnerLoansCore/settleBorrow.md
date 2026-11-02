# BurnerLoansCore.settleBorrow coverage plan

Source: [settleBorrow](../../../policies/burnerloans/BurnerLoansCore.sol#L322). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-BORROW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_DEBT_POLICY_ROLE`. Inputs: BorrowRequest asset,borrower,payer,recipient,amount:uint128,maturity:uint48,fee:uint256. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan. In particular, the action must reject its own address as the user-selected output recipient before instructing Core. Core trusts this public-layer validation; these settlement tests do not invent a second action-recipient guard on Core.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-A01 | BL_DEBT_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-BORROW-A02 | Fuzz EOA/contracts excluding every BL_DEBT_POLICY_ROLE holder | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [invariant_lifecycleAuthorizationAndCustodyStayIndependent](setAuthorization.t.sol#L193), [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-BORROW-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-BORROW-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-L01 | BL_DEBT_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-BORROW-L02 | BL_DEBT_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-BORROW-L03 | BL_DEBT_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-BORROW-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-BORROW-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Dependency lifecycle

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-D03 | BL_DEBT_POLICY_ROLE holder | Originations disabled | FLOAN_OriginationsDisabled(market) | Covered: [test][test_givenOriginationsDisabled_whenBorrowed_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-I01 | BL_DEBT_POLICY_ROLE holder | maturity<=now; fuzz 0..now and seed 0,now-1,now; expected bound is now and actual value is submitted maturity | FLOAN_InvalidMaturity(now,maturity) | Unchanged; no committed logs | Covered: [test][test_givenPastMaturity_whenBorrowed_reverts], [test][test_whenPastMaturityBoundarySeeds_reverts] |
| BLCORE-SETTLE-BORROW-I02 | BL_DEBT_POLICY_ROLE holder | Existing debt; submitted maturity differs | FLOAN_InvalidMaturity(old,new) | Unchanged; no committed logs | Covered: [test][test_givenChangedActiveMaturity_whenBorrowed_reverts] |
| BLCORE-SETTLE-BORROW-I03 | BL_DEBT_POLICY_ROLE holder | Valid instruction; fee=0 | Success | No fee token/Custody call; Inventory funds principal | Covered: [test][test_givenZeroFee_whenBorrowed], [test][test_whenPrincipalBoundarySeeds], [test][test_whenOnePrincipalSeed], [invariant_canonicalDebtAndCustodyMatchIndependentModel](settleSeize.t.sol#L963) |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-N01 | BL_DEBT_POLICY_ROLE holder | amount=0 | FLOAN_InvalidAmount() | Covered: [test][test_givenZeroAmount_whenBorrowed_reverts] |
| BLCORE-SETTLE-BORROW-N02 | BL_DEBT_POLICY_ROLE holder | First debt exceeds maximum horizon | FLOAN_MaturityHorizonExceeded(new,maximum) | Covered: [test][test_givenHorizonExceeded_whenBorrowed_reverts] |
| BLCORE-SETTLE-BORROW-N03 | BL_DEBT_POLICY_ROLE holder | Market principal cap exceeded | FLOAN_PrincipalCapExceeded(market,cap) | Covered: [test][test_givenCapExceeded_whenBorrowed_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-P01 | BL_DEBT_POLICY_ROLE holder | Canonical position absent | BurnerLoansCore_NoDebt() | Unchanged; no committed logs | Covered: [test][test_givenMissingPosition_whenBorrowed_reverts] |
| BLCORE-SETTLE-BORROW-P02 | BL_DEBT_POLICY_ROLE holder | Fee>0; incoming transfer blocked | Exact configured token error | Unchanged; no committed logs | Covered: [test][test_givenMandatoryFeeFailure_whenBorrowed_reverts] |
| BLCORE-SETTLE-BORROW-P03 | BL_DEBT_POLICY_ROLE holder | Fee>0; incoming Custody receipt inexact | SafeERC20Exact_InexactTransferFrom(asset,Custody,fee,received) | Unchanged; no committed logs | Covered: [test][test_givenShortIncomingReceipt_whenSettled_reverts], [test][test_givenExcessIncomingReceipt_whenSettled_reverts] |
| BLCORE-SETTLE-BORROW-P04 | BL_DEBT_POLICY_ROLE holder | Exact incoming fee; final protocol payout fails | Borrow succeeds | Custody keeps backed pending fee; recipient gets principal | Covered: [test][test_givenOptionalPayoutFailure_whenBorrowed] |
| BLCORE-SETTLE-BORROW-P05 | BL_DEBT_POLICY_ROLE holder | Inventory draw reverts after fee credit | Exact configured Inventory error | Unchanged; no committed logs | Covered: [test][test_givenInventoryFailureAfterFee_whenBorrowed_reverts] |

## Shared assertions

Assert actual custody and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-BORROW-C01 | Selected same-Kernel active action with the matching settlement role | Mandatory payer→Custody fee transfer before Custody.creditFee; positive fee | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately ADMIN-authorized Custody recovery to exercise Core.requireNotReentrant before Custody local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One debt/maturity increase and exact fee collection; one Inventory draw; no nested payout recovery | Covered: [test][test_givenSettlementCallback_whenCaught], [test][test_givenAdminMutationCallback_whenCaught], [test][test_givenPayoutRecoveryCallback_whenCaught] |
| BLCORE-SETTLE-BORROW-C02 | Selected same-Kernel active action with the matching settlement role | Mandatory payer→Custody fee transfer before Custody.creditFee; positive fee | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately ADMIN-authorized Custody recovery to exercise Core.requireNotReentrant before Custody local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenSettlementCallback_whenPropagated], [test][test_givenAdminMutationCallback_whenPropagated], [test][test_givenPayoutRecoveryCallback_whenPropagated] |
| BLCORE-SETTLE-BORROW-C03 | Selected same-Kernel active action with the matching settlement role | Inventory mint/funding and OHM delivery to the borrower-selected recipient | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One funded principal increase and recipient OHM delivery; cap/provider/MINTR accounting agree | Covered: [test][test_givenOhmCallback_whenCaught] |
| BLCORE-SETTLE-BORROW-C04 | Selected same-Kernel active action with the matching settlement role | Inventory mint/funding and OHM delivery to the borrower-selected recipient | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenOhmCallback_whenPropagated] |
| BLCORE-SETTLE-BORROW-C05 | Selected same-Kernel active action with the matching settlement role | Optional Custody→fee recipient payout after mandatory fee receipt | Custody retry/recovery with its required authority reaching Custody local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | Borrow succeeds once; principal and funding unchanged by optional payout failure; delivery clears only its bucket once | Covered: [test][test_givenOptionalFeeCallback_whenCaught] |
| BLCORE-SETTLE-BORROW-C06 | Selected same-Kernel active action with the matching settlement role | Optional Custody→fee recipient payout after mandatory fee receipt | Custody retry/recovery with its required authority reaching Custody local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | Borrow succeeds once; principal and funding unchanged by optional payout failure; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test][test_givenOptionalFeeCallback_whenPropagated] |

[test_givenAdminMutationCallback_whenCaught]: settleBorrow.t.sol#L461
[test_givenAdminMutationCallback_whenPropagated]: settleBorrow.t.sol#L489
[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleBorrow.t.sol#L116
[test_givenCallerInactive_whenSettled]: settleBorrow.t.sol#L103
[test_givenCapExceeded_whenBorrowed_reverts]: settleBorrow.t.sol#L250
[test_givenChangedActiveMaturity_whenBorrowed_reverts]: settleBorrow.t.sol#L196
[test_givenCoreDisabled_whenSettled_reverts]: settleBorrow.t.sol#L74
[test_givenCoreInactive_whenSettled_reverts]: settleBorrow.t.sol#L86
[test_givenExcessIncomingReceipt_whenSettled_reverts]: settleBorrow.t.sol#L735
[test_givenHorizonExceeded_whenBorrowed_reverts]: settleBorrow.t.sol#L228
[test_givenInventoryFailureAfterFee_whenBorrowed_reverts]: settleBorrow.t.sol#L308
[test_givenMandatoryFeeFailure_whenBorrowed_reverts]: settleBorrow.t.sol#L284
[test_givenMissingPosition_whenBorrowed_reverts]: settleBorrow.t.sol#L271
[test_givenOhmCallback_whenCaught]: settleBorrow.t.sol#L635
[test_givenOhmCallback_whenPropagated]: settleBorrow.t.sol#L669
[test_givenOnlySiblingRole_whenSettled_reverts]: settleBorrow.t.sol#L47
[test_givenOptionalFeeCallback_whenCaught]: settleBorrow.t.sol#L571
[test_givenOptionalFeeCallback_whenPropagated]: settleBorrow.t.sol#L600
[test_givenOptionalPayoutFailure_whenBorrowed]: settleBorrow.t.sol#L355
[test_givenOriginationsDisabled_whenBorrowed_reverts]: settleBorrow.t.sol#L143
[test_givenPastMaturity_whenBorrowed_reverts]: settleBorrow.t.sol#L163
[test_whenPastMaturityBoundarySeeds_reverts]: settleBorrow.t.sol#L184
[test_givenPayoutRecoveryCallback_whenCaught]: settleBorrow.t.sol#L516
[test_givenPayoutRecoveryCallback_whenPropagated]: settleBorrow.t.sol#L544
[test_givenRoleHoldingEOA_whenSettled]: settleBorrow.t.sol#L109
[test_givenSettlementCallback_whenCaught]: settleBorrow.t.sol#L396
[test_givenSettlementCallback_whenPropagated]: settleBorrow.t.sol#L429
[test_givenShortIncomingReceipt_whenSettled_reverts]: settleBorrow.t.sol#L703
[test_givenWrongKernelCaller_whenSettled]: settleBorrow.t.sol#L60
[test_givenZeroAmount_whenBorrowed_reverts]: settleBorrow.t.sol#L214
[test_givenZeroFee_whenBorrowed]: settleBorrow.t.sol#L327
[test_whenCallerLacksSettlementRole_reverts]: settleBorrow.t.sol#L33
[test_whenOnePrincipalSeed]: settleBorrow.t.sol#L767
[test_whenPrincipalBoundarySeeds]: settleBorrow.t.sol#L350
