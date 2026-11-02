# BurnerLoansInventory.supply coverage plan

Source: [supply](../../../policies/burnerloans/BurnerLoansInventory.sol#L234). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-SUPPLY` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Provider role+enabled. Inputs amount. Numeric and custody requirements are specified below.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

## Authorization

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-SUPPLY-A01 | Fuzz all callers excluding provider role holders | Inventory enabled; caller lacks provider role | ROLES_RequireRole(BURNER_LOANS_INVENTORY_PROVIDER_ROLE) | Covered: [test_givenCallerWithoutProviderRole_reverts][test_givenCallerWithoutProviderRole_reverts] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-SUPPLY-L01 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | false | Positive amount with representable credit | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenPausedInventory_whenAction_reverts][test_givenPausedInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-SUPPLY-L02 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | false | amount=0 | NotEnabled() | Unchanged; pause wins over ZeroAmount | Covered: [test_givenPausedInventory_whenZeroAmount_reverts][test_givenPausedInventory_whenZeroAmount_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] |
| BLINV-SUPPLY-L03 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | true | Otherwise-valid operation; positive work | Success | Exact incoming OHM; caller claim, aggregate claim and idle increase by amount; OhmSupplied; unrelated claims unchanged | Covered: [test_givenProvider_updatesAccountingAndEmits][test_givenProvider_updatesAccountingAndEmits], [test][test_givenInactiveDisabledInventory_whenZeroAmount_reverts] |
| BLINV-SUPPLY-L04 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenAction_reverts][test_givenInactiveDisabledInventory_whenAction_reverts]; [test_whenActionLifecycleSeeds][test_whenActionLifecycleSeeds] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLINV-SUPPLY-P01 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenAction_reverts][test_givenInactiveEnabledInventory_whenAction_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLINV-SUPPLY-L05 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Exact incoming OHM; caller claim, aggregate claim and idle increase by amount; OhmSupplied; unrelated claims unchanged | Covered: [test_givenReEnabledInventory_whenAction_succeeds][test_givenReEnabledInventory_whenAction_succeeds] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-SUPPLY-N01 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | amount=0 | BurnerLoansInventory_ZeroAmount() | Unchanged; no committed logs | Covered: [test_givenZeroAmount_reverts][test_givenZeroAmount_reverts] |
| BLINV-SUPPLY-N02 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | amount fuzz1..MAX128; claim/idle/aggregate additions fit; seed1,MAX128 in empty fixture | Success | Exact payer→Inventory OHM; own claim/idle/aggregate increase amount; unrelated claims unchanged; OhmSupplied | Covered: [test_givenProvider_updatesAccountingAndEmits][test_givenProvider_updatesAccountingAndEmits]; [test_givenMultipleProviders_recordsSeparateClaims][test_givenMultipleProviders_recordsSeparateClaims]; [test_whenSupplyBoundarySeeds][test_whenSupplyBoundarySeeds] |
| BLINV-SUPPLY-N03 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Provider claim=MAX128; aggregate=idle=MAX128; amount=1 | SafeCastOverflowedUintDowncast(128, MAX128+1) | Unchanged; no committed logs | Covered: [test_givenMaximumProviderClaim_whenOneUnitSupplied_reverts][test_givenMaximumProviderClaim_whenOneUnitSupplied_reverts] |
| BLINV-SUPPLY-N04 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Another provider owns MAX128 claims, all idle; caller claim=0 and amount=1; caller addition fits | SafeCastOverflowedUintDowncast(128, MAX128+1) | Unchanged; no committed logs | Covered: [test_givenMaximumIdle_whenAnotherProviderSuppliesOne_reverts][test_givenMaximumIdle_whenAnotherProviderSuppliesOne_reverts] |
| BLINV-SUPPLY-N05 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Aggregate=MAX128; draw 1 so idle=MAX128-1; new caller claim=0 and amount=1; earlier additions fit | SafeCastOverflowedUintDowncast(128, MAX128+1) | Unchanged; no committed logs | Covered: [test_givenMaximumClaimsAndOneUnitDrawn_whenAnotherProviderSuppliesOne_reverts][test_givenMaximumClaimsAndOneUnitDrawn_whenAnotherProviderSuppliesOne_reverts] |

## Transfers and dependency failures

| ID | Caller | Transfer / dependency condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-SUPPLY-D01 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Caller allowance<amount; balance sufficient | Exact configured OHM allowance error | Unchanged; no committed logs | Covered: [test_givenMissingAllowance_reverts][test_givenMissingAllowance_reverts] |
| BLINV-SUPPLY-D02 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Caller balance<amount; allowance sufficient | Exact configured OHM balance error | Unchanged; no committed logs | Covered: [test_givenMissingBalance_reverts][test_givenMissingBalance_reverts] |
| BLINV-SUPPLY-D03 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Receipt delta<amount; donated old surplus present | SafeERC20Exact_InexactTransferFrom(OHM,Inventory,amount,received) | Unchanged; no committed logs | Covered: [test_givenExistingBalance_givenUnderDeliveredTransfer_reverts][test_givenExistingBalance_givenUnderDeliveredTransfer_reverts] |
| BLINV-SUPPLY-D04 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | Receipt delta>amount | SafeERC20Exact_InexactTransferFrom(OHM,Inventory,amount,received) | Unchanged; no committed logs | Covered: [test_givenOverDeliveredReceipt_whenSupplied_reverts][test_givenOverDeliveredReceipt_whenSupplied_reverts] |
| BLINV-SUPPLY-D05 | BURNER_LOANS_INVENTORY_PROVIDER_ROLE holder | MINTR approval reduction fails after exact incoming receipt | Exact configured MINTR error | Receipt, claims and approvals roll back | Covered: [test_givenApprovalReductionFailure_whenSupplied_reverts][test_givenApprovalReductionFailure_whenSupplied_reverts] |

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
| BLINV-SUPPLY-C01 | Inventory provider role holder | Provider→Inventory OHM transferFrom | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Provider claim, aggregate supplied and idle amounts rise once; exact receipt and mint approval reconcile | Covered: [test_givenSupplyCallback_whenRejectionCaught_succeeds][test_givenSupplyCallback_whenRejectionCaught_succeeds] |
| BLINV-SUPPLY-C02 | Inventory provider role holder | Provider→Inventory OHM transferFrom | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenSupplyCallback_whenRejectionPropagates_reverts][test_givenSupplyCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenApprovalReductionFailure_whenSupplied_reverts]: supply.t.sol#L236
[test_givenCallerWithoutProviderRole_reverts]: supply.t.sol#L70
[test_givenExistingBalance_givenUnderDeliveredTransfer_reverts]: supply.t.sol#L97
[test_givenInactiveEnabledInventory_whenAction_reverts]: supply.t.sol#L151
[test_givenMaximumClaimsAndOneUnitDrawn_whenAnotherProviderSuppliesOne_reverts]: supply.t.sol#L327
[test_givenMaximumIdle_whenAnotherProviderSuppliesOne_reverts]: supply.t.sol#L317
[test_givenMaximumProviderClaim_whenOneUnitSupplied_reverts]: supply.t.sol#L305
[test_givenMissingAllowance_reverts]: supply.t.sol#L78
[test_givenMissingBalance_reverts]: supply.t.sol#L87
[test_givenMultipleProviders_recordsSeparateClaims]: supply.t.sol#L131
[test_givenOverDeliveredReceipt_whenSupplied_reverts]: supplyCallback.t.sol#L48
[test_givenPausedInventory_whenAction_reverts]: supply.t.sol#L172
[test_givenPausedInventory_whenZeroAmount_reverts]: supply.t.sol#L215
[test_givenProvider_updatesAccountingAndEmits]: supply.t.sol#L35
[test_givenReEnabledInventory_whenAction_succeeds]: supply.t.sol#L199
[test_givenSupplyCallback_whenRejectionCaught_succeeds]: supplyCallback.t.sol#L24
[test_givenSupplyCallback_whenRejectionPropagates_reverts]: supplyCallback.t.sol#L37
[test_givenZeroAmount_reverts]: supply.t.sol#L53
[test_whenActionLifecycleSeeds]: supply.t.sol#L263
[test_whenSupplyBoundarySeeds]: supply.t.sol#L255

[test_givenInactiveDisabledInventory_whenAction_reverts]: supply.t.sol#L185

[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: supply.t.sol#L349

[test_givenInactiveDisabledInventory_whenZeroAmount_reverts]: supply.t.sol#L225
