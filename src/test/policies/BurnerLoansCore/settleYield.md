# BurnerLoansCore.settleYield coverage plan

Source: [settleYield](../../../policies/burnerloans/BurnerLoansCore.sol#L961). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-SETTLE-YIELD` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

Error ownership: local policy inactivity uses the component’s BurnerLoans_PolicyNotActive(BurnerLoansCore) error. `PolicyDependency_NotActive(component)` identifies an unavailable external dependency; no additional lifecycle gates are implied.

Required caller role: `BL_YIELD_CLAIMER_ROLE`. Inputs: asset, requested:uint256, recipient:address selected by trusted YieldClaimerTask from Custody.yieldRecipient(). Admission is specified in the function-local matrix below. Callers in body rows satisfy every admission condition. Public action numeric/economic restrictions belong to the corresponding action plan.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Body inputs are otherwise valid. Admission order: Core activity, Core enablement, required operation role. Core’s guard runs before these checks. Every rejection leaves balances, approvals and module/accounting state unchanged.

## Authorization

Fixed for this table: Local active: true; Local enabled: true.

| ID | Caller | Required role held | Execution | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-A01 | BL_YIELD_CLAIMER_ROLE holder | true | Body executes | Covered: [test][test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer] |
| BLCORE-SETTLE-YIELD-A02 | Fuzz EOA/contracts excluding every BL_YIELD_CLAIMER_ROLE holder | false | ROLES_RequireRole(BL_YIELD_CLAIMER_ROLE) | Covered: [test][test_whenCallerLacksSettlementRole_reverts] |
| BLCORE-SETTLE-YIELD-A03 | Policy holding only sibling operation role | false | ROLES_RequireRole(BL_YIELD_CLAIMER_ROLE) | Covered: [test][test_givenOnlySiblingRole_whenSettled_reverts] |
| BLCORE-SETTLE-YIELD-A04 | Role-holding policy reporting another Kernel | true | Body executes; no caller Kernel or membership query | Covered: [test][test_givenWrongKernelCaller_whenSettled] |

## Lifecycle

Fixed for this table: Required role held: true.

| ID | Caller | Local active | Local enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-L01 | BL_YIELD_CLAIMER_ROLE holder | true | false | NotEnabled() | Covered: [test][test_givenCoreDisabled_whenSettled_reverts] |
| BLCORE-SETTLE-YIELD-L02 | BL_YIELD_CLAIMER_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-YIELD-L03 | BL_YIELD_CLAIMER_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Covered: [test][test_givenCoreInactive_whenSettled_reverts] |
| BLCORE-SETTLE-YIELD-D01 | Inactive role-holding policy | true | true | Body executes; caller Kernel membership is irrelevant | Covered: [test][test_givenCallerInactive_whenSettled] |
| BLCORE-SETTLE-YIELD-D02 | Role-holding EOA | true | true | Body executes; no contract code or identity metadata required | Covered: [test][test_givenRoleHoldingEOA_whenSettled] |

The operation role is the sole caller admission requirement. Caller Kernel membership, reported Kernel, contract code, local enablement and `core()` binding are not inspected. EOAs and contracts holding the role reach the body with otherwise-valid inputs. Governance revokes the role to remove settlement authority. Core retains its own lifecycle and settlement guard; public actions enforce their own lifecycle and actual-caller grants.

For each admission rejection, add an invalid action input to prove guard precedence. An authorized nested settlement or guarded lifecycle/pointer mutation rejects `ReentrancyGuardReentrantCall()`. Separate caught callbacks (one outer operation) from propagated failures (rollback). Dependency getter failures propagate their exact configured error. Read-only callbacks are not final-accounting evidence.

## Settlement authorization

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-A05 | BL_YIELD_CLAIMER_ROLE holder | Core lacks DM deposit-operator role | ROLES_RequireRole(DEPOSIT_OPERATOR_ROLE) | Covered: [test][test_givenNoOperatorRole_whenYieldSettled_reverts] |

## Dependency lifecycle

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-D03 | BL_YIELD_CLAIMER_ROLE holder | DepositManager locally disabled | NotEnabled() | Covered: [test][test_givenDepositManagerPaused_whenYieldSettled_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-I01 | BL_YIELD_CLAIMER_ROLE holder | Asset unregistered | BurnerLoansCore_AssetNotConfigured(asset) | Unchanged; no committed logs | Covered: [test][test_givenUnregisteredAsset_whenYieldSettled_reverts] |
| BLCORE-SETTLE-YIELD-I02 | BL_YIELD_CLAIMER_ROLE holder | recipient=0 | DepositManager_ZeroAddress() | Unchanged; no committed logs | Covered: [test][test_givenZeroRecipient_whenYieldSettled_reverts] |
| BLCORE-SETTLE-YIELD-I03 | BL_YIELD_CLAIMER_ROLE holder | recipient=DepositManager | DepositManager_InvalidRecipient(recipient) | Unchanged; no committed logs | Covered: [test][test_givenCustodianRecipient_whenYieldSettled_reverts] |
| BLCORE-SETTLE-YIELD-I04 | BL_YIELD_CLAIMER_ROLE holder | requested=0 | AssetManager_ZeroAmount() | Unchanged; no committed logs | Covered: [test][test_givenZeroAmount_whenYieldSettled_reverts] |
| BLCORE-SETTLE-YIELD-I05 | BL_YIELD_CLAIMER_ROLE holder | Actual output=0 | Return output token and zero | No Core YieldClaimed event; no Custody obligation | Covered: [test][test_givenSubShareYield_whenSettled] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-P01 | BL_YIELD_CLAIMER_ROLE holder | Post-withdrawal custody insolvent | DepositManager_Insolvent(asset,liabilities,heldAssets,borrowed) | Unchanged; no committed logs | Covered: [test][test_givenInsolventWithdrawal_whenYieldSettled_reverts] |
| BLCORE-SETTLE-YIELD-P02 | BL_YIELD_CLAIMER_ROLE holder | Actual output>0 | Return actual token/output | DM directly pays recipient; Core YieldClaimed; no deferred yield | Covered: [test][test_givenIndependentDependencyOutput_whenSettled], [test][test_givenActualVaultYield_whenSettled] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-D04 | BL_YIELD_CLAIMER_ROLE holder | Recipient transfer fails | Exact configured token error | Covered: [test][test_givenYieldDeliveryFailure_whenSettled_reverts] |

## Shared assertions

Assert actual custody and module aggregates; seed every numeric input at zero, one and its type maximum, with separate success/rejection partitions determined by the dependency. Use exact FLOAN/DepositManager errors from their source. Every token callback attempts a fully authorized nested Core route: caught guard failure allows exactly one settlement; propagated failure restores the complete pre-call graph. Dependency events have their actual emitting contracts. There is no Core callback into the action.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-SETTLE-YIELD-C01 | Selected same-Kernel active action with the matching settlement role | DM/vault redemption and direct output delivery to Treasury or RevenueDistributor; no Custody yield balance | Otherwise-valid authorized public action reaching guarded Core settlement; callback catches the guard rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Claim delivers once to current yield route; no new Custody pending-yield obligation; collateral liabilities unchanged | Covered: [test][test_givenVaultCallback_whenCaught] |
| BLCORE-SETTLE-YIELD-C02 | Selected same-Kernel active action with the matching settlement role | DM/vault redemption and direct output delivery to Treasury or RevenueDistributor; no Custody yield balance | Otherwise-valid authorized public action reaching guarded Core settlement; token propagates the guard rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test][test_givenVaultCallback_whenPropagated] |

[test_givenActualVaultYield_whenSettled]: settleYield.t.sol#L240
[test_givenAdmittedAction_whenLocalPauseAndCoreBindingDiffer]: settleYield.t.sol#L116
[test_givenCallerInactive_whenSettled]: settleYield.t.sol#L103
[test_givenCoreDisabled_whenSettled_reverts]: settleYield.t.sol#L78
[test_givenCoreInactive_whenSettled_reverts]: settleYield.t.sol#L88
[test_givenCustodianRecipient_whenYieldSettled_reverts]: settleYield.t.sol#L185
[test_givenDepositManagerPaused_whenYieldSettled_reverts]: settleYield.t.sol#L150
[test_givenIndependentDependencyOutput_whenSettled]: settleYield.t.sol#L208
[test_givenInsolventWithdrawal_whenYieldSettled_reverts]: settleYield.t.sol#L278
[test_givenNoOperatorRole_whenYieldSettled_reverts]: settleYield.t.sol#L138
[test_givenOnlySiblingRole_whenSettled_reverts]: settleYield.t.sol#L53
[test_givenRoleHoldingEOA_whenSettled]: settleYield.t.sol#L109
[test_givenSubShareYield_whenSettled]: settleYield.t.sol#L260
[test_givenUnregisteredAsset_whenYieldSettled_reverts]: settleYield.t.sol#L160
[test_givenVaultCallback_whenCaught]: settleYield.t.sol#L317
[test_givenVaultCallback_whenPropagated]: settleYield.t.sol#L349
[test_givenWrongKernelCaller_whenSettled]: settleYield.t.sol#L64
[test_givenYieldDeliveryFailure_whenSettled_reverts]: settleYield.t.sol#L300
[test_givenZeroAmount_whenYieldSettled_reverts]: settleYield.t.sol#L199
[test_givenZeroRecipient_whenYieldSettled_reverts]: settleYield.t.sol#L174
[test_whenCallerLacksSettlementRole_reverts]: settleYield.t.sol#L41
