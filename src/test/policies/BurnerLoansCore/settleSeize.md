# BurnerLoansCore.settleSeize coverage plan

Source: [settleSeize](../../../policies/burnerloans/BurnerLoansCore.sol#L586). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-SEIZE` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_LIQUIDATION_POLICY_ROLE`. Inputs: asset, borrowers:address[], keeper, Snapshot. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-A01 | BL_LIQUIDATION_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-SEIZE-A02 | Fuzz EOA/contracts excluding every BL_LIQUIDATION_POLICY_ROLE holder | false | ROLES_RequireRole(BL_LIQUIDATION_POLICY_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-SEIZE-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_LIQUIDATION_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-SEIZE-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-L01 | BL_LIQUIDATION_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-SEIZE-L02 | BL_LIQUIDATION_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-SEIZE-L03 | BL_LIQUIDATION_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-SEIZE-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-SEIZE-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-I01 | BL_LIQUIDATION_POLICY_ROLE holder | Later borrower position exists with zero debt | FLOAN_InvalidAmount() | Earlier defaults and all receipt/payout state roll back | Covered: [test][test_givenLaterBorrowerWithoutDebt_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I02 | BL_LIQUIDATION_POLICY_ROLE holder | DM returned token differs from expected | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenUnexpectedOutputToken_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I03 | BL_LIQUIDATION_POLICY_ROLE holder | Custody balance decreased during incoming redemption | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenDecreasingBalance_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I04 | BL_LIQUIDATION_POLICY_ROLE holder | Custody incoming delta smaller than returned amount; old surplus present | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenShortPayoutReceipt_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I05 | BL_LIQUIDATION_POLICY_ROLE holder | Custody incoming delta larger than returned amount | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenExcessReceipt_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I06 | BL_LIQUIDATION_POLICY_ROLE holder | Risk reward>actual redemption output | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenExcessiveReward_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-I07 | BL_LIQUIDATION_POLICY_ROLE holder | Custody rejects credit after receipt | BurnerLoansCore_InvalidSettlement() | Unchanged; no committed logs | Covered: [test][test_givenPayoutCreditRejected_whenSeized_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-N01 | BL_LIQUIDATION_POLICY_ROLE holder | Injected inconsistent FLOAN accounting; aggregate debt>MAX128 | SafeCastOverflowedUintDowncast(128,total) | Covered: [test][test_givenInconsistentAggregate_whenSeized_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-P01 | BL_LIQUIDATION_POLICY_ROLE holder | Later borrower position absent | BurnerLoansCore_NoDebt() | Earlier defaults and all receipt/payout state roll back | Covered: [test][test_givenLaterBorrowerMissing_whenSeized_reverts] |
| BLCORE-SETTLE-SEIZE-P02 | BL_LIQUIDATION_POLICY_ROLE holder | Ordinary keeper; positive eligible reward | Seizure succeeds | Debt defaults, actual output split; Seized per borrower then SeizureBatchSettled | Covered: [test][test_givenOrdinaryKeeper_whenSeized], [invariant_canonicalDebtAndCustodyMatchIndependentModel][invariant_canonicalDebtAndCustodyMatchIndependentModel] |
| BLCORE-SETTLE-SEIZE-P03 | BL_LIQUIDATION_POLICY_ROLE holder | Protocol-role keeper | Reward=0 | All actual proceeds Treasury-bound | Covered: [test][test_givenProtocolKeeper_whenSeized] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Only failed bucket stays backed/pending.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-D03 | BL_LIQUIDATION_POLICY_ROLE holder | Final keeper or Treasury transfer fails in its own explicit test | Seizure succeeds | Covered: [test][test_givenKeeperTransferFailure_whenSeized], [test][test_givenTreasuryTransferFailure_whenSeized] |

## Shared assertions

Assert actual custody and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-SEIZE-C01 | Selected same-Kernel active action with the matching settlement role | DM underlying/share redemption to Custody before creditSeizure | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately authorized Custody recovery reaching Core.requireNotReentrant; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Selected positions default once; exact output backs all new keeper/Treasury reserves; Inventory principal reduced once | Covered: [test][test_givenSettlementCallback_whenCaught], [test][test_givenAdminMutationCallback_whenCaught], [test][test_givenPayoutRecoveryCallback_whenCaught] |
| BLCORE-SETTLE-SEIZE-C02 | Selected same-Kernel active action with the matching settlement role | DM underlying/share redemption to Custody before creditSeizure | Public action with a valid borrower/operator grant reaching Core settlement; separately an ADMIN-authorized guarded Core mutation; separately authorized Custody recovery reaching Core.requireNotReentrant; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenSettlementCallback_whenPropagated], [test][test_givenAdminMutationCallback_whenPropagated], [test][test_givenPayoutRecoveryCallback_whenPropagated] |
| BLCORE-SETTLE-SEIZE-C03 | Selected same-Kernel active action with the matching settlement role | Optional Custody→keeper and Custody→Treasury payouts; trigger each independently | Custody retry/recovery reaching Custody local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); payout succeeds | Default and Inventory reconciliation commit once; isolate independent keeper and Treasury payout buckets; delivery clears only its bucket once | Covered: [test][test_givenOptionalKeeperCallback_whenCaught], [test][test_givenOptionalTreasuryCallback_whenCaught] |
| BLCORE-SETTLE-SEIZE-C04 | Selected same-Kernel active action with the matching settlement role | Optional Custody→keeper and Custody→Treasury payouts; trigger each independently | Custody retry/recovery reaching Custody local guard; callback propagates nested rejection | Nested guard error propagates through token; optional payout defers | Default and Inventory reconciliation commit once; isolate independent keeper and Treasury payout buckets; exact unpaid amount stays backed and indexed; later callback-free retry pays once | Covered: [test][test_givenOptionalKeeperCallback_whenPropagated], [test][test_givenOptionalTreasuryCallback_whenPropagated] |

