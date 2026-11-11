# BurnerLoansInventory.setGlobalDebtCap coverage plan

Source: [setGlobalDebtCap](../../../policies/burnerloans/BurnerLoansInventory.sol#L185).

## Domains and notation

Scenario scope: `BLINV-GLOBAL-CAP`. ADMIN_ROLE updates the uint128 OHM cap directly on Inventory. This is not routed through BurnerLoansConfig or either timelock; being the recovery configurator alone grants no cap authority. Inventory must be active and enabled; Core settlement must be idle, but Core lifecycle does not gate the update. Guard order: local reentrancy, Core.requireNotReentrant, own activity, enabled state, ADMIN role, cap floor, then equality. An unchanged valid cap still synchronizes approval but emits no cap-change event. If approval already matches the target, synchronization performs no MINTR write. Let C=old cap, P=active principal, J=supplied idle, S=provider claims. Desired MINTR approval=max(newCap-P-J,0), with widened arithmetic. Changing the cap does not mint/burn/transfer OHM or change P/J/S.

Unchanged includes the cap/controller, provider claims and idle, principal, OHM balances/supply, MINTR approval, Core/FLOAN positions and committed logs. `MAXn=2**n-1`.

## Authorization

Inventory active/enabled and idle, cap valid and changed.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-A08 | ADMIN_ROLE holder | Direct governance caller | Success | Set cap and reconcile MINTR; GlobalDebtCapSet(newCap) | Covered: [test_givenAdmin_setsCapAndApproval][test_givenAdmin_setsCapAndApproval] |
| BLINV-GLOBAL-CAP-A01 | Fuzz caller excluding all ADMIN_ROLE holders | Seed Core, BurnerLoansConfig, Inventory timelock and BL-admin-only | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_givenUnauthorizedCaller_reverts][test_givenUnauthorizedCaller_reverts] |
| BLINV-GLOBAL-CAP-A02 | Selected recovery configurator without ADMIN | Pointer alone grants no cap authority | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_givenRecoveryConfigurator_whenGlobalDebtCapSet_reverts][test_givenRecoveryConfigurator_whenGlobalDebtCapSet_reverts] |

## Local lifecycle

Caller ADMIN, Core guard idle; cap>=P and different from old cap, except paused equality seed.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-L06 | ADMIN_ROLE holder | true | true | Success | Cap/approval update; GlobalDebtCapSet; P/J/S unchanged | Covered: [test_givenAdmin_setsCapAndApproval][test_givenAdmin_setsCapAndApproval] |
| BLINV-GLOBAL-CAP-A05 | ADMIN_ROLE holder | true | false | NotEnabled(), including unchanged cap | Unchanged | Covered: [test_givenGloballyDisabled_whenAdminSetsCap_reverts][test_givenGloballyDisabled_whenAdminSetsCap_reverts] |
| BLINV-GLOBAL-CAP-P04 | ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Inventory) | Unchanged | Covered: [test_givenInactiveEnabledInventory_whenAdminSetsCap_reverts][test_givenInactiveEnabledInventory_whenAdminSetsCap_reverts] |
| BLINV-GLOBAL-CAP-L09 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansInventory) before local enablement, roles and inputs | Unchanged | Covered: [test_givenInactiveDisabledInventory_whenAdminSetsCap_reverts][test_givenInactiveDisabledInventory_whenAdminSetsCap_reverts] |

## Core lifecycle independence

Inventory active/enabled, ADMIN caller, idle Core guard. No upstream controller lifecycle/API checks.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-L01 | ADMIN_ROLE holder | true | true | Success | Cap/approval only | Covered: [test_givenCoreLifecycle_whenCapSet][test_givenCoreLifecycle_whenCapSet]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-GLOBAL-CAP-L02 | ADMIN_ROLE holder | true | false | Success | Cap/approval only | Covered: [test_givenCoreLifecycle_whenCapSet][test_givenCoreLifecycle_whenCapSet]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-GLOBAL-CAP-L03 | ADMIN_ROLE holder | false | true | Success | Cap/approval only | Covered: [test_givenCoreLifecycle_whenCapSet][test_givenCoreLifecycle_whenCapSet]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-GLOBAL-CAP-L04 | ADMIN_ROLE holder | false | false | Success | Cap/approval only | Covered: [test_givenCoreLifecycle_whenCapSet][test_givenCoreLifecycle_whenCapSet]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |

## Input bounds

Caller ADMIN; other admission passes. Changing-value cases exclude current cap.

