# BurnerLoansInventory.settleDefault coverage plan

Source: [settleDefault](../../../policies/burnerloans/BurnerLoansInventory.sol#L357). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-DEFAULT` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only Core+enabled. Inputs amount. Numeric and custody requirements are specified below.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

Fixed for this table: Accounting / events: No state/balance/event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-DEFAULT-A01 | Fuzz callers excluding the immutable Core address | Local enabled=true; amount=1 and amount=0 in separate calls | `NotAuthorised()` | Covered: [test_whenUnauthorizedCallerWithZeroOrOne_reverts][test_whenUnauthorizedCallerWithZeroOrOne_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-DEFAULT-L01 | Immutable Core | true | false | Valid operation; also repeat with zero amount where the API accepts an amount | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_givenPausedInventory_whenZeroAmount_reverts][test_givenPausedInventory_whenZeroAmount_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-DEFAULT-L02 | Immutable Core | true | true | Otherwise-valid operation; positive work | Success | Principal decreases by amount; supplied idle and provider claims unchanged; bounded mint approval restoration; PrincipalDefaulted | Covered: [test_givenPartialDefault_preservesClaim][test_givenPartialDefault_preservesClaim] |
| BLINV-DEFAULT-L03 | Immutable Core | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds], [test][test_givenInactiveDisabledInventory_whenZeroAmount_reverts] |
| BLINV-DEFAULT-P03 | Immutable Core | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] |
| BLINV-DEFAULT-L04 | Immutable Core | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Principal decreases by amount; supplied idle and provider claims unchanged; bounded mint approval restoration; PrincipalDefaulted | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-DEFAULT-N01 | Core | amount=0 | ZeroAmount() | Unchanged | Covered: [test_givenZeroAmount_reverts][test_givenZeroAmount_reverts] |
| BLINV-DEFAULT-N02 | Core | P<MAX128; fuzz amount P+1..MAX128; seed P+1,MAX128 | ExcessivePrincipal(amount,P) | Unchanged | Covered: [test_givenAmountAbovePrincipal_reverts][test_givenAmountAbovePrincipal_reverts]; [test_whenDefaultBoundarySeeds][test_whenDefaultBoundarySeeds] |
| BLINV-DEFAULT-N03 | Core | amount1..P, partial/full including MAX128 | P decreases amount | Provider claims and idle/balances untouched; PrincipalDefaulted; restore approval bounded by amount/gap | Covered: [test_givenPartialDefault_preservesClaim][test_givenPartialDefault_preservesClaim]; [test_givenFullDefault_clearsPrincipalAndPreservesClaim][test_givenFullDefault_clearsPrincipalAndPreservesClaim]; [test_givenMaximumPrincipal_whenDefaulted][test_givenMaximumPrincipal_whenDefaulted]; [test_whenDefaultBoundarySeeds][test_whenDefaultBoundarySeeds] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-DEFAULT-P01 | Immutable Core | Restoration increase fails; no excess approval | Success | Default principal decrement/event committed; approval deficit recoverable | Covered: [test_givenApprovalRestorationFailure_defersToAdminWithoutReverting][test_givenApprovalRestorationFailure_defersToAdminWithoutReverting] |
| BLINV-DEFAULT-P02 | Core | Default→later surviving-loan repayment→provider withdrawal | Claim remains and can replenish from later repayment | Conservation across sequence; no immediate provider writeoff | Covered: [test_givenDefaultThenLaterRepayment_replenishesSurvivingClaim][test_givenDefaultThenLaterRepayment_replenishesSurvivingClaim] |

## Transfers and dependency failures

Fixed for this table: Accounting / events: Default accounting/event roll back.

| ID | Caller | Transfer / dependency condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-DEFAULT-D01 | Immutable Core | Excess approval reduction fails | Exact configured MINTR error | Covered: [test_givenExcessApprovalReductionFails_whenDefaulted_reverts][test_givenExcessApprovalReductionFails_whenDefaulted_reverts] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `activePrincipalOhm`, `desiredMintApproval`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenAmountAbovePrincipal_reverts]: settleDefault.t.sol#L109
[test_givenApprovalRestorationFailure_defersToAdminWithoutReverting]: settleDefault.t.sol#L134
[test_givenDefaultThenLaterRepayment_replenishesSurvivingClaim]: settleDefault.t.sol#L53
[test_givenExcessApprovalReductionFails_whenDefaulted_reverts]: settleDefault.t.sol#L260
[test_givenFullDefault_clearsPrincipalAndPreservesClaim]: settleDefault.t.sol#L41
[test_givenInactiveEnabledInventory_whenAction_reverts]: settleDefault.t.sol#L174
[test_givenMaximumPrincipal_whenDefaulted]: settleDefault.t.sol#L278
[test_givenPartialDefault_preservesClaim]: settleDefault.t.sol#L29
[test_givenPausedInventory_whenAction_reverts]: settleDefault.t.sol#L192
[test_givenPausedInventory_whenZeroAmount_reverts]: settleDefault.t.sol#L226
[test_givenReEnabledInventory_whenAction_succeeds]: settleDefault.t.sol#L213
[test_givenZeroAmount_reverts]: settleDefault.t.sol#L99
[test_whenActionLifecycleSeeds]: settleDefault.t.sol#L308
[test_whenDefaultBoundarySeeds]: settleDefault.t.sol#L298
[test_whenUnauthorizedCallerWithZeroOrOne_reverts]: settleDefault.t.sol#L247

[test_givenInactiveDisabledInventory_whenAction_reverts]: settleDefault.t.sol#L202

[test_givenInactiveDisabledInventory_whenZeroAmount_reverts]: settleDefault.t.sol#L236
