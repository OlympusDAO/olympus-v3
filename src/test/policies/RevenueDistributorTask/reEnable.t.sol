// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskReEnableTest is RevenueDistributorTaskTest {
    // Scenarios: LC-P03, LC-L02.
    function test_givenDisabledWithinGrace_whenPermittedCallerReEnables(
        bool adminCalls_,
        bool active_,
        uint8 timePoint_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("prior disable");
        if (!active_) _deactivateTask();
        address caller = adminCalls_ ? admin : bob;
        uint48 disabledAt = task.lastTransitionAt();
        uint48 deadline = disabledAt + task.gracePeriod();
        timePoint_ = _boundUint8(timePoint_, 0, 2);
        uint48 reEnableAt = timePoint_ == 0
            ? disabledAt
            : (timePoint_ == 1 ? deadline - 1 : deadline);
        vm.warp(reEnableAt);
        uint32 executionLimit = task.executionGasLimit();

        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller, true, "", reEnableAt);
        vm.prank(caller);
        task.reEnable();

        assertTrue(task.isEnabled(), "permitted caller re-enables task");
        assertEq(task.lastTransitionAt(), reEnableAt, "re-enable records timestamp");
        assertEq(task.executionGasLimit(), executionLimit, "configuration preserved");
    }

    // Scenarios: LC-I02.
    function test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts() public {
        RevenueDistributorTask fresh = _newActivatedTask();

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        fresh.reEnable();

        assertFalse(fresh.isEnabled(), "fresh task remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "timestamp remains zero");
    }

    // Scenarios: LC-A02.
    function test_givenDisabled_whenUnauthorizedCallerReEnables_reverts(address caller_) public {
        _grantRevenueDistributorAdmin(bob);
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        _disableTask("");
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.reEnable();

        assertFalse(task.isEnabled(), "task remains disabled");
        assertEq(task.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-I06.
    function test_givenEnabled_whenReEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        task.reEnable();
    }

    // Scenarios: LC-I07.
    function test_givenGraceExpired_whenAdminReEnables_reverts(uint48 timestamp_) public {
        _disableTask("");
        uint48 transitionAt = task.lastTransitionAt();
        uint48 deadline = transitionAt + task.gracePeriod();
        timestamp_ = _boundUint48(timestamp_, deadline + 1, type(uint48).max);
        vm.warp(timestamp_);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(admin);
        task.reEnable();

        assertFalse(task.isEnabled(), "expired task remains disabled");
        assertEq(task.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    // Scenarios: LC-I04.
    function test_givenDistributorInactive_whenPermittedCallerReEnables_reverts(
        bool adminCalls_,
        bool taskActive_,
        bool distributorEnabled_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("");
        _setDistributorLifecycle(false, distributorEnabled_);
        if (!taskActive_) _deactivateTask();

        _expectInvalidDistributor();
        vm.prank(adminCalls_ ? admin : bob);
        task.reEnable();

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    // Scenarios: LC-I05.
    function test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts(
        bool adminCalls_,
        bool taskActive_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("");
        _disableDistributor();
        if (!taskActive_) _deactivateTask();

        _expectInvalidDistributor();
        vm.prank(adminCalls_ ? admin : bob);
        task.reEnable();

        assertFalse(task.isEnabled(), "task remains disabled");
    }
}