| ID | Caller | New cap / fixed state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-N01 | ADMIN_ROLE holder | P>0; fuzz cap in 0..P-1; seed 0,P-1 | BurnerLoansInventory_InvalidCap(cap,P) | Unchanged | Covered: [test_givenPrincipal_whenInvalidCap_reverts][test_givenPrincipal_whenInvalidCap_reverts]; [test_whenCapBoundarySeeds][test_whenCapBoundarySeeds] |
| BLINV-GLOBAL-CAP-N02 | ADMIN_ROLE holder | P<MAX128; fuzz cap in P+1..MAX128; seed P+1,MAX128 | Success | Exact desired approval and GlobalDebtCapSet | Covered: [test_givenPrincipal_whenValidCapSet][test_givenPrincipal_whenValidCapSet]; [test_whenCapBoundarySeeds][test_whenCapBoundarySeeds] |
| BLINV-GLOBAL-CAP-P01 | ADMIN_ROLE holder | newCap=P, distinct from C | Success at exact principal floor | Desired approval0; existing provider idle and claims retained | Covered: [test_givenProviderIdle_whenExactPrincipalCapSet][test_givenProviderIdle_whenExactPrincipalCapSet] |
| BLINV-GLOBAL-CAP-N03 | ADMIN_ROLE holder | P=0; newCap=0, old C>0 | Success | Cap0; desired approval0 | Covered: [test_givenZeroCap_succeeds][test_givenZeroCap_succeeds] |
| BLINV-GLOBAL-CAP-N04 | ADMIN_ROLE holder | P=0,J=0; newCap=1, old C>1 | Success | Cap1 and approval1; no OHM mint | Covered: [test_givenCoreLifecycle_whenCapSet][test_givenCoreLifecycle_whenCapSet]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-GLOBAL-CAP-P02 | ADMIN_ROLE holder | newCap=currentCap, including 0/MAX128; actual approval differs from desired | Synchronize approval after admission and cap floor | Exact desired approval; no cap event or provider/token changes | Covered: [test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized][test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized], [test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized][test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized], [test_givenSameCapWithPrincipalIdleAndDonation_whenSet_thenApprovalSynchronized][test_givenSameCapWithPrincipalIdleAndDonation_whenSet_thenApprovalSynchronized]; [test_whenCapBoundarySeeds][test_whenCapBoundarySeeds] |
| BLINV-GLOBAL-CAP-P09 | ADMIN_ROLE holder | newCap=currentCap; approval already equals desired | No writes after checking live approval | No MINTR mutation, cap event or accounting changes | Covered: [test_givenSameCapAndApprovalAligned_whenSet_thenNoWrites][test_givenSameCapAndApprovalAligned_whenSet_thenNoWrites] |
| BLINV-GLOBAL-CAP-P10 | ADMIN_ROLE holder | newCap=currentCap; approval too low/high; matching MINTR reconciliation reverts | ApprovalChangeFailed() | Cap, approval, balances and provider accounting unchanged | Covered: [test_givenSameCapAndApprovalSyncFails_whenSet_reverts][test_givenSameCapAndApprovalSyncFails_whenSet_reverts] |

## Accounting and controller independence

Fixed values use 9-decimal OHM. Independent expectations come from the stated cap, principal and idle, never the Inventory getter under test.

| ID | Caller | Fixture / transition | Expected outcome | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-P03 | ADMIN_ROLE holder | P=20e9,J=150e9,S=150e9; lower cap from 200e9 to 120e9 | Desired approval0; available capacity100e9 | Do not burn/remove provider idle when J exceeds remaining cap room | Covered: [test_givenIdleExceedsRoom_whenCapLowered][test_givenIdleExceedsRoom_whenCapLowered] |
| BLINV-GLOBAL-CAP-P06 | ADMIN_ROLE holder | P=20e9,J=50e9,S=50e9,donated surplus30e9; newCap120e9 | Desired approval50e9; capacity100e9 | Donation excluded from supplied idle; P/J/S/surplus unchanged | Covered: [test_givenDonationAndIdle_whenCapLowered][test_givenDonationAndIdle_whenCapLowered] |
| BLINV-GLOBAL-CAP-D03 | ADMIN_ROLE holder | BurnerLoansConfig replaced independently of recovery controller | Direct cap update still succeeds | No Config/controller getter or authority synchronization | Covered: [test_givenCoreControllerReplaced_whenCapUpdated_thenInventoryAuthorityIndependent][test_givenCoreControllerReplaced_whenCapUpdated_thenInventoryAuthorityIndependent] |

## MINTR failures

Caller ADMIN and changed valid cap. Faults are strict.

| ID | Caller | Dependency fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-D01 | ADMIN_ROLE holder | Required increaseMintApproval fails with ApprovalChangeFailed() | Exact ApprovalChangeFailed() | Cap and approval roll back; no event | Covered: [test_givenIncreaseFailure_revertsAndRollsBack][test_givenIncreaseFailure_revertsAndRollsBack] |
| BLINV-GLOBAL-CAP-D02 | ADMIN_ROLE holder | Required decreaseMintApproval fails with ApprovalChangeFailed() | Exact ApprovalChangeFailed() | Cap and approval roll back; no event | Covered: [test_givenDecreaseFailure_revertsAndRollsBack][test_givenDecreaseFailure_revertsAndRollsBack] |

