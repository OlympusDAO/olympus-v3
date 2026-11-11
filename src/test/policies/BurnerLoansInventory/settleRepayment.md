# BurnerLoansInventory.settleRepayment coverage plan

Source: [settleRepayment](../../../policies/burnerloans/BurnerLoansInventory.sol#L321). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-REPAYMENT` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only Core+enabled; OHM receipt arrives before this call. Inputs amount. Use shared numerical/custody definitions.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

Core spends the payer's allowance to Core and transfers OHM directly to Inventory before this call, within Core's settlement guard. Inventory authenticates that immutable Core and validates balance >= supplied idle + repayment before accounting. An Inventory pull from Core would require payer→Core→Inventory and an additional allowance; an Inventory pull from the payer would change the user's spender approval. No callback or forwarded payer authority is introduced.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

Fixed for this table: Accounting / events: No state/balance/event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-A01 | Fuzz callers excluding the immutable Core address | Local enabled=true; amount=1 and amount=0 in separate calls | `NotAuthorised()` | Covered: [test_whenUnauthorizedCallerWithZeroOrOne_reverts][test_whenUnauthorizedCallerWithZeroOrOne_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-L01 | Immutable Core | true | false | Valid operation; also repeat with zero amount where the API accepts an amount | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_givenPausedInventory_whenZeroAmount_reverts][test_givenPausedInventory_whenZeroAmount_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-REPAYMENT-L02 | Immutable Core | true | true | Otherwise-valid operation; positive work | Success | Principal decreases by amount; replenish supplied-claim deficit, burn excess; RepaymentSettled; provider claims unchanged | Covered: [test_givenClaimDeficit_retainsRepayment][test_givenClaimDeficit_retainsRepayment]; [test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn][test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn] |
| BLINV-REPAYMENT-L03 | Immutable Core | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds], [test][test_givenInactiveDisabledInventory_whenZeroAmount_reverts] |
| BLINV-REPAYMENT-P04 | Immutable Core | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] |
| BLINV-REPAYMENT-L04 | Immutable Core | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Principal decreases by amount; replenish supplied-claim deficit, burn excess; RepaymentSettled; provider claims unchanged | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-N01 | Core | amount=0 | ZeroAmount() | Balance validation precedes debt decrement; unchanged | Covered: [test_givenZeroAmount_reverts][test_givenZeroAmount_reverts] |
| BLINV-REPAYMENT-N02 | Core | OHM receipt sufficient; amount>P; fuzz P+1..MAX128 | ExcessivePrincipal(amount,P) | Balance validation precedes debt decrement; unchanged | Covered: [test_givenAmountAbovePrincipal_reverts][test_givenAmountAbovePrincipal_reverts]; [test_whenRepaymentBoundarySeeds][test_whenRepaymentBoundarySeeds] |
| BLINV-REPAYMENT-N03 | Core | amount below/equal/above S−J; amount<=P, seed boundaries | P decreases amount; retain=min(amount,S−J), burn rest | Provider claim S unchanged; J grows retained; RepaymentSettled reports actual burned | Covered: [test_givenClaimDeficit_retainsRepayment][test_givenClaimDeficit_retainsRepayment]; [test_givenClaimReplenished_burnsRepayment][test_givenClaimReplenished_burnsRepayment]; [test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn][test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn]; [test_givenMaximumPrincipal_whenRepaid][test_givenMaximumPrincipal_whenRepaid]; [test_whenRepaymentBoundarySeeds][test_whenRepaymentBoundarySeeds] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-P01 | Core | MINTR burn reverts; nonzero excess | Repayment succeeds; OhmBurnFailed(amount,failureData) | Excess remains surplus; principal/idle retained accounting committed | Covered: [test_givenBurnFailure_settlesAndLeavesSurplus][test_givenBurnFailure_settlesAndLeavesSurplus] |
| BLINV-REPAYMENT-P02 | Core | MINTR approval restoration increase reverts | Repayment succeeds; ApprovalRestorationFailed(amount,failureData) | Safe approval deficit; standalone sync can repair | Covered: [test_givenApprovalRestorationFailure_defersToAdminWithoutReverting][test_givenApprovalRestorationFailure_defersToAdminWithoutReverting] |
| BLINV-REPAYMENT-P03 | Core | Prior OHM donation; exact incoming repayment | Success | Donation remains surplus; do not reclassify as supplied idle | Covered: [test_givenDonation_whenRepaid_preservesSurplus][test_givenDonation_whenRepaid_preservesSurplus] |

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-D01 | Core | amount>0; OHM balance<J+amount | InsufficientBalance(J+amount,balance) | Balance validation precedes debt decrement; unchanged | Covered: [test_givenInsufficientReceivedBalance_reverts][test_givenInsufficientReceivedBalance_reverts] |
| BLINV-REPAYMENT-D02 | Core | Burn succeeds but approval reduction fails on external overapproval | Exact configured MINTR approval error despite burn | Entire repayment subtransaction restored | Covered: [test_givenBurnThenApprovalReductionFails_whenRepaid_reverts][test_givenBurnThenApprovalReductionFails_whenRepaid_reverts] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `activePrincipalOhm`, `suppliedIdleOhm`, `surplusOhm`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-REPAYMENT-C01 | Immutable Core | MINTR/OHM burn when repayment exceeds provider-claim deficit | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); burn completes | Principal falls once and retained idle funding is correct; burn/approval restoration occur once | Covered: [test_givenRepaymentBurnCallback_whenRejectionCaught_burns][test_givenRepaymentBurnCallback_whenRejectionCaught_burns] |
| BLINV-REPAYMENT-C02 | Immutable Core | MINTR/OHM burn when repayment exceeds provider-claim deficit | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Burn failure is caught by Inventory; repayment completes with OhmBurnFailed | Principal falls once and retained idle funding is correct; no burn or burn-restoration credit; retained claims and repayment principal remain correct; surplus recoverable | Covered: [test_givenRepaymentBurnCallback_whenRejectionPropagates_defersBurn][test_givenRepaymentBurnCallback_whenRejectionPropagates_defersBurn] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenAmountAbovePrincipal_reverts]: settleRepayment.t.sol#L147
[test_givenApprovalRestorationFailure_defersToAdminWithoutReverting]: settleRepayment.t.sol#L206
[test_givenBurnFailure_settlesAndLeavesSurplus]: settleRepayment.t.sol#L98
[test_givenBurnThenApprovalReductionFails_whenRepaid_reverts]: settleRepayment.t.sol#L347
[test_givenClaimDeficit_retainsRepayment]: settleRepayment.t.sol#L36
[test_givenClaimReplenished_burnsRepayment]: settleRepayment.t.sol#L54
[test_givenDonation_whenRepaid_preservesSurplus]: settleRepayment.t.sol#L336
[test_givenInactiveEnabledInventory_whenAction_reverts]: settleRepayment.t.sol#L246
[test_givenInsufficientReceivedBalance_reverts]: settleRepayment.t.sol#L174
[test_givenMaximumPrincipal_whenRepaid]: settleRepayment.t.sol#L366
[test_givenPausedInventory_whenAction_reverts]: settleRepayment.t.sol#L265
[test_givenPausedInventory_whenZeroAmount_reverts]: settleRepayment.t.sol#L302
[test_givenReEnabledInventory_whenAction_succeeds]: settleRepayment.t.sol#L288
[test_givenRepaymentBurnCallback_whenRejectionCaught_burns]: settleRepaymentCallback.t.sol#L22
[test_givenRepaymentBurnCallback_whenRejectionPropagates_defersBurn]: settleRepaymentCallback.t.sol#L45
[test_givenRepaymentCrossesClaimDeficit_splitsRetentionAndBurn]: settleRepayment.t.sol#L78
[test_givenZeroAmount_reverts]: settleRepayment.t.sol#L164
[test_whenActionLifecycleSeeds]: settleRepayment.t.sol#L413
[test_whenRepaymentBoundarySeeds]: settleRepayment.t.sol#L390
[test_whenUnauthorizedCallerWithZeroOrOne_reverts]: settleRepayment.t.sol#L323

[test_givenInactiveDisabledInventory_whenAction_reverts]: settleRepayment.t.sol#L276

[test_givenInactiveDisabledInventory_whenZeroAmount_reverts]: settleRepayment.t.sol#L312
