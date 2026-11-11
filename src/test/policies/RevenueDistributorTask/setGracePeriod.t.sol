// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";

import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskSetGracePeriodTest is RevenueDistributorTaskTest {
    // Scenarios: RDTASK-GRACE-P04.
    function test_whenAdminSetsPositiveGracePeriod_updatesValue(uint32 period_) public {
        period_ = _boundUint32(period_, 1, type(uint32).max);
        uint32 currentPeriod = task.gracePeriod();
        if (period_ == currentPeriod) {
            period_ = currentPeriod == type(uint32).max ? currentPeriod - 1 : currentPeriod + 1;
        }
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(task));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), period_, "grace period equals input");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: RDTASK-GRACE-I03.
    function test_whenAdminSetsZeroGracePeriod_reverts() public {
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        task.setGracePeriod(0);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    function test_whenAdminSetsCurrentGracePeriod_emitsEvent() public {
        uint32 currentPeriod = task.gracePeriod();
        uint48 transitionAt = task.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(task));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        task.setGracePeriod(currentPeriod);

        assertEq(task.gracePeriod(), currentPeriod, "same grace period retained");
        assertEq(task.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    function test_givenDisabled_whenGracePeriodSet_revertsBeforeOtherChecks(
        address caller_,
        uint32 period_
    ) public {
        _disableTask("");

        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: RDTASK-GRACE-L04.
    function test_givenInactiveAndDisabled_whenGracePeriodSet_revertsBeforeOtherChecks(
        address caller_,
        uint32 period_
    ) public {
        _disableTask("");
        _deactivateTask();
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: RDTASK-GRACE-A04.
    function test_givenEnabled_whenNonAdminSetsGracePeriod_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != admin);
        uint32 periodBefore = task.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        task.setGracePeriod(period_);

        assertEq(task.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: RDTASK-GRACE-L02, RDTASK-GRACE-P06.
    function test_givenInactivePolicy_whenAdminChangesGrace_reverts(uint32 period_) public {
        _setPolicyActive(address(task), false);
        uint32 beforePeriod = task.gracePeriod();
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(admin);
        task.setGracePeriod(period_);
        assertEq(task.gracePeriod(), beforePeriod, "Inactive setter preserves grace");
        assertEq(task.lastTransitionAt(), beforeAt, "Inactive setter preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Inactive setter emits no logs");
    }

    // Scenarios: RDTASK-GRACE-P05.
    function test_givenCurrentGrace_whenAdminSetsSameValue(uint32 period_) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        period_ = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        vm.prank(admin);
        task.setGracePeriod(period_);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(task));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.recordLogs();
        vm.prank(admin);
        task.setGracePeriod(period_);
        assertEq(task.gracePeriod(), period_, "Same valid duration is preserved");
        assertEq(task.lastTransitionAt(), beforeAt, "Same duration preserves transition timestamp");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Same duration preserves configuration, queue and custody"
        );
        assertEq(
            vm.getRecordedLogs().length,
            1,
            "Same valid duration still emits exactly one event"
        );
    }

    // Scenarios: RDTASK-GRACE-L01.
    function test_givenDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        vm.prank(admin);
        task.disable("");

        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        task.setGracePeriod(period_);
        assertFalse(task.isEnabled(), "Disabled setter preserves disabled state");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            task.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDTASK-GRACE-L03.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        vm.prank(admin);
        task.disable("");
        _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(caller_);
        task.setGracePeriod(period_);
        assertFalse(task.isEnabled(), "Disabled setter preserves disabled state");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            task.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDTASK-GRACE-L01, RDTASK-GRACE-L03, RDTASK-GRACE-P05.
    function test_givenGraceSetterBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCurrentGrace_whenAdminSetsSameValue(1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenCurrentGrace_whenAdminSetsSameValue(type(uint32).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenDisabled_whenAnyCallerSetsGrace_reverts(address(0), 0);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenDisabled_whenAnyCallerSetsGrace_reverts(address(0), 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenDisabled_whenAnyCallerSetsGrace_reverts(address(0), type(uint32).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst(address(0), 0);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst(address(0), 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst(
            address(0),
            type(uint32).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
    }
}
