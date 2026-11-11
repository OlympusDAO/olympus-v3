// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansDebtReEnableTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBT-REENABLE-L03.
    function test_givenInactive_whenReEnabled_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _setPolicyState(_debt, false, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            )
        );
        vm.prank(caller_);
        _debt.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-P01, BLDEBT-REENABLE-P02.
    function test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, type(uint48).max - grace_));
        now_ = uint48(bound(now_, last_, uint256(last_) + grace_));
        vm.assume(caller_ != address(0));
        _grantRoleIfMissing(blAdmin_ ? BURNER_LOANS_ADMIN_ROLE : ADMIN_ROLE, caller_);
        if (overlap_) _grantRoleIfMissing(blAdmin_ ? ADMIN_ROLE : BURNER_LOANS_ADMIN_ROLE, caller_);
        vm.warp(last_);
        _debt.setGracePeriod(grace_);
        _debt.disable("");
        vm.warp(now_);
        vm.expectEmit(address(_debt));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_debt));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        _debt.reEnable();
        assertTrue(_debt.isEnabled(), "Permitted re-enable succeeds");
        assertEq(_debt.lastTransitionAt(), now_, "Re-enable records exact time");
        assertEq(_debt.gracePeriod(), grace_, "Grace preserved");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-P02.
    function test_givenExistingFixtureAdmin_whenReEnabled() public {
        test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
            3284,
            392188,
            31536001,
            address(this),
            true,
            true
        );
    }

    // Scenarios: BLDEBT-REENABLE-P02.
    function test_givenMaximumDeadline_whenAtDeadline_thenReEnableSucceeds() public {
        test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
            type(uint48).max - 1,
            1,
            type(uint48).max,
            address(0xabc),
            true,
            false
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-P03.
    function test_givenExpiredGrace_whenReEnabled_reverts(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, type(uint48).max - grace_ - 1));
        uint48 deadline = last_ + grace_;
        now_ = uint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.warp(last_);
        _debt.setGracePeriod(grace_);
        _debt.disable("");
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _debt.reEnable();
        assertFalse(_debt.isEnabled(), "Expired grace leaves disabled");
        assertEq(_debt.lastTransitionAt(), last_, "Expired grace preserves timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-N01.
    function test_givenGraceDeadlineOverflow_whenReEnabled_reverts(
        uint32 grace_,
        uint48 last_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max));
        vm.warp(last_);
        _debt.setGracePeriod(grace_);
        _debt.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last_) + grace_
            )
        );
        vm.prank(caller_);
        _debt.reEnable();
        assertFalse(_debt.isEnabled(), "Overflow cannot re-enable");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-A01.
    function test_givenDisabled_whenUnauthorizedReEnables_reverts(address caller_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _debt.disable("");
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _debt.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-L01.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(
        address caller_,
        bool active_
    ) public {
        _setPolicyState(_debt, active_, true);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _debt.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-N01.
    function test_givenGraceOverflowEndpoints_whenReEnabled_thenTypedOverflow() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenGraceDeadlineOverflow_whenReEnabled_reverts(
            1,
            type(uint48).max,
            address(0xabc1),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore enabled subject between overflow seeds");
        test_givenGraceDeadlineOverflow_whenReEnabled_reverts(
            type(uint32).max,
            type(uint48).max,
            address(0xabc2),
            true,
            false
        );
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-A02.
    function test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins(
        address caller_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _debt.disable("");
        _core.disable("");
        vm.warp(uint256(_debt.lastTransitionAt()) + _debt.gracePeriod() + 1);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _debt.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-D01.
    function test_givenCoreDisabled_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _core.disable("");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _core.enable("");
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-REENABLE-D03.
    function test_givenCoreInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        _core.enable("");
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-REENABLE-D02.
    function test_givenCoreInactive_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_core));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_core));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-REENABLE-D04.
    function test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(0x1234)
            )
        );
        vm.prank(caller_);
        _debt.reEnable();
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBT-REENABLE-D06, BLDEBT-REENABLE-D08.
    function test_givenInventoryDisabled_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _inventory.disable("");
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _inventory.enable("");
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-REENABLE-D07, BLDEBT-REENABLE-D08.
    function test_givenInventoryInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _inventory.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_inventory));
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        _inventory.enable("");
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    // Scenarios: BLDEBT-REENABLE-D05, BLDEBT-REENABLE-D08.
    function test_givenInventoryInactive_whenReEnabled_thenRejectAndRetry(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_inventory));
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _debt.lastTransitionAt();
        _expectDependencyNotActive(address(_inventory));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
        _kernel.executeAction(Actions.ActivatePolicy, address(_inventory));
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationSucceeded();
    }

    function test_givenInventoryKernelChanged_whenReEnabled_reverts() public {
        _debt.disable("");
        Kernel other = new Kernel();
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(other)
            )
        );
        _debt.reEnable();
    }

    // Scenarios: BLDEBT-REENABLE-L04.
    function test_givenSettlementRoleRevoked_whenReEnabled_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _debt.disable("");
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_debt));
        uint48 last = _debt.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, _SETTLEMENT_ROLE)
        );
        vm.prank(caller_);
        _debt.reEnable();
        _assertActivationRejected(last);
    }

    // Scenarios: BLDEBT-REENABLE-L02, BLDEBT-REENABLE-L05.
    function test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansDebt fresh = new BurnerLoansDebt(_kernel, _core);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLDEBT-REENABLE-D01.
    function test_givenEachPermittedRole_givenCoreDisabled_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCoreDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenCoreDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenCoreDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-D02.
    function test_givenEachPermittedRole_givenCoreInactive_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCoreInactive_whenReEnabled_thenRejectAndRetry(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenCoreInactive_whenReEnabled_thenRejectAndRetry(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenCoreInactive_whenReEnabled_thenRejectAndRetry(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-D03.
    function test_givenEachPermittedRole_givenCoreInactiveAndDisabled_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCoreInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc1),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenCoreInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc2),
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenCoreInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLDEBT-REENABLE-D06, BLDEBT-REENABLE-D08.
    function test_givenEachPermittedRole_givenInventoryDisabled_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenInventoryDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenInventoryDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenInventoryDisabled_whenReEnabled_thenRejectAndRetry(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-D05, BLDEBT-REENABLE-D08.
    function test_givenEachPermittedRole_givenInventoryInactive_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenInventoryInactive_whenReEnabled_thenRejectAndRetry(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenInventoryInactive_whenReEnabled_thenRejectAndRetry(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenInventoryInactive_whenReEnabled_thenRejectAndRetry(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-D07, BLDEBT-REENABLE-D08.
    function test_givenEachPermittedRole_givenInventoryInactiveAndDisabled_whenReEnabled_thenRejectAndRetry()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenInventoryInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc1),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenInventoryInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc2),
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenInventoryInactiveAndDisabled_whenReEnabled_thenRejectAndRetry(
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLDEBT-REENABLE-D04.
    function test_givenEachPermittedRole_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
            address(0xabc1),
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
            address(0xabc2),
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLDEBT-REENABLE-L04.
    function test_givenEachPermittedRole_givenSettlementRoleRevoked_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenSettlementRoleRevoked_whenReEnabled_reverts(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenSettlementRoleRevoked_whenReEnabled_reverts(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenSettlementRoleRevoked_whenReEnabled_reverts(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-L03.
    function test_givenEachPermittedRole_givenInactive_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenInactive_whenReEnabled_reverts(address(0xabc1), false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for borrower-loans admin");
        test_givenInactive_whenReEnabled_reverts(address(0xabc2), true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore lifecycle for overlapping roles");
        test_givenInactive_whenReEnabled_reverts(address(0xabc3), false, true);
    }

    // Scenarios: BLDEBT-REENABLE-P01, BLDEBT-REENABLE-P02.
    function test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            address caller = address(uint160(0xabc1 + role));
            test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
                1,
                2,
                1,
                caller,
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore at last transition boundary");
            test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
                1,
                2,
                2,
                caller,
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore at one before deadline");
            test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
                type(uint48).max - 1,
                1,
                type(uint48).max,
                caller,
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore maximum inclusive deadline");
        }
    }

    // Scenarios: BLDEBT-REENABLE-P03.
    function test_givenEachPermittedRole_whenExpiredGraceEndpoints_thenExactError() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            address caller = address(uint160(0xabc1 + role));
            test_givenExpiredGrace_whenReEnabled_reverts(1, 1, 3, caller, role == 1, role == 2);
            assertTrue(vm.revertToState(checkpoint), "Restore first expired timestamp");
            test_givenExpiredGrace_whenReEnabled_reverts(
                1,
                1,
                type(uint48).max,
                caller,
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore maximum expired timestamp");
        }
    }

    // Scenarios: BLDEBT-REENABLE-N01.
    function test_givenEachPermittedRole_whenGraceOverflows_thenExactTypedError() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenGraceDeadlineOverflow_whenReEnabled_reverts(
                type(uint32).max,
                type(uint48).max,
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore overflowing deadline for next role");
        }
    }

    // Scenarios: BLDEBT-REENABLE-P01, BLDEBT-REENABLE-P02.
    function test_givenExistingAdmin_whenReEnabled_thenExactTransition() public {
        test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
            281474976710654,
            3334,
            1,
            address(this),
            false,
            true
        );
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast)
