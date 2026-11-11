# BurnerLoansInventory.rescueSurplus coverage plan

Source: [rescueSurplus](../../../policies/burnerloans/BurnerLoansInventory.sol#L405). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-RESCUE-SURPLUS` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN or the nonzero selected configurator. Recovery is available while locally disabled; Kernel activity is still required. Inputs none. The configurator is Inventory's stored controller, not the controller's external delegated operator.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Accounting and interaction setup

OHM state in uint128: cap C, active principal P, supplied claims S, supplied idle J, claims per provider. Desired MINTR approval=max(C−P−J,0) using widened sum. Available capacity=min(C−P,J+actual mint approval); donated surplus does not become supplied idle. Preserve S=sum provider claims, J<=S, P<=C and OHM balance>=J. Default never reduces provider claim. Burn/approval restoration failure can leave recoverable surplus/approval deficit.

Numeric input seed0,1,MAX128 plus exact principal/cap/claim/idle/deficit/desired limits and neighbors. Address equalities include provider=recipient, distinct recipient, zero recipient and recipient=Inventory; derive actual outgoing behavior, no invented self-recipient ban. Callbacks through MINTR or token must attempt an authorized nested Inventory mutation; caught/propagated outcomes differ. A Core guard also covers Inventory callbacks during Core settlement. Unrelated providers/assets/Core loan state remains unchanged on standalone funding operations.

The recovery configurator is independent of BurnerLoansConfig. Governance selects the dedicated Inventory timelock directly on Inventory; replacing Core's Config does not change this authority.

## Authorization

Inventory active with cached ROLES/TRSRY. Local enabled=true except the explicitly paused recovery-configurator case. Hold 50e9 OHM provider idle/claims and 1e9 surplus. The selected recovery configurator needs no ADMIN grant; its own lifecycle is an upstream concern. Own activity precedes authorization and zero-surplus returns.

| ID | Caller | Authority / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-RESCUE-SURPLUS-A01 | Fuzz caller excluding selected configurator and every ADMIN_ROLE holder | No grant | NotAuthorised() | Unchanged; no transfer or event | Covered: [test_whenCallerIsNeitherConfigNorAdmin_reverts][test_whenCallerIsNeitherConfigNorAdmin_reverts] |
| BLINV-RESCUE-SURPLUS-A02 | Selected nonzero configurator without ADMIN_ROLE | Stored configurator equals caller | Success | Transfer 1e9 to cached TRSRY; SurplusRescued(1e9); provider backing and claims unchanged | Covered: [test_givenSelectedConfigWithoutAdmin_whenSurplusRescued_thenIdleRemainsBacked][test_givenSelectedConfigWithoutAdmin_whenSurplusRescued_thenIdleRemainsBacked] |
| BLINV-RESCUE-SURPLUS-A03 | Selected nonzero configurator without ADMIN_ROLE | Inventory locally disabled | Success | Same recovery; Inventory remains disabled | Covered: [test_givenDisabledInventory_whenSelectedConfigRescues_thenIdleRemainsBacked][test_givenDisabledInventory_whenSelectedConfigRescues_thenIdleRemainsBacked] |
| BLINV-RESCUE-SURPLUS-A04 | Selected configurator also holding ADMIN_ROLE | Both authorization paths apply | Success | Exactly one transfer and event, not two | Covered: [test_givenSelectedConfigWithAdmin_whenSurplusRescued_thenTransferredOnce][test_givenSelectedConfigWithAdmin_whenSurplusRescued_thenTransferredOnce] |
| BLINV-RESCUE-SURPLUS-A05 | Previous configurator without ADMIN_ROLE | ADMIN selected a different Inventory recovery configurator | NotAuthorised() | Unchanged; no transfer or event | Covered: [test_givenConfiguratorReplaced_whenPreviousConfigRescues_reverts][test_givenConfiguratorReplaced_whenPreviousConfigRescues_reverts] |
| BLINV-RESCUE-SURPLUS-A06 | Zero address without ADMIN_ROLE | Stored configurator cleared to zero | NotAuthorised() | Zero disables delegated authority; no transfer or event | Covered: [test_givenConfiguratorCleared_whenZeroAddressRescues_reverts][test_givenConfiguratorCleared_whenZeroAddressRescues_reverts] |

## Lifecycle

Use ADMIN for this table; authorization is established above. Inventory previously activated with cached ROLES/TRSRY, provider idle/claims=50e9 and surplus=1e9. Core lifecycle does not gate Inventory recovery. Local enablement is not a rescue prerequisite; Kernel activity remains required.

| ID | Caller | Local active | Local enabled | History / inputs | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-RESCUE-SURPLUS-L01 | ADMIN_ROLE holder | true | false | Locally disabled after activation | Success | Transfer 1e9 surplus to TRSRY; one SurplusRescued(1e9); remain disabled; idle/claims/principal unchanged | Covered: [test_givenActiveDisabledInventory_whenSurplusRescued_thenIdleRemainsBacked][test_givenActiveDisabledInventory_whenSurplusRescued_thenIdleRemainsBacked] |
| BLINV-RESCUE-SURPLUS-L02 | ADMIN_ROLE holder | true | true | No lifecycle transition before rescue | Success | Transfer 1e9 surplus to TRSRY; one SurplusRescued(1e9); idle/claims/principal unchanged | Covered: [test_givenActiveEnabledInventory_whenSurplusRescued_thenIdleRemainsBacked][test_givenActiveEnabledInventory_whenSurplusRescued_thenIdleRemainsBacked] |
| BLINV-RESCUE-SURPLUS-L03 | ADMIN_ROLE holder | false | false | Disabled then Kernel-deactivated; cached ROLES retained | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no transfer or committed event | Covered: [test_givenInactiveDisabledInventory_whenSurplusRescued_reverts][test_givenInactiveDisabledInventory_whenSurplusRescued_reverts] |
| BLINV-RESCUE-SURPLUS-P02 | ADMIN_ROLE holder | false | true | Kernel-deactivated while locally enabled | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no transfer or committed event | Covered: [test_givenInactiveEnabledInventory_whenSurplusRescued_reverts][test_givenInactiveEnabledInventory_whenSurplusRescued_reverts] |
| BLINV-RESCUE-SURPLUS-L04 | ADMIN_ROLE holder | true | true | Disable then permitted reEnable within grace | Success | Transfer 1e9 surplus to TRSRY; one SurplusRescued(1e9); idle/claims/principal unchanged | Covered: [test_givenReEnabledInventory_whenSurplusRescued][test_givenReEnabledInventory_whenSurplusRescued] |

## Surplus boundaries and execution

ADMIN caller, Inventory active/enabled and cached modules configured. Provider claims, idle and principal remain unchanged. No approval or mint/burn operation is performed.

| ID | Caller | Balance / module state | Execution | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-RESCUE-SURPLUS-D01 | ADMIN_ROLE holder | OHM balance equals supplied idle J, including J=0 | No-op | No transfer or SurplusRescued event | Covered: [test_givenEmptyInventory_whenRescued_noOp][test_givenEmptyInventory_whenRescued_noOp]; [test_givenFullyBackedIdle_whenRescued_noOp][test_givenFullyBackedIdle_whenRescued_noOp]; [test_whenRescueBoundarySeeds][test_whenRescueBoundarySeeds] |
| BLINV-RESCUE-SURPLUS-N01 | ADMIN_ROLE holder | OHM balance below supplied idle J; simulate token balance loss | No-op; surplusOhm returns zero | No underflow or transfer; existing deficit is not repaired | Covered: [test_givenLostBacking_whenRescued_noOp][test_givenLostBacking_whenRescued_noOp]; [test_whenRescueBoundarySeeds][test_whenRescueBoundarySeeds] |
| BLINV-RESCUE-SURPLUS-N02 | ADMIN_ROLE holder | OHM balance J+1 | Transfer exactly 1 to cached TRSRY | Remaining balance J; SurplusRescued(1) | Covered: [test_givenIdle_whenSurplusRescued][test_givenIdle_whenSurplusRescued]; [test_whenRescueBoundarySeeds][test_whenRescueBoundarySeeds] |
| BLINV-RESCUE-SURPLUS-N03 | ADMIN_ROLE holder | Fuzz positive surplus in 1..MAX256-J; seed 1 and MAX256-J | Transfer the entire surplus to cached TRSRY | Remaining balance J; SurplusRescued(surplus) | Covered: [test_givenIdle_whenSurplusRescued][test_givenIdle_whenSurplusRescued]; [test_whenRescueBoundarySeeds][test_whenRescueBoundarySeeds] |
| BLINV-RESCUE-SURPLUS-P01 | ADMIN_ROLE holder | TRSRY upgraded and dependencies refreshed; positive surplus | Transfer to the new TRSRY | Old TRSRY unchanged; one rescue event | Covered: [test_givenTreasuryUpgrade_whenSurplusRescued][test_givenTreasuryUpgrade_whenSurplusRescued] |

## Transfer failures

| ID | Caller | Failure | Execution | Rollback | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-RESCUE-SURPLUS-D02 | ADMIN_ROLE holder | Positive surplus; outgoing OHM transfer fails | Exact configured token error | Inventory/TRSRY balances, claims, idle and principal unchanged; no committed rescue event | Covered: [test_givenTransferFailure_revertsWithoutChangingSurplus][test_givenTransferFailure_revertsWithoutChangingSurplus] |

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
| BLINV-RESCUE-SURPLUS-C01 | ADMIN_ROLE holder | Inventory→Treasury OHM surplus transfer; Inventory | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback catches nested rejection | Nested call rejects ReentrancyGuardReentrantCall(); outer operation succeeds | Only surplus transferred once; provider reserves preserved | Covered: [test_givenRescueCallback_whenRejectionCaught_succeeds][test_givenRescueCallback_whenRejectionCaught_succeeds] |
| BLINV-RESCUE-SURPLUS-C02 | ADMIN_ROLE holder | Inventory→Treasury OHM surplus transfer; Inventory | Nested Inventory money-moving operation with its required Core/provider/ADMIN authority reaching Inventory local guard; callback propagates nested rejection | Exact propagated token/dependency error rejects outer operation | Full pre-call rollback of affected positions, debt, claims, token/receipt balances, allowances, reserves, indexes, approvals and committed logs, including earlier subcalls | Covered: [test_givenRescueCallback_whenRejectionPropagates_reverts][test_givenRescueCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

## Activity precedence

| ID | Caller | Pre-state | Expected behavior | Test |
| --- | --- | --- | --- | --- |
| BLINV-RESCUE-SURPLUS-L05 | Unauthorized caller | Inventory inactive; fuzz local enablement | BurnerLoans_PolicyNotActive(Inventory) before caller and no-op checks | Covered: [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |

[test_givenActiveDisabledInventory_whenSurplusRescued_thenIdleRemainsBacked]: rescueSurplusIntegration.t.sol#L49
[test_givenActiveEnabledInventory_whenSurplusRescued_thenIdleRemainsBacked]: rescueSurplusIntegration.t.sol#L44
[test_givenConfiguratorCleared_whenZeroAddressRescues_reverts]: rescueSurplusIntegration.t.sol#L114
[test_givenConfiguratorReplaced_whenPreviousConfigRescues_reverts]: rescueSurplusIntegration.t.sol#L106
[test_givenDisabledInventory_whenSelectedConfigRescues_thenIdleRemainsBacked]: rescueSurplusIntegration.t.sol#L82
[test_givenEmptyInventory_whenRescued_noOp]: rescueSurplus.t.sol#L75
[test_givenFullyBackedIdle_whenRescued_noOp]: rescueSurplus.t.sol#L80
[test_givenIdle_whenSurplusRescued]: rescueSurplus.t.sol#L45
[test_givenInactiveDisabledInventory_whenSurplusRescued_reverts]: rescueSurplusIntegration.t.sol#L56
[test_givenInactiveEnabledInventory_whenSurplusRescued_reverts]: rescueSurplusIntegration.t.sol#L64
[test_givenLostBacking_whenRescued_noOp]: rescueSurplus.t.sol#L86
[test_givenReEnabledInventory_whenSurplusRescued]: rescueSurplus.t.sol#L108
[test_givenRescueCallback_whenRejectionCaught_succeeds]: rescueSurplusCallback.t.sol#L18
[test_givenRescueCallback_whenRejectionPropagates_reverts]: rescueSurplusCallback.t.sol#L31
[test_givenSelectedConfigWithAdmin_whenSurplusRescued_thenTransferredOnce]: rescueSurplusIntegration.t.sol#L89
[test_givenSelectedConfigWithoutAdmin_whenSurplusRescued_thenIdleRemainsBacked]: rescueSurplusIntegration.t.sol#L71
[test_givenTransferFailure_revertsWithoutChangingSurplus]: rescueSurplusIntegration.t.sol#L150
[test_givenTreasuryUpgrade_whenSurplusRescued]: rescueSurplus.t.sol#L94
[test_whenCallerIsNeitherConfigNorAdmin_reverts]: rescueSurplusIntegration.t.sol#L95
[test_whenRescueBoundarySeeds]: rescueSurplus.t.sol#L123
[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: rescueSurplus.t.sol#L23
