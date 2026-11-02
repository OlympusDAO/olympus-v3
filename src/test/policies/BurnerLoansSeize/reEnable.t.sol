// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
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
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {PolicyAdmin} from "src/policies/utils/PolicyAdmin.sol";
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansSeizeReEnableTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-REENABLE-L03.
    function test_givenInactive_whenReEnabled_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _setPolicyState(_liquidation, false, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_liquidation)
            )
        );
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-P01, BLLIQ-REENABLE-P02.
    function test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition(
        uint48 last_,
        uint32 grace_,
        uint48 now_,
        address caller_,
        bool blAdmin_,
        bool overlap_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertEnabled();
        assertEq(_liquidation.gracePeriod(), bound(grace_, 1, type(uint32).max), "Grace preserved");
    }

    // Scenarios: BLLIQ-REENABLE-P03.
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
        _liquidation.setGracePeriod(grace_);
        _liquidation.disable("");
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        _liquidation.reEnable();
        assertFalse(_liquidation.isEnabled(), "Expired grace leaves disabled");
        assertEq(_liquidation.lastTransitionAt(), last_, "Expired grace preserves timestamp");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-N01.
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
        _liquidation.setGracePeriod(grace_);
        _liquidation.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                48,
                uint256(last_) + grace_
            )
        );
        vm.prank(caller_);
        _liquidation.reEnable();
        assertFalse(_liquidation.isEnabled(), "Overflow cannot re-enable");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-A01.
    function test_givenDisabled_whenUnauthorizedReEnables_reverts(address caller_) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _liquidation.disable("");
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-L01.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(
        address caller_,
        bool active_,
        bool zeroHistory_
    ) public {
        _setEnabledHistory(zeroHistory_);
        _mockUnavailableCoreViews();
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_liquidation));
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-A02.
    function test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins(
        address caller_
    ) public {
        vm.assume(
            !_roles.hasRole(caller_, ADMIN_ROLE) &&
                !_roles.hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
        _liquidation.disable("");
        _core.disable("");
        vm.warp(uint256(_liquidation.lastTransitionAt()) + _liquidation.gracePeriod() + 1);
        vm.expectRevert(PolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-D04.
    function test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
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
        _liquidation.reEnable();
        vm.clearMockedCalls();
        _assertLoansPreserved();
    }

    function test_givenInventoryKernelChanged_whenReEnabled_reverts() public {
        _liquidation.disable("");
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
        _liquidation.reEnable();
    }

    // Scenarios: BLLIQ-REENABLE-L04.
    function test_givenSettlementRoleRevoked_whenReEnabled_reverts(
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _rolesAdmin.revokeRole(_SETTLEMENT_ROLE, address(_liquidation));
        uint48 last = _liquidation.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, _SETTLEMENT_ROLE)
        );
        vm.prank(caller_);
        _liquidation.reEnable();
        assertFalse(_liquidation.isEnabled(), "Missing settlement authority blocks activation");
        assertEq(_liquidation.lastTransitionAt(), last, "Failed activation preserves history");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-L02, BLLIQ-REENABLE-L05.
    function test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence(
        address caller_
    ) public {
        BurnerLoansSeize fresh = new BurnerLoansSeize(_kernel, _core);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Fresh action remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Rejected transition cannot initialize history");
    }

    // Scenarios: BLLIQ-REENABLE-P01, BLLIQ-REENABLE-P02.
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

    // Scenarios: BLLIQ-REENABLE-P03.
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

    // Scenarios: BLLIQ-REENABLE-N01.
    function test_givenEachPermittedRole_whenGraceOverflows_thenExactTypedError() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenGraceDeadlineOverflow_whenReEnabled_reverts(
                1,
                type(uint48).max,
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2
            );
            assertTrue(vm.revertToState(checkpoint), "Restore minimum-grace overflow seed");
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

    // Scenarios: BLLIQ-REENABLE-L01.
    function test_givenZeroTransitionHistory_whenAlreadyEnabled_thenStateWins() public {
        test_givenEnabled_whenAnyCallerReEnables_reverts(address(0), true, true);
    }

    // Scenarios: BLLIQ-REENABLE-L03.
    function test_givenEachPermittedRole_givenInactive_whenReEnabled_reverts() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenInactive_whenReEnabled_reverts(
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2,
                1,
                2,
                2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore same prerequisite for each permitted role"
            );
        }
    }

    // Scenarios: BLLIQ-REENABLE-D04.
    function test_givenEachPermittedRole_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch()
        public
    {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch(
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2,
                1,
                2,
                2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore same prerequisite for each permitted role"
            );
        }
    }

    // Scenarios: BLLIQ-REENABLE-L04.
    function test_givenEachPermittedRole_givenSettlementRoleRevoked_whenReEnabled_reverts() public {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenSettlementRoleRevoked_whenReEnabled_reverts(
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2,
                1,
                2,
                2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore same prerequisite for each permitted role"
            );
        }
    }

    // Scenarios: BLLIQ-REENABLE-D09, BLLIQ-REENABLE-D10, BLLIQ-REENABLE-D11, BLLIQ-REENABLE-D12.
    function test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_,
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        vm.assume(!active_ || !enabled_);
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _setPolicyState(_payout, active_, enabled_);
        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_payout);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertActivationRejected(last);
        _restorePolicyState(_payout, active_, enabled_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertEnabled();
    }

    // Scenarios: BLLIQ-REENABLE-D09, BLLIQ-REENABLE-D10, BLLIQ-REENABLE-D11, BLLIQ-REENABLE-D12.
    function test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry(
            true,
            false,
            address(0xabc1),
            false,
            false,
            1,
            2,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for inactive state");
        test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry(
            false,
            true,
            address(0xabc1),
            false,
            false,
            1,
            2,
            2
        );
        assertTrue(vm.revertToState(checkpoint), "Restore Payout for both flags off");
        test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry(
            false,
            false,
            address(0xabc1),
            false,
            false,
            1,
            2,
            2
        );
    }

    // Scenarios: BLLIQ-REENABLE-L02.
    function test_givenActivatedButNeverEnabled_whenReEnabled_thenHistoryWins(
        address caller_
    ) public {
        _liquidation = new BurnerLoansSeize(_kernel, _core);
        _kernel.executeAction(Actions.ActivatePolicy, address(_liquidation));
        _mockUnavailableCoreViews();
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        _liquidation.reEnable();
        assertFalse(
            _liquidation.isEnabled(),
            "Activated policy stays disabled without enable history"
        );
        assertEq(_liquidation.lastTransitionAt(), 0, "No transition initialized");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-REENABLE-D09, BLLIQ-REENABLE-D12.
    function test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry()
        public
    {
        for (uint256 role; role < 3; ++role) {
            uint256 checkpoint = vm.snapshotState();
            test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry(
                true,
                false,
                address(uint160(0xabc1 + role)),
                role == 1,
                role == 2,
                1,
                2,
                2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore Payout for each permitted recovery caller"
            );
        }
    }

    // Scenarios: BLLIQ-REENABLE-D01, BLLIQ-REENABLE-D02, BLLIQ-REENABLE-D03.
    function test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_,
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        vm.assume(!active_ || !enabled_);
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _setPolicyState(_core, active_, enabled_);

        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_core);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertActivationRejected(last);
        _restorePolicyState(_core, active_, enabled_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertEnabled();
    }

    // Scenarios: BLLIQ-REENABLE-D01, BLLIQ-REENABLE-D02, BLLIQ-REENABLE-D03.
    function test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry()
        public
    {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 state; state < 3; ++state) {
            for (uint256 role; role < 3; ++role) {
                uint256 checkpoint = vm.snapshotState();
                test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry(
                    active[state],
                    enabled[state],
                    address(uint160(0xabc1 + role)),
                    role == 1,
                    role == 2,
                    1,
                    2,
                    2
                );
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore prerequisite for each state and role seed"
                );
            }
        }
    }

    // Scenarios: BLLIQ-REENABLE-D05, BLLIQ-REENABLE-D06, BLLIQ-REENABLE-D07, BLLIQ-REENABLE-D08.
    function test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry(
        bool active_,
        bool enabled_,
        address caller_,
        bool blAdmin_,
        bool overlap_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public givenRecoveryWindow(last_, grace_, now_) {
        vm.assume(!active_ || !enabled_);
        _grantReEnableCaller(caller_, blAdmin_, overlap_);
        _setPolicyState(_inventory, active_, enabled_);
        assertTrue(_core.isEnabled(), "Core remains enabled during independent Inventory drift");
        uint48 last = _liquidation.lastTransitionAt();
        _expectDependencyUnavailable(_inventory);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertActivationRejected(last);
        _restorePolicyState(_inventory, active_, enabled_);
        _expectEnabledTransition(caller_);
        vm.prank(caller_);
        _liquidation.reEnable();
        _assertEnabled();
    }

    // Scenarios: BLLIQ-REENABLE-D05, BLLIQ-REENABLE-D06, BLLIQ-REENABLE-D07, BLLIQ-REENABLE-D08.
    function test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry()
        public
    {
        bool[3] memory active = [true, false, false];
        bool[3] memory enabled = [false, true, false];
        for (uint256 state; state < 3; ++state) {
            for (uint256 role; role < 3; ++role) {
                uint256 checkpoint = vm.snapshotState();
                test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry(
                    active[state],
                    enabled[state],
                    address(uint160(0xabc1 + role)),
                    role == 1,
                    role == 2,
                    1,
                    2,
                    2
                );
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore prerequisite for each state and role seed"
                );
            }
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast)
