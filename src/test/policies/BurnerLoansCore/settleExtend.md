# BurnerLoansCore.settleExtend coverage plan

Source: [settleExtend](../../../policies/burnerloans/BurnerLoansCore.sol#L370). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-EXTEND` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_DEBT_POLICY_ROLE`. Inputs: asset, borrower,payer,maturity:uint48,fee:uint256. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-A01 | BL_DEBT_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-EXTEND-A02 | Fuzz EOA/contracts excluding every BL_DEBT_POLICY_ROLE holder | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-EXTEND-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_DEBT_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-EXTEND-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-L01 | BL_DEBT_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-EXTEND-L02 | BL_DEBT_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-EXTEND-L03 | BL_DEBT_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-EXTEND-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-EXTEND-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Dependency lifecycle

Recommended policy: an origination pause also blocks extensions because a later maturity renews the protocol's credit exposure. This retains the existing scenario expectation while the user considers extension policy. Collateral deposits and repayment remain available. Fixed-term precedents treat extensions as renewed credit approval: [Term Finance rollovers](https://docs.term.finance/protocol/term-repos/rollovers) must clear a new auction; [Maple refinancing](https://docs.maple.finance/technical-resources/interfaces/fixed-term-loan-manager#acceptnewterms) accepts new loan terms. These support the distinction between improving collateral and prolonging a loan; neither is an exact precedent for this flag.

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-D03 | BL_DEBT_POLICY_ROLE holder | Originations disabled | FLOAN_OriginationsDisabled(market) | Covered: [test][test_givenOriginationsDisabled_whenExtended_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-I01 | BL_DEBT_POLICY_ROLE holder | Position exists; debt=0 | FLOAN_InvalidAmount() | Unchanged; no committed logs | Covered: [test][test_givenNoDebt_whenExtended_reverts] |
| BLCORE-SETTLE-EXTEND-I02 | BL_DEBT_POLICY_ROLE holder | newMaturity<=oldMaturity | FLOAN_InvalidMaturity(old,new) | Unchanged; no committed logs | Covered: [test][test_givenNotLater_whenExtended_reverts] |
| BLCORE-SETTLE-EXTEND-I03 | BL_DEBT_POLICY_ROLE holder | newMaturity>oldMaturity but <=now | FLOAN_InvalidMaturity(old,new) | Unchanged; no committed logs | Covered: [test][test_givenExpiredNewMaturity_whenExtended_reverts] |
| BLCORE-SETTLE-EXTEND-I04 | BL_DEBT_POLICY_ROLE holder | Valid instruction; fee=0 | Apply maturity | No fee/Custody call | Covered: [test][test_givenValidMaturity_whenExtended] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-N01 | BL_DEBT_POLICY_ROLE holder | newMaturity exceeds horizon | FLOAN_MaturityHorizonExceeded(new,maximum) | Covered: [test][test_givenHorizonExceeded_whenExtended_reverts], [test][test_whenMaturityMaximumSeed_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-P01 | BL_DEBT_POLICY_ROLE holder | Canonical position absent | BurnerLoansCore_NoDebt() | Unchanged; no committed logs | Covered: [test][test_givenMissingPosition_whenExtended_reverts] |
| BLCORE-SETTLE-EXTEND-P02 | BL_DEBT_POLICY_ROLE holder | Valid instruction; mandatory fee collected and paid | Apply maturity | Exact fee debit/payout; principal/collateral unchanged | Covered: [test][test_givenValidMaturity_whenExtended] |
| BLCORE-SETTLE-EXTEND-P03 | BL_DEBT_POLICY_ROLE holder | Mandatory fee collection fails | Exact configured token error | Unchanged; no committed logs | Covered: [test][test_givenMandatoryFeeFailure_whenExtended_reverts] |
| BLCORE-SETTLE-EXTEND-P04 | BL_DEBT_POLICY_ROLE holder | Mandatory fee received; final payout fails | Extension succeeds | New maturity and backed pending fee committed | Covered: [test][test_givenOptionalPayoutFailure_whenExtended] |

## Shared assertions

Assert actual custody and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-EXTEND-C01 | Selected same-Kernel active action with the matching settlement role | Mandatory extension fee payer→Custody transfer before creditFee | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately authorized Custody recovery before its local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One maturity extension and exact fee collection; principal/collateral unchanged | Covered: [test][test_givenSettlementCallback_whenCaught], [test][test_givenAdminMutationCallback_whenCaught], [test][test_givenPayoutRecoveryCallback_whenCaught] |
| BLCORE-SETTLE-EXTEND-C02 | Selected same-Kernel active action with the matching settlement role | Mandatory extension fee payer→Custody transfer before creditFee | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately authorized Custody recovery before its local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenSettlementCallback_whenPropagated], [test][test_givenAdminMutationCallback_whenPropagated], [test][test_givenPayoutRecoveryCallback_whenPropagated] |
| BLCORE-SETTLE-EXTEND-C03 | Selected same-Kernel active action with the matching settlement role | Optional Custody→fee recipient payout | Custody retry/recovery reaching Custody local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | Maturity extension commits once; optional delivery cannot revoke it; delivery clears only its bucket once | Covered: [test][test_givenOptionalFeeCallback_whenCaught] |
| BLCORE-SETTLE-EXTEND-C04 | Selected same-Kernel active action with the matching settlement role | Optional Custody→fee recipient payout | Custody retry/recovery reaching Custody local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | Maturity extension commits once; optional delivery cannot revoke it; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test][test_givenOptionalFeeCallback_whenPropagated] |

[test_givenAdminMutationCallback_whenCaught]: settleExtend.t.sol#L392
[test_givenAdminMutationCallback_whenPropagated]: settleExtend.t.sol#L427
[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleExtend.t.sol#L107
[test_givenCallerInactive_whenSettled]: settleExtend.t.sol#L94
[test_givenCoreDisabled_whenSettled_reverts]: settleExtend.t.sol#L69
[test_givenCoreInactive_whenSettled_reverts]: settleExtend.t.sol#L79
[test_givenExpiredNewMaturity_whenExtended_reverts]: settleExtend.t.sol#L189
[test_givenHorizonExceeded_whenExtended_reverts]: settleExtend.t.sol#L204
[test_givenMandatoryFeeFailure_whenExtended_reverts]: settleExtend.t.sol#L238
[test_givenMissingPosition_whenExtended_reverts]: settleExtend.t.sol#L223
[test_givenNoDebt_whenExtended_reverts]: settleExtend.t.sol#L158
[test_givenNotLater_whenExtended_reverts]: settleExtend.t.sol#L174
[test_givenOnlySiblingRole_whenSettled_reverts]: settleExtend.t.sol#L44
[test_givenOptionalFeeCallback_whenCaught]: settleExtend.t.sol#L530
[test_givenOptionalFeeCallback_whenPropagated]: settleExtend.t.sol#L566
[test_givenOptionalPayoutFailure_whenExtended]: settleExtend.t.sol#L290
[test_givenOriginationsDisabled_whenExtended_reverts]: settleExtend.t.sol#L135
[test_givenPayoutRecoveryCallback_whenCaught]: settleExtend.t.sol#L461
[test_givenPayoutRecoveryCallback_whenPropagated]: settleExtend.t.sol#L496
[test_givenRoleHoldingEOA_whenSettled]: settleExtend.t.sol#L100
[test_givenSettlementCallback_whenCaught]: settleExtend.t.sol#L313
[test_givenSettlementCallback_whenPropagated]: settleExtend.t.sol#L353
[test_givenValidMaturity_whenExtended]: settleExtend.t.sol#L265
[test_givenWrongKernelCaller_whenSettled]: settleExtend.t.sol#L55
[test_whenCallerLacksSettlementRole_reverts]: settleExtend.t.sol#L32
[test_whenMaturityMaximumSeed_reverts]: settleExtend.t.sol#L608