## Reentrancy

Authorized ADMIN callback; no Config forwarding is involved.

| ID | Caller | Boundary | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-GLOBAL-CAP-A06 | ADMIN_ROLE holder | Core fee-receipt callback before Inventory local settlement guard | ReentrancyGuardReentrantCall() from Core guard | No cap or approval change | Covered: [test_givenFeeReceiptCallback_whenCapRejectionCaught_succeeds][test_givenFeeReceiptCallback_whenCapRejectionCaught_succeeds]; [test_givenFeeReceiptCallback_whenCapRejectionPropagates_reverts][test_givenFeeReceiptCallback_whenCapRejectionPropagates_reverts] |
| BLINV-GLOBAL-CAP-C01 | ADMIN_ROLE holder | Nested setter while Inventory local guard entered | ReentrancyGuardReentrantCall() | No nested cap write; propagate failure to verify full rollback | Covered: [test_givenCapCallback_whenRejectionCaught_succeeds][test_givenCapCallback_whenRejectionCaught_succeeds]; [test_givenCapCallback_whenRejectionPropagates_reverts][test_givenCapCallback_whenRejectionPropagates_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenAdmin_setsCapAndApproval]: setGlobalDebtCapIntegration.t.sol#L39
[test_givenCapCallback_whenRejectionCaught_succeeds]: setGlobalDebtCapCallback.t.sol#L22
[test_givenCapCallback_whenRejectionPropagates_reverts]: setGlobalDebtCapCallback.t.sol#L38
[test_givenCoreControllerReplaced_whenCapUpdated_thenInventoryAuthorityIndependent]: setGlobalDebtCapIntegration.t.sol#L214
[test_givenCoreLifecycle_whenCapSet]: setGlobalDebtCap.t.sol#L223
[test_givenDecreaseFailure_revertsAndRollsBack]: setGlobalDebtCapIntegration.t.sol#L136
[test_givenDonationAndIdle_whenCapLowered]: setGlobalDebtCap.t.sol#L205
[test_givenFeeReceiptCallback_whenCapRejectionCaught_succeeds]: setGlobalDebtCapIntegration.t.sol#L232
[test_givenFeeReceiptCallback_whenCapRejectionPropagates_reverts]: setGlobalDebtCapIntegration.t.sol#L245
[test_givenGloballyDisabled_whenAdminSetsCap_reverts]: setGlobalDebtCapIntegration.t.sol#L161
[test_givenIdleExceedsRoom_whenCapLowered]: setGlobalDebtCap.t.sol#L192
[test_givenInactiveDisabledInventory_whenAdminSetsCap_reverts]: setGlobalDebtCapIntegration.t.sol#L174
[test_givenInactiveEnabledInventory_whenAdminSetsCap_reverts]: setGlobalDebtCapIntegration.t.sol#L182
[test_givenIncreaseFailure_revertsAndRollsBack]: setGlobalDebtCapIntegration.t.sol#L119
[test_givenPrincipal_whenInvalidCap_reverts]: setGlobalDebtCap.t.sol#L30
[test_givenPrincipal_whenValidCapSet]: setGlobalDebtCap.t.sol#L48
[test_givenProviderIdle_whenExactPrincipalCapSet]: setGlobalDebtCap.t.sol#L257
[test_givenRecoveryConfigurator_whenGlobalDebtCapSet_reverts]: setGlobalDebtCapIntegration.t.sol#L207
[test_givenSameCapAndExcessApproval_whenSet_thenApprovalSynchronized]: setGlobalDebtCap.t.sol#L64
[test_givenUnauthorizedCaller_reverts]: setGlobalDebtCapIntegration.t.sol#L153
[test_givenZeroCap_succeeds]: setGlobalDebtCapIntegration.t.sol#L69
[test_whenCapBoundarySeeds]: setGlobalDebtCap.t.sol#L233
[test_whenCoreLifecycleSeeds]: setGlobalDebtCap.t.sol#L271

[test_givenSameCapAndInsufficientApproval_whenSet_thenApprovalSynchronized]: ./setGlobalDebtCap.t.sol#L87

[test_givenSameCapAndApprovalAligned_whenSet_thenNoWrites]: ./setGlobalDebtCap.t.sol#L136

[test_givenSameCapAndApprovalSyncFails_whenSet_reverts]: ./setGlobalDebtCap.t.sol#L158

[test_givenSameCapWithPrincipalIdleAndDonation_whenSet_thenApprovalSynchronized]: ./setGlobalDebtCap.t.sol#L110