[test_givenAdminMutationCallback_whenCaught]: settleSeize.t.sol#L562
[test_givenAdminMutationCallback_whenPropagated]: settleSeize.t.sol#L597
[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleSeize.t.sol#L156
[test_givenCallerInactive_whenSettled]: settleSeize.t.sol#L143
[test_givenCoreDisabled_whenSettled_reverts]: settleSeize.t.sol#L108
[test_givenCoreInactive_whenSettled_reverts]: settleSeize.t.sol#L123
[test_givenDecreasingBalance_whenSeized_reverts]: settleSeize.t.sol#L884
[test_givenExcessReceipt_whenSeized_reverts]: settleSeize.t.sol#L912
[test_givenExcessiveReward_whenSeized_reverts]: settleSeize.t.sol#L280
[test_givenInconsistentAggregate_whenSeized_reverts]: settleSeize.t.sol#L939
[test_givenKeeperTransferFailure_whenSeized]: settleSeize.t.sol#L429
[test_givenLaterBorrowerMissing_whenSeized_reverts]: settleSeize.t.sol#L179
[test_givenLaterBorrowerWithoutDebt_whenSeized_reverts]: settleSeize.t.sol#L198
[test_givenOnlySiblingRole_whenSettled_reverts]: settleSeize.t.sol#L78
[test_givenOptionalKeeperCallback_whenCaught]: settleSeize.t.sol#L700
[test_givenOptionalKeeperCallback_whenPropagated]: settleSeize.t.sol#L743
[test_givenOptionalTreasuryCallback_whenCaught]: settleSeize.t.sol#L792
[test_givenOptionalTreasuryCallback_whenPropagated]: settleSeize.t.sol#L835
[test_givenOrdinaryKeeper_whenSeized]: settleSeize.t.sol#L334
[test_givenPayoutCreditRejected_whenSeized_reverts]: settleSeize.t.sol#L307
[test_givenPayoutRecoveryCallback_whenCaught]: settleSeize.t.sol#L631
[test_givenPayoutRecoveryCallback_whenPropagated]: settleSeize.t.sol#L666
[test_givenProtocolKeeper_whenSeized]: settleSeize.t.sol#L408
[test_givenRoleHoldingEOA_whenSettled]: settleSeize.t.sol#L149
[test_givenSettlementCallback_whenCaught]: settleSeize.t.sol#L483
[test_givenSettlementCallback_whenPropagated]: settleSeize.t.sol#L523
[test_givenShortPayoutReceipt_whenSeized_reverts]: settleSeize.t.sol#L254
[test_givenTreasuryTransferFailure_whenSeized]: settleSeize.t.sol#L456
[test_givenUnexpectedOutputToken_whenSeized_reverts]: settleSeize.t.sol#L229
[test_givenWrongKernelCaller_whenSettled]: settleSeize.t.sol#L94
[test_whenCallerLacksSettlementRole_reverts]: settleSeize.t.sol#L61

[invariant_canonicalDebtAndCustodyMatchIndependentModel]: settleSeize.t.sol#L987
