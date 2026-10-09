// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskDisableTest is RevenueDistributorTaskTest {
    // Scenarios: LC-P02, LC-L02.
    function test_whenPermittedCallerDisables_preservesConfiguration(
        bool adminCalls_,
        bool active_,
        bytes calldata data_
    ) public {
        address caller = adminCalls_ ? admin : emergency;
        if (!active_) _deactivateTask();
        uint32 executionLimit = task.executionGasLimit();
        uint32 threshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();
        uint48 transitionTime = 2 days;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller, false, data_, transitionTime);
        vm.prank(caller);
        task.disable(data_);

        assertFalse(task.isEnabled(), "permitted caller disables task");
        assertEq(task.lastTransitionAt(), transitionTime, "disable records timestamp");
        assertEq(task.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(task.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(task.gasReserve(), reserve, "reserve preserved");
    }

    // Scenarios: LC-I05.
    function test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_
    ) public {
        _disableTask("");
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        task.disable(data_);

        assertFalse(task.isEnabled(), "task remains disabled");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: LC-A03.
    function test_givenEnabled_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.disable(data_);

        assertTrue(task.isEnabled(), "task remains enabled");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }
}
