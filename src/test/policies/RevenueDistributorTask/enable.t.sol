// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskEnableTest is RevenueDistributorTaskTest {
    // Scenarios: LC-P01, LC-L02.
    function test_givenDisabled_whenAdminEnables_preservesConfiguration(
        bytes calldata data_,
        bool active_
    ) public {
        _disableTask("prior disable");
        if (!active_) _deactivateTask();
        uint32 executionLimit = task.executionGasLimit();
        uint32 threshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();
        uint48 transitionTime = 2 days;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(admin, true, data_, transitionTime);
        vm.prank(admin);
        task.enable(data_);

        assertTrue(task.isEnabled(), "admin enables task");
        assertEq(task.lastTransitionAt(), transitionTime, "enable records timestamp");
        assertEq(task.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(task.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(task.gasReserve(), reserve, "reserve preserved");
    }

    // Scenarios: LC-P01.
    function test_givenNeverEnabled_whenAdminEnables() public {
        RevenueDistributorTask fresh = _newActivatedTask();

        vm.prank(admin);
        fresh.enable("");

        assertTrue(fresh.isEnabled(), "fresh task enabled");
        assertEq(fresh.lastTransitionAt(), block.timestamp, "transition timestamp recorded");
    }

    // Scenarios: LC-I01.
    function test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks(
        address caller_,
        bytes calldata data_,
        bool taskActive_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        _setDistributorLifecycle(distributorActive_, distributorEnabled_);
        if (!taskActive_) _deactivateTask();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        task.enable(data_);

        assertTrue(task.isEnabled(), "failed enable preserves enabled state");
    }

    // Scenarios: LC-A01.
    function test_givenDisabled_whenNonAdminEnables_reverts(
        address caller_,
        bytes calldata data_,
        bool active_
    ) public {
        vm.assume(caller_ != admin);
        _disableTask("");
        if (!active_) _deactivateTask();
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        task.enable(data_);

        assertFalse(task.isEnabled(), "unauthorized enable preserves disabled state");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-I04.
    function test_givenDistributorInactive_whenAdminEnables_reverts(
        bytes calldata data_,
        bool taskActive_,
        bool distributorEnabled_
    ) public {
        _disableTask("");
        _setDistributorLifecycle(false, distributorEnabled_);
        if (!taskActive_) _deactivateTask();

        _expectInvalidDistributor();
        vm.prank(admin);
        task.enable(data_);

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    // Scenarios: LC-I05.
    function test_givenDistributorDisabled_whenAdminEnables_reverts(
        bytes calldata data_,
        bool taskActive_
    ) public {
        _disableTask("");
        _disableDistributor();
        if (!taskActive_) _deactivateTask();

        _expectInvalidDistributor();
        vm.prank(admin);
        task.enable(data_);

        assertFalse(task.isEnabled(), "task remains disabled");
    }
}
