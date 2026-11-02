# BurnerLoansInventory.burnSurplus coverage plan

Source: [burnSurplus](../../../policies/burnerloans/BurnerLoansInventory.sol#L391). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-BURN-SURPLUS` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN or the nonzero selected configurator; Inventory must be locally enabled. Inputs none. The configurator is the address stored on Inventory, without a reverse lifecycle check.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

This recovery function retries burning OHM left as surplus after settleRepayment catches a failed MINTR burn. It can also burn donated OHM. Supplied idle is excluded, so providers' backing is preserved. rescueSurplus instead transfers surplus to Treasury without reducing OHM total supply. burnSurplus does not restore a mint-approval deficit; syncMintApproval handles that separately.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

The recovery configurator is independent of BurnerLoansConfig. Governance selects the dedicated Inventory timelock directly on Inventory; replacing Core's Config does not change this authority.

## Authorization

Inventory active/enabled, cached ROLES/MINTR configured, 50e9 OHM supplied idle and 1e9 OHM surplus unless stated otherwise. The selected recovery configurator needs no ADMIN grant. Authorization is checked even when surplus is zero.

| ID | Caller | Authority / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-A01 | Fuzz caller excluding selected configurator and every ADMIN_ROLE holder | No grant; positive surplus | NotAuthorised() | Unchanged; no burn or event | Covered: [test_givenUnauthorizedCaller_reverts][test_givenUnauthorizedCaller_reverts] |
| BLINV-BURN-SURPLUS-A02 | Selected nonzero configurator without ADMIN_ROLE | Stored configurator equals caller | Success | Burn 1e9 once; SurplusBurned(1e9); provider backing/claims unchanged | Covered: [test_givenSelectedConfigWithoutAdmin_whenSurplusBurned_thenIdleRemainsBacked][test_givenSelectedConfigWithoutAdmin_whenSurplusBurned_thenIdleRemainsBacked] |
| BLINV-BURN-SURPLUS-A03 | Previous configurator without ADMIN_ROLE | ADMIN selected a different Inventory recovery configurator; surplus=0 | NotAuthorised() | Unchanged; no burn or event | Covered: [test_givenReplacedConfiguratorAndNoSurplus_whenBurned_reverts][test_givenReplacedConfiguratorAndNoSurplus_whenBurned_reverts] |
| BLINV-BURN-SURPLUS-A04 | Selected configurator also holding ADMIN_ROLE | Both authorization paths apply | Success | Exactly one burn and event, not two | Covered: [test_givenSelectedConfigWithAdmin_whenSurplusBurned_thenBurnedOnce][test_givenSelectedConfigWithAdmin_whenSurplusBurned_thenBurnedOnce] |

## Lifecycle

Kernel membership and local enablement vary independently. Cached ROLES and required modules are configured; no Inventory operation is already executing. Successful cases use the authorized caller shown and otherwise-valid inputs. Core lifecycle does not gate Inventory's independent funding/accounting service. Restore membership and retry an activity rejection without changing the position/claim inputs.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-L01 | ADMIN_ROLE holder | true | false | Surplus=1e9; supplied idle=50e9 | NotEnabled() | Unchanged; rejects before caller and body validation | Covered: [test_givenGloballyDisabled_reverts][test_givenGloballyDisabled_reverts] |
| BLINV-BURN-SURPLUS-L02 | ADMIN_ROLE holder | true | true | Otherwise-valid operation; positive work | Success | Positive surplus is burned through MINTR; SurplusBurned; provider idle, claims and principal unchanged | Covered: [test_givenIdle_whenSurplusBurned][test_givenIdle_whenSurplusBurned] |
| BLINV-BURN-SURPLUS-L03 | ADMIN_ROLE holder | false | false | Previously activated then deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; own activity precedes local pause, caller and inputs | Covered: [test_givenInactiveDisabledInventory_whenBurned_reverts][test_givenInactiveDisabledInventory_whenBurned_reverts] |
| BLINV-BURN-SURPLUS-P01 | ADMIN_ROLE holder | false | true | Previously activated then Kernel-deactivated; cached ROLES retained; valid operation | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no token/module writes or committed logs | Covered: [test_givenInactiveEnabledInventory_whenBurned_reverts][test_givenInactiveEnabledInventory_whenBurned_reverts] |
| BLINV-BURN-SURPLUS-L04 | ADMIN_ROLE holder | true | true | Disable then permitted reEnable within grace; restore readiness before invoking the action | Success | Positive surplus is burned through MINTR; SurplusBurned; provider idle, claims and principal unchanged | Covered: [test_givenReEnabledInventory_whenBurned][test_givenReEnabledInventory_whenBurned] |

## Surplus boundaries

Inventory active/enabled, ADMIN caller, configured MINTR. J is supplied idle OHM, S is provider claims and P is active principal. Each case preserves J/S/P. MINTR approval synchronization remains a separate operation.

| ID | Caller | OHM balance / surplus | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-D01 | ADMIN_ROLE holder | balance=J; include J=0 | No-op | No MINTR burn or SurplusBurned event; token supply unchanged | Covered: [test_givenEmptyInventory_whenBurned_noOp][test_givenEmptyInventory_whenBurned_noOp]; [test_givenFullyBackedIdle_whenBurned_noOp][test_givenFullyBackedIdle_whenBurned_noOp]; [test_whenBurnBoundarySeeds][test_whenBurnBoundarySeeds] |
| BLINV-BURN-SURPLUS-N01 | ADMIN_ROLE holder | balance<J; simulate token balance loss | No-op; surplusOhm returns zero | No underflow, burn or event; existing deficit is not repaired | Covered: [test_givenLostBacking_whenBurned_noOp][test_givenLostBacking_whenBurned_noOp]; [test_whenBurnBoundarySeeds][test_whenBurnBoundarySeeds] |
| BLINV-BURN-SURPLUS-N02 | ADMIN_ROLE holder | balance=J+1 | Burn exactly 1 raw OHM unit | Token supply -1; remaining balance J; SurplusBurned(1) | Covered: [test_givenIdle_whenSurplusBurned][test_givenIdle_whenSurplusBurned]; [test_whenBurnBoundarySeeds][test_whenBurnBoundarySeeds] |
| BLINV-BURN-SURPLUS-N03 | ADMIN_ROLE holder | Fuzz surplus 2..MAX256-J, with J<=MAX128; seed 2 and an interior positive amount | Burn exactly the surplus | Token supply decreases by surplus; remaining balance J; one SurplusBurned(surplus) | Covered: [test_givenIdle_whenSurplusBurned][test_givenIdle_whenSurplusBurned]; [test_whenBurnBoundarySeeds][test_whenBurnBoundarySeeds] |
| BLINV-BURN-SURPLUS-N04 | ADMIN_ROLE holder | balance=MAX256; J=50e9; token supply can represent the fixture | Burn MAX256-50e9 | Remaining balance and total supply 50e9; SurplusBurned(MAX256-50e9); provider claims unchanged | Covered: [test_givenIdle_whenSurplusBurned][test_givenIdle_whenSurplusBurned]; [test_whenBurnBoundarySeeds][test_whenBurnBoundarySeeds] |

## Failed repayment burn recovery

| ID | Caller | Prior operation | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-P02 | ADMIN_ROLE holder | Supply 50e9, borrow 100e9; repay all 100e9 while MINTR burn of 50e9 fails; then restore MINTR | Burn recovered surplus 50e9 | Provider idle and claim remain 50e9; principal zero; surplus zero; total supply -50e9; SurplusBurned(50e9) | Covered: [test_givenRepaymentBurnFailed_whenSurplusBurned_thenProviderIdleRemainsBacked][test_givenRepaymentBurnFailed_whenSurplusBurned_thenProviderIdleRemainsBacked] |

## Dependency failures

| ID | Caller | Dependency condition | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-D02 | ADMIN_ROLE holder | Positive surplus; MINTR burn fails | Exact configured MINTR burn error | Surplus and token supply unchanged; no event; unlike repayment this failure is strict | Covered: [test_givenBurnFailure_revertsAndPreservesSurplus][test_givenBurnFailure_revertsAndPreservesSurplus] |

## Shared assertions

Existing Inventory scenario/test formulas inform expectations; do not mirror production logic as the sole assertion. Guarantee boundary seeds and independent actual MINTR approval under/over desired states.

Co-located API assertions: `surplusOhm`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Transfer callbacks and reentrancy

Arm callbacks only after setup. Fund and authorize each nested route so it passes its public caller/input checks and reaches the named guard; a role or allowance failure is not reentrancy proof. Use one representative token-transfer callback, with nonzero pre-existing accounting and an unrelated entity. Read-only callbacks may observe intermediate state and must not be treated as final-accounting assertions. Keep caught and propagated outcomes as separate named tests.

| ID | Outer caller | Callback point | Authorized nested route / handling | Execution | Accounting / rollback | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-C01 | ADMIN_ROLE holder | MINTR/OHM burn of positive surplus | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Only true surplus burned once; idle backing, principal and claims unchanged | Covered: [test_givenBurnCallback_whenRejectionCaught_succeeds][test_givenBurnCallback_whenRejectionCaught_succeeds] |
| BLINV-BURN-SURPLUS-C02 | ADMIN_ROLE holder | MINTR/OHM burn of positive surplus | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenBurnCallback_whenRejectionPropagates_reverts][test_givenBurnCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

## Additional admission coverage

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLINV-BURN-SURPLUS-P03 | Unauthorized caller | Core settlement busy; fuzz own activity/enablement; empty surplus | ReentrancyGuardReentrantCall before own lifecycle, caller or no-op checks; accounting unchanged | Covered: [test][test_givenCoreBusy_whenUnauthorizedBurnsEmptySurplus_reverts] |

[test_givenBurnCallback_whenRejectionCaught_succeeds]: burnSurplusCallback.t.sol#L18
[test_givenBurnCallback_whenRejectionPropagates_reverts]: burnSurplusCallback.t.sol#L31
[test_givenBurnFailure_revertsAndPreservesSurplus]: burnSurplus.t.sol#L69
[test_givenEmptyInventory_whenBurned_noOp]: burnSurplus.t.sol#L140
[test_givenFullyBackedIdle_whenBurned_noOp]: burnSurplus.t.sol#L145
[test_givenGloballyDisabled_reverts]: burnSurplus.t.sol#L96
[test_givenIdle_whenSurplusBurned]: burnSurplus.t.sol#L109
[test_givenInactiveDisabledInventory_whenBurned_reverts]: burnSurplus.t.sol#L179
[test_givenInactiveEnabledInventory_whenBurned_reverts]: burnSurplus.t.sol#L164
[test_givenLostBacking_whenBurned_noOp]: burnSurplus.t.sol#L151
[test_givenReEnabledInventory_whenBurned]: burnSurplus.t.sol#L204
[test_givenRepaymentBurnFailed_whenSurplusBurned_thenProviderIdleRemainsBacked]: burnSurplusIntegration.t.sol#L30
[test_givenReplacedConfiguratorAndNoSurplus_whenBurned_reverts]: burnSurplus.t.sol#L218
[test_givenSelectedConfigWithAdmin_whenSurplusBurned_thenBurnedOnce]: burnSurplusIntegration.t.sol#L87
[test_givenSelectedConfigWithoutAdmin_whenSurplusBurned_thenIdleRemainsBacked]: burnSurplusIntegration.t.sol#L78
[test_givenUnauthorizedCaller_reverts]: burnSurplus.t.sol#L88
[test_whenBurnBoundarySeeds]: burnSurplus.t.sol#L229

[test_givenCoreBusy_whenUnauthorizedBurnsEmptySurplus_reverts]: burnSurplus.t.sol#L29
