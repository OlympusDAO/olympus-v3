# BurnerLoansInventory.draw coverage plan

Source: [draw](../../../policies/burnerloans/BurnerLoansInventory.sol#L290). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-DRAW` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Only Core+enabled. Inputs amount,recipient. Numeric and custody requirements are specified below.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

Fixed for this table: Accounting / events: No state/balance/event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-DRAW-A01 | Fuzz callers excluding the immutable Core address | Local enabled=true; amount=1 and amount=0 in separate calls | `NotAuthorised()` | Covered: [test_whenUnauthorizedCallerWithZeroOrOne_reverts][test_whenUnauthorizedCallerWithZeroOrOne_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-DRAW-L01 | Immutable Core | true | false | Valid operation; also repeat with zero amount where the API accepts an amount | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_givenPausedInventory_whenZeroAmount_reverts][test_givenPausedInventory_whenZeroAmount_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-DRAW-L02 | Immutable Core | true | true | Otherwise-valid operation; positive work | Success | Principal increases by amount; supplied idle funds first, mint the remainder; recipient receives exact OHM; OhmDrawn | Covered: [test_givenMixedFunding_drawsExactAmount][test_givenMixedFunding_drawsExactAmount] |
| BLINV-DRAW-L03 | Immutable Core | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds], [test][test_givenInactiveDisabledInventory_whenZeroAmount_reverts] |
| BLINV-DRAW-P01 | Immutable Core | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] |
| BLINV-DRAW-L04 | Immutable Core | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Principal increases by amount; supplied idle funds first, mint the remainder; recipient receives exact OHM; OhmDrawn | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-DRAW-N01 | Core | amount=0; recipient nonzero | ZeroAmount() | Unchanged | Covered: [test_givenZeroAmount_reverts][test_givenZeroAmount_reverts] |
| BLINV-DRAW-N02 | Core | amount=1; recipient=0 | ZeroAddress() | Unchanged | Covered: [test_givenZeroRecipient_reverts][test_givenZeroRecipient_reverts] |
| BLINV-DRAW-N03 | Core | availableCapacity<MAX128; fuzz amount capacity+1..MAX128; seed both endpoints | InsufficientCapacity(amount,capacity) | Unchanged | Covered: [test_givenAmountAboveCapacity_reverts][test_givenAmountAboveCapacity_reverts]; [test_whenDrawBoundarySeeds][test_whenDrawBoundarySeeds] |
| BLINV-DRAW-N04 | Core | amount1..capacity; J below/equal/above amount; exact capacity; MAX128 constructible | P+amount; supplied=min(amount,J), minted=amount−supplied | Idle first, mint remainder only; transfer full amount; OhmDrawn exact split | Covered: [test_givenMixedFunding_drawsExactAmount][test_givenMixedFunding_drawsExactAmount]; [test_givenMintFunding_drawsExactAmount][test_givenMintFunding_drawsExactAmount]; [test_givenIdleFunding_drawsExactAmount][test_givenIdleFunding_drawsExactAmount]; [test_givenMaximumCap_whenDrawn][test_givenMaximumCap_whenDrawn]; [test_whenDrawBoundarySeeds][test_whenDrawBoundarySeeds] |
| BLINV-DRAW-N05 | Core | Externally set MINTR approval MAX256 but cap small | Draw still cap bounded | No cap bypass | Covered: [test_givenMaximumExternalOverApproval_drawRemainsCapBounded][test_givenMaximumExternalOverApproval_drawRemainsCapBounded] |

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-DRAW-D01 | Immutable Core | Minted portion>0; MINTR mint fails | Exact configured MINTR error | Unchanged; no committed logs | Covered: [test_givenMintFailure_revertsAndRollsBack][test_givenMintFailure_revertsAndRollsBack] |
| BLINV-DRAW-D02 | Immutable Core | Mint succeeded; final OHM transfer fails | Exact configured token error | Principal/idle/mint supply/approvals roll back | Covered: [test_givenTransferFailure_revertsAndRollsBack][test_givenTransferFailure_revertsAndRollsBack] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `activePrincipalOhm`, `availableCapacity`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-DRAW-C01 | Immutable Core | MINTR mint and Inventory→recipient OHM transfer; independently arm each | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Principal rises once; idle versus minted split and approvals agree | Covered: [test_givenDrawMintCallback_whenRejectionCaught_succeeds][test_givenDrawMintCallback_whenRejectionCaught_succeeds]; [test_givenDrawTransferCallback_whenRejectionCaught_succeeds][test_givenDrawTransferCallback_whenRejectionCaught_succeeds] |
| BLINV-DRAW-C02 | Immutable Core | MINTR mint and Inventory→recipient OHM transfer; independently arm each | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenDrawMintCallback_whenRejectionPropagates_reverts][test_givenDrawMintCallback_whenRejectionPropagates_reverts]; [test_givenDrawTransferCallback_whenRejectionPropagates_reverts][test_givenDrawTransferCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenAmountAboveCapacity_reverts]: draw.t.sol#L163
[test_givenDrawMintCallback_whenRejectionCaught_succeeds]: drawCallback.t.sol#L19
[test_givenDrawMintCallback_whenRejectionPropagates_reverts]: drawCallback.t.sol#L33
[test_givenDrawTransferCallback_whenRejectionCaught_succeeds]: drawCallback.t.sol#L43
[test_givenDrawTransferCallback_whenRejectionPropagates_reverts]: drawCallback.t.sol#L56
[test_givenIdleFunding_drawsExactAmount]: draw.t.sol#L64
[test_givenInactiveEnabledInventory_whenAction_reverts]: draw.t.sol#L222
[test_givenMaximumCap_whenDrawn]: draw.t.sol#L308
[test_givenMaximumExternalOverApproval_drawRemainsCapBounded]: draw.t.sol#L133
[test_givenMintFailure_revertsAndRollsBack]: draw.t.sol#L82
[test_givenMintFunding_drawsExactAmount]: draw.t.sol#L55
[test_givenMixedFunding_drawsExactAmount]: draw.t.sol#L41
[test_givenPausedInventory_whenAction_reverts]: draw.t.sol#L240
[test_givenPausedInventory_whenZeroAmount_reverts]: draw.t.sol#L274
[test_givenReEnabledInventory_whenAction_succeeds]: draw.t.sol#L261
[test_givenTransferFailure_revertsAndRollsBack]: draw.t.sol#L102
[test_givenZeroAmount_reverts]: draw.t.sol#L190
[test_givenZeroRecipient_reverts]: draw.t.sol#L199
[test_whenActionLifecycleSeeds]: draw.t.sol#L361
[test_whenDrawBoundarySeeds]: draw.t.sol#L343
[test_whenUnauthorizedCallerWithZeroOrOne_reverts]: draw.t.sol#L295

[test_givenInactiveDisabledInventory_whenAction_reverts]: draw.t.sol#L250

[test_givenInactiveDisabledInventory_whenZeroAmount_reverts]: draw.t.sol#L284
