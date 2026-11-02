# BurnerLoansInventory.withdraw coverage plan

Source: [withdraw](../../../policies/burnerloans/BurnerLoansInventory.sol#L261). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-WITHDRAW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Provider role+enabled. Inputs amount,recipient. Use shared numerical/custody definitions.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-A01 | Former provider role revoked | Positive preserved claim | ROLES_RequireRole(providerRole) | Claim not confiscated; withdraw unavailable until governance restores role | Covered: [test_givenProviderRoleRevoked_preservesClaimAndReverts][test_givenProviderRoleRevoked_preservesClaimAndReverts] |
| BLINV-WITHDRAW-A02 | Fuzz callers excluding every BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Local enabled=true; amount=1 and amount=0 in separate calls | `ROLES_RequireRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE)` | No state/balance/event | Covered: [test_whenUnauthorizedCallerWithZeroOrOne_reverts][test_whenUnauthorizedCallerWithZeroOrOne_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-L01 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | false | Valid operation; also repeat with zero amount where the API accepts an amount | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_givenPausedInventory_whenZeroAmount_reverts][test_givenPausedInventory_whenZeroAmount_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-WITHDRAW-L02 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | true | Otherwise-valid operation; positive work | Success | Caller and aggregate claims and idle decrease by amount; exact OHM sent to recipient; OhmWithdrawn | Covered: [test_givenIdleClaim_withdrawsExactAmount][test_givenIdleClaim_withdrawsExactAmount] |
| BLINV-WITHDRAW-L03 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds], [test][test_givenInactiveDisabledInventory_whenZeroAmount_reverts] |
| BLINV-WITHDRAW-P03 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] |
| BLINV-WITHDRAW-L04 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Caller and aggregate claims and idle decrease by amount; exact OHM sent to recipient; OhmWithdrawn | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Invalid inputs

Fixed for this table: Accounting / events: Order exact; other provider claim cannot substitute.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-I01 | Provider | amount>0; recipient=0 | ZeroAddress() | Covered: [test_givenZeroRecipient_reverts][test_givenZeroRecipient_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Order exact; other provider claim cannot substitute.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-N01 | Provider | amount=0; recipient nonzero | ZeroAmount() | Covered: [test_givenZeroAmount_reverts][test_givenZeroAmount_reverts] |
| BLINV-WITHDRAW-N02 | Provider | claim<MAX128; fuzz amount claim+1..MAX128 | InsufficientClaim(amount,claim) | Covered: [test_givenClaim_whenAmountAboveClaim_reverts][test_givenClaim_whenAmountAboveClaim_reverts]; [test_whenWithdrawalBoundarySeeds][test_whenWithdrawalBoundarySeeds] |
| BLINV-WITHDRAW-N03 | Provider | Claim sufficient; J<MAX128; fuzz amount J+1..MAX128 | InsufficientIdle(amount,J) | Covered: [test_givenMaximumClaim_whenAmountAboveIdle_reverts][test_givenMaximumClaim_whenAmountAboveIdle_reverts]; [test_whenWithdrawalBoundarySeeds][test_whenWithdrawalBoundarySeeds] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-P01 | Provider | amount1..min(ownclaim,J); partial/full; provider=recipient vs distinct | Ownclaim/S/J decrease amount, recipient receives nominal amount | OhmWithdrawn; approval restore <=withdraw amount and desired gap | Covered: [test_givenIdleClaim_withdrawsExactAmount][test_givenIdleClaim_withdrawsExactAmount]; [test_givenFullIdleClaim_withdrawsAll][test_givenFullIdleClaim_withdrawsAll]; [test_givenClaim_whenWithdrawnToSelf][test_givenClaim_whenWithdrawnToSelf]; [test_whenWithdrawalBoundarySeeds][test_whenWithdrawalBoundarySeeds] |
| BLINV-WITHDRAW-P02 | Provider | External approval above desired target | Success | Reduce unsafe excess before completing withdrawal | Covered: [test_givenExternalOverApproval_reducesApprovalToDesired][test_givenExternalOverApproval_reducesApprovalToDesired] |

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-D01 | Provider | MINTR increase approval fails | Withdrawal succeeds; ApprovalRestorationFailed(amount,failureData) | Safe approval deficit remains; one exact outgoing transfer | Covered: [test_givenApprovalIncreaseFailure_whenWithdrawn_succeeds][test_givenApprovalIncreaseFailure_whenWithdrawn_succeeds] |
| BLINV-WITHDRAW-D02 | Provider | Outgoing OHM transfer returns false | SafeERC20FailedOperation(OHM) | All claim, idle, approval and balance changes roll back | Covered: [test_givenFalseTransfer_whenWithdrawn_reverts][test_givenFalseTransfer_whenWithdrawn_reverts] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `providerClaimOhm`, `suppliedOhm`, `suppliedIdleOhm`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-WITHDRAW-C01 | Inventory provider withdrawing its own claim | Inventory→provider-selected recipient OHM transfer | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Provider claim and idle backing fall once; recipient paid once; unrelated claims unchanged | Covered: [test_givenWithdrawCallback_whenRejectionCaught_succeeds][test_givenWithdrawCallback_whenRejectionCaught_succeeds] |
| BLINV-WITHDRAW-C02 | Inventory provider withdrawing its own claim | Inventory→provider-selected recipient OHM transfer | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenWithdrawCallback_whenRejectionPropagates_reverts][test_givenWithdrawCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenApprovalIncreaseFailure_whenWithdrawn_succeeds]: withdraw.t.sol#L352
[test_givenClaim_whenAmountAboveClaim_reverts]: withdraw.t.sol#L290
[test_givenClaim_whenWithdrawnToSelf]: withdraw.t.sol#L330
[test_givenExternalOverApproval_reducesApprovalToDesired]: withdraw.t.sol#L182
[test_givenFalseTransfer_whenWithdrawn_reverts]: withdraw.t.sol#L378
[test_givenFullIdleClaim_withdrawsAll]: withdraw.t.sol#L60
[test_givenIdleClaim_withdrawsExactAmount]: withdraw.t.sol#L35
[test_givenInactiveEnabledInventory_whenAction_reverts]: withdraw.t.sol#L200
[test_givenMaximumClaim_whenAmountAboveIdle_reverts]: withdraw.t.sol#L307
[test_givenPausedInventory_whenAction_reverts]: withdraw.t.sol#L219
[test_givenPausedInventory_whenZeroAmount_reverts]: withdraw.t.sol#L256
[test_givenProviderRoleRevoked_preservesClaimAndReverts]: withdraw.t.sol#L154
[test_givenReEnabledInventory_whenAction_succeeds]: withdraw.t.sol#L242
[test_givenWithdrawCallback_whenRejectionCaught_succeeds]: withdrawCallback.t.sol#L22
[test_givenWithdrawCallback_whenRejectionPropagates_reverts]: withdrawCallback.t.sol#L34
[test_givenZeroAmount_reverts]: withdraw.t.sol#L139
[test_givenZeroRecipient_reverts]: withdraw.t.sol#L146
[test_whenActionLifecycleSeeds]: withdraw.t.sol#L415
[test_whenUnauthorizedCallerWithZeroOrOne_reverts]: withdraw.t.sol#L277
[test_whenWithdrawalBoundarySeeds]: withdraw.t.sol#L395

[test_givenInactiveDisabledInventory_whenAction_reverts]: withdraw.t.sol#L230

[test_givenInactiveDisabledInventory_whenZeroAmount_reverts]: withdraw.t.sol#L266
