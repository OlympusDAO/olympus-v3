# BurnerLoansCore.settleWithdraw coverage plan

Source: [settleWithdraw](../../../policies/burnerloans/BurnerLoansCore.sol#L372). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

The settlement ABI uses `WithdrawRequest`, which carries asset, amount, borrower and recipient. Operator and original authorization context remain separate arguments. Existing scenario outcomes, numeric domains, identity distinctions, callbacks and rollback assertions are unchanged.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-WITHDRAW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_COLLATERAL_POLICY_ROLE`. Inputs: asset, amount:uint128, borrower, recipient. Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan. In particular, the action must reject its own address as the user-selected output recipient before instructing Core. Core trusts this public-layer validation; these settlement tests do not invent a second action-recipient guard on Core.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-A01 | BL_COLLATERAL_POLICY_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-WITHDRAW-A02 | Fuzz EOA/contracts excluding every BL_COLLATERAL_POLICY_ROLE holder | false | ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts]  [valid captured authority][test_givenLiveGrant_whenUnadmittedCallerReusesContext_reverts] |
| BLCORE-SETTLE-WITHDRAW-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-WITHDRAW-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-L01 | BL_COLLATERAL_POLICY_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-WITHDRAW-L02 | BL_COLLATERAL_POLICY_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-WITHDRAW-L03 | BL_COLLATERAL_POLICY_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-WITHDRAW-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-WITHDRAW-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-I01 | BL_COLLATERAL_POLICY_ROLE holder | DM output=0 after valid debit | BurnerLoansCore_ZeroCollateralWithdrawal() | Covered: [test][test_givenZeroOutput_whenWithdrawn_reverts] |
| BLCORE-SETTLE-WITHDRAW-I02 | BL_COLLATERAL_POLICY_ROLE holder | DM returned token differs from expected | BurnerLoansCore_InvalidSettlement() | Covered: [test][test_givenUnexpectedOutputToken_whenWithdrawn_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-N01 | BL_COLLATERAL_POLICY_ROLE holder | amount=0 | FLOAN_InvalidAmount() | Covered: [test][test_givenZeroAmount_whenWithdrawn_reverts] |
| BLCORE-SETTLE-WITHDRAW-N02 | BL_COLLATERAL_POLICY_ROLE holder | collateral<MAX128; fuzz amount collateral+1..MAX128 | FLOAN_InvalidAmount() | Covered: [test][test_givenAboveCollateral_whenWithdrawn_reverts], [test][test_whenCollateralDebitMaximumSeed_reverts] |

## Configuration transitions

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Prior configuration / update | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-P01 | BL_COLLATERAL_POLICY_ROLE holder | Registered market; canonical position absent | BurnerLoansCore_NoDebt() | Covered: [test][test_givenMissingPosition_whenWithdrawn_reverts] |

## Successful execution

Fixed for this table: Accounting / events: No ordinary-recipient Core delta assertion; no user health check at Core.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-P02 | BL_COLLATERAL_POLICY_ROLE holder | Ordinary recipient; DM success; actual output differs numerically from credit debit | Return actual token/output/remaining | Covered: [invariant_canonicalDebtAndCustodyMatchIndependentModel][invariant_canonicalDebtAndCustodyMatchIndependentModel], [test][test_givenActualOutputDifferentFromDebit_whenWithdrawn], [test][test_givenRealCustody_whenWithdrawn], [test][test_whenWithdrawalBoundarySeeds] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-D03 | BL_COLLATERAL_POLICY_ROLE holder | Recipient=Custody; receipt delta differs from reported output | BurnerLoansCore_InvalidSettlement() | Covered: [test][test_givenPayoutRecipientAndInexactDelta_whenWithdrawn_reverts] |

## Shared assertions

Assert actual payout and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-C01 | Selected same-Kernel active action with the matching settlement role | DM redemption and direct underlying/share delivery to recipient | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | One collateral debit and recipient output; actual remaining collateral and WAD health agree; unrelated positions unchanged | Covered: [test][test_givenSettlementCallback_whenCaught] |
| BLCORE-SETTLE-WITHDRAW-C02 | Selected same-Kernel active action with the matching settlement role | DM redemption and direct underlying/share delivery to recipient | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenSettlementCallback_whenPropagated] |

## Delegated completion

Core, the selected Auth and the admitted Collateral action are active/enabled. Account A has a reusable withdrawal grant for O with its fixed recipient. All collateral values below are raw units; the floor applies to the remaining canonical position.

| ID | Caller | Existing collateral | Withdrawal | minCollateral | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-N90 | Collateral action forwarding O | 1000 | 100 | 901 | ResultOutsideGrant: remaining 900 is one raw unit below the floor; custody and position roll back | Covered: [test][test_givenDelegatedGrant_whenRemainingCollateralBelowFloor_reverts] |
| BLCORE-SETTLE-WITHDRAW-P90 | Collateral action forwarding O | 1000 | 100 | 900 | Success: remaining collateral 900; recipient receives 100 | Covered: [test][test_givenDelegatedGrant_whenRemainingCollateralEqualsFloor] |

## Request ABI validation

| ID | Caller | Raw economic field | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-WITHDRAW-I03 | Unadmitted recipient account | amount > uint128 maximum | Compiler ABI rejection before role checks; empty returndata | Custody and positions unchanged | Covered: [test][test_whenMalformedEconomicRequest_thenAbiDecodingRejectsBeforeRoleCheck] |

[invariant_canonicalDebtAndCustodyMatchIndependentModel]: settleSeize.t.sol#L987
[test_givenAboveCollateral_whenWithdrawn_reverts]: settleWithdraw.t.sol#L258
[test_givenActualOutputDifferentFromDebit_whenWithdrawn]: settleWithdraw.t.sol#L348
[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleWithdraw.t.sol#L211
[test_givenCallerInactive_whenSettled]: settleWithdraw.t.sol#L198
[test_givenCoreDisabled_whenSettled_reverts]: settleWithdraw.t.sol#L155
[test_givenCoreInactive_whenSettled_reverts]: settleWithdraw.t.sol#L174
[test_givenDelegatedGrant_whenRemainingCollateralBelowFloor_reverts]: authorizationLifecycleWithdraw.t.sol#L15
[test_givenDelegatedGrant_whenRemainingCollateralEqualsFloor]: authorizationLifecycleWithdraw.t.sol#L40
[test_givenMissingPosition_whenWithdrawn_reverts]: settleWithdraw.t.sol#L280
[test_givenOnlySiblingRole_whenSettled_reverts]: settleWithdraw.t.sol#L121
[test_givenPayoutRecipientAndInexactDelta_whenWithdrawn_reverts]: settleWithdraw.t.sol#L419
[test_givenRealCustody_whenWithdrawn]: settleWithdraw.t.sol#L386
[test_givenRoleHoldingEOA_whenSettled]: settleWithdraw.t.sol#L204
[test_givenSettlementCallback_whenCaught]: settleWithdraw.t.sol#L454
[test_givenSettlementCallback_whenPropagated]: settleWithdraw.t.sol#L496
[test_givenUnexpectedOutputToken_whenWithdrawn_reverts]: settleWithdraw.t.sol#L322
[test_givenWrongKernelCaller_whenSettled]: settleWithdraw.t.sol#L141
[test_givenZeroAmount_whenWithdrawn_reverts]: settleWithdraw.t.sol#L237
[test_givenZeroOutput_whenWithdrawn_reverts]: settleWithdraw.t.sol#L298
[test_whenCallerLacksSettlementRole_reverts]: settleWithdraw.t.sol#L100
[test_whenCollateralDebitMaximumSeed_reverts]: settleWithdraw.t.sol#L537
[test_whenMalformedEconomicRequest_thenAbiDecodingRejectsBeforeRoleCheck]: ./settleWithdraw.t.sol#L35
[test_whenWithdrawalBoundarySeeds]: settleWithdraw.t.sol#L443

[test_givenLiveGrant_whenUnadmittedCallerReusesContext_reverts]: ./settleWithdraw.t.sol#L57
