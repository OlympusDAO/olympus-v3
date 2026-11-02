# BurnerLoansCore.settleRepay coverage plan

Source: [settleRepay](../../../policies/burnerloans/BurnerLoansCore.sol#L345). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-REPAY` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_DEBT_POLICY_ROLE`. Inputs: asset, amount:uint128, payer, borrower. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-A01 | BL_DEBT_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-REPAY-A02 | Fuzz EOA/contracts excluding every BL_DEBT_POLICY_ROLE holder | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-REPAY-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-REPAY-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-L01 | BL_DEBT_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-REPAY-L02 | BL_DEBT_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-REPAY-L03 | BL_DEBT_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-REPAY-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-REPAY-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Dependency lifecycle

Fixed for this table: Accounting / events: Servicing allowed.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-D03 | BL_DEBT_POLICY_ROLE holder | Originations disabled; valid repayment | Success | Covered: [test][test_givenLiveDebt_whenRepaid], [test][test_whenRepaymentBoundarySeeds] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-I01 | BL_DEBT_POLICY_ROLE holder | Existing position; principal=0 | FLOAN_InvalidAmount() | Covered: [test][test_givenNoDebt_whenRepaid_reverts] |
| BLCORE-SETTLE-REPAY-I02 | BL_DEBT_POLICY_ROLE holder | amount>debt | FLOAN_InvalidAmount() | Covered: [test][test_givenOverpayment_whenRepaid_reverts], [test][test_whenOverpaymentMaximumSeed_reverts] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-N01 | BL_DEBT_POLICY_ROLE holder | Existing position; amount=0 | FLOAN_InvalidAmount() | Unchanged; no committed logs | Covered: [test][test_givenZeroAmount_whenRepaid_reverts] |
| BLCORE-SETTLE-REPAY-N02 | BL_DEBT_POLICY_ROLE holder | amount<debt | Remaining principal=debt-amount | FLOAN/Inventory totals decrease; episode metadata retained | Covered: [test][test_givenLiveDebt_whenRepaid], [test][test_whenRepaymentBoundarySeeds], [invariant_canonicalDebtAndCustodyMatchIndependentModel](settleSeize.t.sol#L963) |
| BLCORE-SETTLE-REPAY-N03 | BL_DEBT_POLICY_ROLE holder | amount=debt | Remaining principal=0 | Debt episode metadata and active index cleared | Covered: [test][test_givenLiveDebt_whenRepaid], [test][test_whenRepaymentBoundarySeeds], [invariant_canonicalDebtAndCustodyMatchIndependentModel](settleSeize.t.sol#L963) |

## Successful execution

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-P01 | BL_DEBT_POLICY_ROLE holder | Canonical position absent | BurnerLoansCore_NoDebt() | Covered: [test][test_givenMissingPosition_whenRepaid_reverts] |
| BLCORE-SETTLE-REPAY-P02 | BL_DEBT_POLICY_ROLE holder | Incoming OHM short or excessive; independent seeds | SafeERC20Exact_InexactTransferFrom(OHM,Inventory,amount,received) | Covered: [test][test_givenShortIncomingReceipt_whenSettled_reverts], [test][test_givenExcessIncomingReceipt_whenSettled_reverts] |
| BLCORE-SETTLE-REPAY-P03 | BL_DEBT_POLICY_ROLE holder | Inventory repayment settlement rejects | Exact configured Inventory error | Covered: [test][test_givenInventoryFailure_whenRepaid_reverts] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Inventory retains surplus; OhmBurnFailed.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-D04 | BL_DEBT_POLICY_ROLE holder | MINTR excess burn fails | Repayment succeeds | Covered: [test][test_givenBurnFailure_whenRepaid] |

## Shared assertions

Assert actual custody and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-REPAY-C01 | Selected same-Kernel active action with the matching settlement role | Payer→Inventory OHM transferFrom before Inventory.settleRepayment enters its local guard | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One actual debt reduction and exact OHM collection; correct Inventory retained/burned amounts and provider claims | Covered: [test][test_givenOhmCallback_whenCaught] |
| BLCORE-SETTLE-REPAY-C02 | Selected same-Kernel active action with the matching settlement role | Payer→Inventory OHM transferFrom before Inventory.settleRepayment enters its local guard | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenOhmCallback_whenPropagated] |

[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleRepay.t.sol#L107
[test_givenBurnFailure_whenRepaid]: settleRepay.t.sol#L248
[test_givenCallerInactive_whenSettled]: settleRepay.t.sol#L94
[test_givenCoreDisabled_whenSettled_reverts]: settleRepay.t.sol#L69
[test_givenCoreInactive_whenSettled_reverts]: settleRepay.t.sol#L79
[test_givenExcessIncomingReceipt_whenSettled_reverts]: settleRepay.t.sol#L378
[test_givenInventoryFailure_whenRepaid_reverts]: settleRepay.t.sol#L169
[test_givenLiveDebt_whenRepaid]: settleRepay.t.sol#L187
[test_givenMissingPosition_whenRepaid_reverts]: settleRepay.t.sol#L160
[test_givenNoDebt_whenRepaid_reverts]: settleRepay.t.sol#L127
[test_givenOhmCallback_whenCaught]: settleRepay.t.sol#L267
[test_givenOhmCallback_whenPropagated]: settleRepay.t.sol#L304
[test_givenOnlySiblingRole_whenSettled_reverts]: settleRepay.t.sol#L44
[test_givenOverpayment_whenRepaid_reverts]: settleRepay.t.sol#L137
[test_givenRoleHoldingEOA_whenSettled]: settleRepay.t.sol#L100
[test_givenShortIncomingReceipt_whenSettled_reverts]: settleRepay.t.sol#L341
[test_givenWrongKernelCaller_whenSettled]: settleRepay.t.sol#L55
[test_givenZeroAmount_whenRepaid_reverts]: settleRepay.t.sol#L149
[test_whenCallerLacksSettlementRole_reverts]: settleRepay.t.sol#L32
[test_whenOverpaymentMaximumSeed_reverts]: settleRepay.t.sol#L415
[test_whenRepaymentBoundarySeeds]: settleRepay.t.sol#L237
