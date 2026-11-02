// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {Kernel} from "src/Kernel.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskReEnableTest is RevenueDistributorTaskTest {
    function test_givenDisabledWithinGrace_whenPermittedCallerReEnables(
        bool adminCalls_,
        uint8 timePoint_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("");
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

    function test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts() public {
        RevenueDistributorTask fresh = _newActivatedTask();

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        fresh.reEnable();

        assertFalse(fresh.isEnabled(), "fresh task remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "timestamp remains zero");
    }

    // Scenarios: RDTASK-REENABLE-A02.
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

    function test_givenEnabled_whenReEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        task.reEnable();
    }

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

    function test_givenDistributorInactive_whenPermittedCallerReEnables_reverts(
        bool adminCalls_,
        bool distributorEnabled_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("");
        _setDistributorLifecycle(false, distributorEnabled_);

        _expectDistributorNotActive();
        vm.prank(adminCalls_ ? admin : bob);
        task.reEnable();

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    function test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts(
        bool adminCalls_
    ) public {
        _grantRevenueDistributorAdmin(bob);
        _disableTask("");
        _disableDistributor();

        _expectDistributorNotActive();
        vm.prank(adminCalls_ ? admin : bob);
        task.reEnable();

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    function test_givenRepresentableGrace_whenPermittedCallerReEnables(
        address caller_,
        bool adminRole_,
        bool revenueRole_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        _grantReEnableCaller(caller_, adminRole_, revenueRole_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace_));
        uint48 deadline = disabledAt_ + grace_;
        now_ = SafeCast.toUint48(bound(now_, disabledAt_, deadline));
        _seedLifecycleRevenue();
        vm.prank(admin);
        task.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        assertEq(task.lastTransitionAt(), disabledAt_, "Disable establishes grace origin");
        vm.warp(now_);
        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        task.reEnable();
        assertTrue(task.isEnabled(), "Permitted caller re-enables inside grace");
        assertEq(task.lastTransitionAt(), now_, "Re-enable records current timestamp");
        _assertLifecycleRevenue();
    }

    function test_givenOverflowingGrace_whenPermittedCallerReEnables_reverts(
        uint32 grace_,
        uint48 disabledAt_,
        bool revenueAdmin_
    ) public {
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max)
        );
        _seedLifecycleRevenue();
        vm.prank(admin);
        task.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        uint256 deadline = uint256(disabledAt_) + grace_;
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                deadline
            )
        );
        vm.prank(bob);
        task.reEnable();
        assertFalse(task.isEnabled(), "Overflow leaves policy disabled");
        assertEq(task.lastTransitionAt(), disabledAt_, "Overflow preserves grace origin");
        assertEq(vm.getRecordedLogs().length, 0, "Overflow emits no transition");
        _assertLifecycleRevenue();
    }

    function test_givenInactivePolicy_whenPermittedReEnable_reverts(bool revenueAdmin_) public {
        _seedLifecycleRevenue();
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.prank(admin);
        task.disable("");
        _setPolicyActive(address(task), false);
        uint48 beforeAt = task.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorTask.RevenueDistributorTask_PolicyNotActive.selector,
                address(task)
            )
        );
        vm.prank(bob);
        task.reEnable();
        assertFalse(task.isEnabled(), "Inactive policy stays disabled");
        assertEq(task.lastTransitionAt(), beforeAt, "Inactive re-enable preserves timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-REENABLE-L05, RDTASK-REENABLE-P01, RDTASK-REENABLE-P02.
    function test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts(
        address caller_,
        bool activated_
    ) public {
        RevenueDistributorTask fresh = new RevenueDistributorTask(
            kernel,
            address(distributor),
            5_000_000
        );
        if (activated_) _setPolicyActive(address(fresh), true);
        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(caller_);
        fresh.reEnable();
        assertFalse(fresh.isEnabled(), "Never-enabled policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Never-enabled timestamp stays zero");
    }

    function test_givenExpiredGrace_whenPermittedCallerReEnables_reverts(
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_,
        bool revenueAdmin_
    ) public {
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace_ - 1)
        );
        uint48 deadline = disabledAt_ + grace_;
        now_ = SafeCast.toUint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        _seedLifecycleRevenue();
        vm.prank(admin);
        task.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(bob);
        task.reEnable();
        assertFalse(task.isEnabled(), "Expired grace keeps policy disabled");
        assertEq(task.lastTransitionAt(), disabledAt_, "Expired grace preserves timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-REENABLE-D06.
    function test_givenDistributorKernelDrift_whenActivation_reverts(
        bool distributorActive_
    ) public {
        vm.prank(admin);
        task.disable("");
        if (!distributorActive_) _setPolicyActive(address(distributor), false);
        Kernel otherKernel = new Kernel();
        vm.prank(address(kernel));
        distributor.changeKernel(otherKernel);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(distributor),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(admin);
        task.reEnable();
        assertFalse(task.isEnabled(), "Kernel drift prevents activation");
    }

    function test_givenUnavailableDistributor_whenActivation_reverts(
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(!distributorActive_ || !distributorEnabled_);
        _seedLifecycleRevenue();
        vm.prank(admin);
        task.disable("");
        if (!distributorEnabled_) {
            vm.prank(admin);
            distributor.disable("");
        }
        if (!distributorActive_) _setPolicyActive(address(distributor), false);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(admin);
        task.reEnable();
        assertFalse(task.isEnabled(), "Unavailable service prevents activation");
        assertEq(task.lastTransitionAt(), beforeAt, "Failed activation preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Failed activation emits no logs");
        _assertLifecycleRevenue();
    }

    function test_givenGraceAndRoleBoundarySeeds_whenReEnabled() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenRepresentableGrace_whenPermittedCallerReEnables(bob, true, false, 1, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore start-of-grace seed");
        test_givenRepresentableGrace_whenPermittedCallerReEnables(bob, false, true, 1, 1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore exact deadline seed");
        test_givenRepresentableGrace_whenPermittedCallerReEnables(
            bob,
            true,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore adjacent deadline seed");
        test_givenRepresentableGrace_whenPermittedCallerReEnables(
            bob,
            true,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max
        );
    }

    function test_givenOverflowBoundarySeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOverflowingGrace_whenPermittedCallerReEnables_reverts(1, type(uint48).max, false);
        assertTrue(vm.revertToState(checkpoint), "Restore minimum overflow seed");
        test_givenOverflowingGrace_whenPermittedCallerReEnables_reverts(
            type(uint32).max,
            type(uint48).max - type(uint32).max + 1,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore adjacent overflow seed");
        test_givenOverflowingGrace_whenPermittedCallerReEnables_reverts(
            type(uint32).max,
            type(uint48).max,
            false
        );
    }

    function test_givenExpiredBoundarySeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenExpiredGrace_whenPermittedCallerReEnables_reverts(1, 1, 3, false);
        assertTrue(vm.revertToState(checkpoint), "Restore first expired instant");
        test_givenExpiredGrace_whenPermittedCallerReEnables_reverts(
            type(uint32).max,
            type(uint48).max - type(uint32).max - 1,
            type(uint48).max,
            true
        );
    }

    function test_givenDistributorStateSeeds_whenActivation_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenUnavailableDistributor_whenActivation_reverts(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive disabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(true, false);
    }

    // Scenarios: RDTASK-REENABLE-P03.
    function test_givenRestoredDistributor_whenActivation_succeeds() public {
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        _setPolicyActive(address(distributor), true);
        vm.prank(admin);
        distributor.enable("");
        vm.prank(admin);
        task.reEnable();
        assertTrue(task.isEnabled(), "Restored service permits activation");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-REENABLE-L02, RDTASK-REENABLE-L04.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(
        address caller_,
        bool active_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        task.reEnable();
        assertTrue(task.isEnabled(), "Enabled guard preserves enabled state");
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

    // Scenarios: RDTASK-REENABLE-L03.
    function test_givenInactive_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
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
        task.reEnable();
        assertFalse(task.isEnabled(), "Inactive subject stays disabled");
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

    // Scenarios: RDTASK-REENABLE-L01, RDTASK-REENABLE-N02, RDTASK-REENABLE-N03.
    function test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace_));
        now_ = SafeCast.toUint48(bound(now_, disabledAt_, uint256(disabledAt_) + grace_));
        vm.prank(admin);
        task.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        assertEq(task.lastTransitionAt(), disabledAt_, "Disable sets grace origin");
        vm.warp(now_);
        bytes32 beforeState = _taskStateDigest(queueId);
        vm.expectEmit(address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.recordLogs();
        vm.prank(caller_);
        task.reEnable();
        assertTrue(task.isEnabled(), "Permitted caller re-enables within inclusive grace");
        assertEq(task.lastTransitionAt(), now_, "Re-enable stores exact timestamp");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Successful re-enable preserves configuration, queue and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 2, "Re-enable emits exactly two lifecycle events");
    }

    // Scenarios: RDTASK-REENABLE-N01.
    function test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max)
        );
        vm.prank(admin);
        task.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt_) + grace_
            )
        );
        vm.prank(caller_);
        task.reEnable();
        assertFalse(task.isEnabled(), "Unrepresentable grace leaves policy disabled");
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

    // Scenarios: RDTASK-REENABLE-N04.
    function test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace_ - 1)
        );
        uint48 deadline = disabledAt_ + grace_;
        now_ = SafeCast.toUint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.prank(admin);
        task.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        task.disable("");
        vm.warp(now_);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        task.reEnable();
        assertFalse(task.isEnabled(), "Expired grace leaves policy disabled");
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

    // Scenarios: RDTASK-REENABLE-L01, RDTASK-REENABLE-L02, RDTASK-REENABLE-L03, RDTASK-REENABLE-L04, RDTASK-REENABLE-N01, RDTASK-REENABLE-N02, RDTASK-REENABLE-N03, RDTASK-REENABLE-N04.
    function test_givenReEnableBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenAnyCallerReEnables_reverts(address(0), true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenEnabled_whenAnyCallerReEnables_reverts(address(0), false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenInactive_whenAuthorizedCallerReEnables_reverts(bob, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, false, false, 1, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, false, false, 1, 1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            false,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            false,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max + 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(bob, false, false, 1, 1, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max - 1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenInactive_whenAuthorizedCallerReEnables_reverts(bob, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, true, false, 1, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, true, false, 1, 1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            true,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            true,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max + 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(bob, true, false, 1, 1, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            type(uint32).max,
            type(uint48).max - type(uint32).max - 1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenInactive_whenAuthorizedCallerReEnables_reverts(bob, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, false, true, 1, 1, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(bob, false, true, 1, 1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            false,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
            bob,
            false,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max + 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            type(uint32).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(bob, false, true, 1, 1, 3);
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
        test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            type(uint32).max,
            type(uint48).max - type(uint32).max - 1,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent re-enable seed");
    }

    // Scenarios: RDTASK-REENABLE-D01, RDTASK-REENABLE-D02, RDTASK-REENABLE-D03.
    function test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(!distributorActive_ || !distributorEnabled_);
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        vm.prank(admin);
        task.disable("");
        _setRevenuePolicyLifecycle(address(distributor), distributorActive_, distributorEnabled_);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(caller_);
        task.reEnable();
        assertFalse(task.isEnabled(), "Unavailable dependency retains disabled subject");
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

    // Scenarios: RDTASK-REENABLE-D01, RDTASK-REENABLE-D02, RDTASK-REENABLE-D03.
    function test_givenRestoredDistributor_whenAuthorizedCallerReEnables(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            caller_,
            revenueOnly_,
            overlap_,
            distributorActive_,
            distributorEnabled_
        );
        if (!distributorActive_) _setPolicyActive(address(distributor), true);
        if (!distributorEnabled_) {
            vm.prank(admin);
            distributor.enable("");
        }
        bytes32 beforeAccounting = _revenueAccountingDigest();
        vm.prank(caller_);
        task.reEnable();
        assertTrue(task.isEnabled(), "Restoration permits the same authorized retry");
        assertEq(
            _revenueAccountingDigest(),
            beforeAccounting,
            "Restored retry preserves all accounting"
        );
    }

    // Scenarios: RDTASK-REENABLE-D01, RDTASK-REENABLE-D02, RDTASK-REENABLE-D03.
    function test_givenDependencyAndRoleSeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, false, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, false, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(
            bob,
            false,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, true, false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, true, false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            true,
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, true, false, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, false, true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, false, true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
            bob,
            false,
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
        test_givenRestoredDistributor_whenAuthorizedCallerReEnables(bob, false, true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore dependency and role seed");
    }

    function test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        vm.prank(admin);
        task.disable("");
        Kernel otherKernel = new Kernel();
        vm.prank(address(kernel));
        distributor.changeKernel(otherKernel);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(distributor),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(caller_);
        task.reEnable();
        assertFalse(task.isEnabled(), "Kernel drift prevents re-enable");
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

    function test_givenKernelDriftRoleSeeds_whenReEnabled_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts(bob, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore drift role seed");
        test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts(bob, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore drift role seed");
        test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts(bob, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore drift role seed");
    }
}
