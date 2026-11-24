// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IPriceCacherTask} from "src/policies/interfaces/IPriceCacherTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {PriceCacherTaskTest} from "./PriceCacherTaskTest.sol";

contract PriceCacherTaskSetGasLimitsTest is PriceCacherTaskTest {
    // Scenarios: PCACHER-GAS-A01, PCACHER-GAS-P02.
    function test_whenAdminSetsValidLimits_thenUpdatesBoth(
        address caller_,
        uint32 executionGas_,
        uint32 pairGas_
    ) public {
        _grantTestRole(ADMIN_ROLE, caller_);
        _assertSetGasLimits(caller_, executionGas_, pairGas_);
    }

    // Scenarios: PCACHER-GAS-A03, PCACHER-GAS-P02.
    function test_whenPriceAdminSetsValidLimits_thenUpdatesBoth(
        address caller_,
        uint32 executionGas_,
        uint32 pairGas_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        _grantTestRole(PRICE_ADMIN_ROLE, caller_);
        _assertSetGasLimits(caller_, executionGas_, pairGas_);
    }

    function _assertSetGasLimits(address caller_, uint32 executionGas_, uint32 pairGas_) private {
        executionGas_ = uint32(bound(executionGas_, 40_002, type(uint32).max));
        pairGas_ = uint32(bound(pairGas_, 1, executionGas_ - 40_001));
        vm.assume(executionGas_ != 1_000_000 || pairGas_ != 400_000);

        vm.expectEmit(address(cacher));
        emit IPriceCacherTask.GasLimitsSet(executionGas_, pairGas_);
        vm.prank(caller_);
        cacher.setGasLimits(executionGas_, pairGas_);

        _assertGasLimits(executionGas_, pairGas_);
    }

    // Scenarios: PCACHER-GAS-P02.
    function test_whenAdminSetsBoundaryLimits_thenUpdatesBoth() public {
        test_whenAdminSetsValidLimits_thenUpdatesBoth(admin, 40_002, 1);
        test_whenAdminSetsValidLimits_thenUpdatesBoth(
            admin,
            type(uint32).max,
            type(uint32).max - 40_001
        );
    }

    // Scenarios: PCACHER-GAS-A02.
    function test_whenCallerLacksBothRoles_reverts(address caller_) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, PRICE_ADMIN_ROLE));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        cacher.setGasLimits(600_000, 200_000);

        _assertGasLimits(1_000_000, 400_000);
    }

    // Scenarios: PCACHER-GAS-L01.
    function test_givenDisabled_whenAdminSetsLimits_thenUpdatesBoth() public {
        _setTaskEnabled(false);
        test_whenAdminSetsValidLimits_thenUpdatesBoth(admin, 600_000, 200_000);
        assertFalse(cacher.isEnabled(), "the task stays disabled");
    }

    // Scenarios: PCACHER-GAS-L01.
    function test_givenDisabled_whenPriceAdminSetsLimits_thenUpdatesBoth() public {
        _setTaskEnabled(false);
        test_whenPriceAdminSetsValidLimits_thenUpdatesBoth(alice, 600_000, 200_000);
        assertFalse(cacher.isEnabled(), "the task stays disabled");
    }

    // Scenarios: PCACHER-GAS-L01.
    function test_givenReEnabled_whenAdminSetsLimits_thenUpdatesBoth() public {
        _setTaskEnabled(false);
        vm.prank(admin);
        cacher.reEnable();
        test_whenAdminSetsValidLimits_thenUpdatesBoth(admin, 600_000, 200_000);
    }

    // Scenarios: PCACHER-GAS-L01.
    function test_givenReEnabled_whenPriceAdminSetsLimits_thenUpdatesBoth() public {
        _setTaskEnabled(false);
        vm.prank(admin);
        cacher.reEnable();
        test_whenPriceAdminSetsValidLimits_thenUpdatesBoth(alice, 600_000, 200_000);
    }

    // Scenarios: PCACHER-GAS-L02.
    function test_givenKernelInactive_whenSettingLimits_reverts(bool enabled_) public {
        _setTaskEnabled(enabled_);
        _setTaskMembership(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceCacherTask.PriceCacherTask_PolicyInactive.selector,
                address(cacher)
            )
        );
        vm.prank(admin);
        cacher.setGasLimits(600_000, 200_000);

        _assertGasLimits(1_000_000, 400_000);
    }

    // Scenarios: PCACHER-GAS-L02.
    function test_givenKernelInactive_whenSettingLimits_revertsInBothLocalStates() public {
        test_givenKernelInactive_whenSettingLimits_reverts(true);
        test_givenKernelInactive_whenSettingLimits_reverts(false);
    }

    // Scenarios: PCACHER-GAS-L03.
    function test_givenKernelReactivated_whenAdminSetsLimits_thenUpdatesBoth() public {
        _setTaskMembership(false);
        _setTaskMembership(true);
        test_whenAdminSetsValidLimits_thenUpdatesBoth(admin, 600_000, 200_000);
    }

    // Scenarios: PCACHER-GAS-N01, PCACHER-GAS-N02.
    function test_whenLimitsLeaveInsufficientGasForAPair_revertsForBoundaries() public {
        _expectInvalidLimits(0, 1);
        _expectInvalidLimits(1, 1);
        _expectInvalidLimits(1_000_000, 0);
        _expectInvalidLimits(440_000, 400_000);
        _expectInvalidLimits(439_999, 400_000);
        _expectInvalidLimits(type(uint32).max, type(uint32).max);
    }

    // Scenarios: PCACHER-GAS-N02.
    function test_whenLimitsLeaveInsufficientGasForAPair_reverts(
        uint32 executionGas_,
        uint32 pairGas_
    ) public {
        pairGas_ = uint32(bound(pairGas_, 1, type(uint32).max));
        uint256 highestInvalidLimit = uint256(pairGas_) + 40_000;
        if (highestInvalidLimit > type(uint32).max) highestInvalidLimit = type(uint32).max;
        executionGas_ = uint32(bound(executionGas_, 0, highestInvalidLimit));
        _expectInvalidLimits(executionGas_, pairGas_);
    }

    // Scenarios: PCACHER-GAS-P03.
    function test_whenLimitsAreUnchanged_thenNoEvent() public {
        vm.recordLogs();
        vm.prank(admin);
        cacher.setGasLimits(1_000_000, 400_000);

        assertEq(vm.getRecordedLogs().length, 0, "unchanged limits emit no event");
        _assertGasLimits(1_000_000, 400_000);
    }

    function _expectInvalidLimits(uint32 executionGas_, uint32 pairGas_) private {
        vm.expectRevert(IPriceCacherTask.PriceCacherTask_InvalidGasLimits.selector);
        vm.prank(admin);
        cacher.setGasLimits(executionGas_, pairGas_);
        _assertGasLimits(1_000_000, 400_000);
    }

    function _assertGasLimits(uint32 executionGas_, uint32 pairGas_) private view {
        assertEq(cacher.executionGasLimit(), executionGas_, "aggregate self-call cap");
        assertEq(cacher.pairGasLimit(), pairGas_, "per-pair call cap");
    }
}
