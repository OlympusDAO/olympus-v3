// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskDisableTest is RevenueDistributorTaskTest {
    function test_whenPermittedCallerDisables_preservesConfiguration(
        bool adminCalls_,
        bool active_,
        uint48 timestamp_
    ) public {
        address caller = adminCalls_ ? admin : emergency;
        if (!active_) _deactivateTask();
        uint32 executionLimit = task.executionGasLimit();
        uint32 threshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();
        uint48 transitionTime = 2 days;
        transitionTime = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller, false, "", transitionTime);
        vm.prank(caller);
        task.disable("");

        assertFalse(task.isEnabled(), "permitted caller disables task");
        assertEq(task.lastTransitionAt(), transitionTime, "disable records timestamp");
        assertEq(task.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(task.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(task.gasReserve(), reserve, "reserve preserved");
    }

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

    function test_givenEnabledPolicy_whenNonemptyDisableData_reverts(
        bytes memory data_,
        bool active_,
        bool adminCalls_
    ) public {
        vm.assume(data_.length > 0);
        _seedLifecycleRevenue();
        if (!active_) _setPolicyActive(address(task), false);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidData.selector);
        vm.prank(adminCalls_ ? admin : emergency);
        task.disable(data_);
        assertTrue(task.isEnabled(), "Invalid pause payload preserves enabled state");
        assertEq(task.lastTransitionAt(), beforeAt, "Invalid pause preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Invalid pause emits no logs");
        _assertLifecycleRevenue();
    }

    function test_givenEnabledPolicy_whenDisablePayloadBoundaries_reverts() public {
        test_givenEnabledPolicy_whenNonemptyDisableData_reverts(hex"00", true, true);
    }

    function test_givenAnyPolicyActivity_whenPermittedCallerPauses_preservesAccounting(
        bool active_,
        bool adminRole_,
        bool emergencyRole_,
        address caller_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != admin && caller_ != emergency);
        vm.assume(adminRole_ || emergencyRole_);
        _seedLifecycleRevenue();
        vm.startPrank(admin);
        if (adminRole_) rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (emergencyRole_) rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.stopPrank();
        if (!active_) _setPolicyActive(address(task), false);
        uint48 transitionAt = 2 days;
        vm.warp(transitionAt);
        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller_, false, "", transitionAt);
        vm.prank(caller_);
        task.disable("");
        assertFalse(task.isEnabled(), "Authorized caller pauses policy");
        assertEq(task.lastTransitionAt(), transitionAt, "Pause records timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-DISABLE-L07.
    function test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts(address caller_) public {
        RevenueDistributorTask fresh = new RevenueDistributorTask(
            kernel,
            address(distributor),
            5_000_000
        );
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RDTASK-DISABLE-D01.
    function test_givenBrokenDistributor_whenEmergencyPauses_succeeds(bool active_) public {
        _seedLifecycleRevenue();
        Kernel otherKernel = new Kernel();
        vm.prank(address(kernel));
        distributor.changeKernel(otherKernel);
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("Unavailable()")
        );
        if (!active_) _setPolicyActive(address(task), false);
        vm.prank(emergency);
        task.disable("");
        assertFalse(task.isEnabled(), "Broken service cannot prevent emergency pause");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-DISABLE-I03, RDTASK-DISABLE-L03, RDTASK-DISABLE-L06.
    function test_givenDisabled_whenAnyCallerPauses_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        vm.prank(admin);
        task.disable("");
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        task.disable(data_);
        assertFalse(task.isEnabled(), "Already disabled policy remains disabled");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-DISABLE-A03, RDTASK-DISABLE-I04.
    function test_givenEnabled_whenCallerLacksPauseRoles_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, EMERGENCY_ROLE));
        uint64 queueId = _seedTaskLifecycleQueue();
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        task.disable(data_);
        assertTrue(task.isEnabled(), "Unauthorized pause preserves enabled state");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-DISABLE-I01.
    function test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
        address caller_,
        bytes memory data_,
        bool active_,
        bool emergencyOnly_,
        bool overlap_
    ) public {
        vm.assume(data_.length > 0 && data_.length <= 256);
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, EMERGENCY_ROLE, emergencyOnly_, overlap_);
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidData.selector);
        vm.prank(caller_);
        task.disable(data_);
        assertTrue(task.isEnabled(), "Invalid pause data preserves enabled state");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-DISABLE-L01, RDTASK-DISABLE-L04, RDTASK-DISABLE-L08, RDTASK-DISABLE-P02.
    function test_givenEnabled_whenAuthorizedCallerPauses(
        address caller_,
        bool active_,
        bool emergencyOnly_,
        bool overlap_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, EMERGENCY_ROLE, emergencyOnly_, overlap_);
        if (!active_) _setPolicyActive(address(task), false);
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _taskStateDigest(queueId);
        vm.expectEmit(address(task));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller_, false, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        task.disable("");
        assertFalse(task.isEnabled(), "Permitted authority pauses policy");
        assertEq(task.lastTransitionAt(), timestamp_, "Pause stores timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Pause emits exactly two lifecycle events");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDTASK-DISABLE-A03, RDTASK-DISABLE-I01, RDTASK-DISABLE-I03, RDTASK-DISABLE-I04, RDTASK-DISABLE-L01, RDTASK-DISABLE-L03, RDTASK-DISABLE-L04, RDTASK-DISABLE-L06, RDTASK-DISABLE-L08, RDTASK-DISABLE-P02.
    function test_givenPauseBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDisabled_whenAnyCallerPauses_reverts(address(0), hex"00", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenDisabled_whenAnyCallerPauses_reverts(address(0), new bytes(256), false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenCallerLacksPauseRoles_reverts(address(0), "", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenCallerLacksPauseRoles_reverts(address(0), hex"00", false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, false, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, false, false, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"00", true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"01", true, false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            true,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, false, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, false, false, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            hex"00",
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            hex"01",
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            false,
            false,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, true, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, true, false, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"00", true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"01", true, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            true,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, true, false, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, true, false, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"00", false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"01", false, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            false,
            true,
            false
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, false, true, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, true, false, true, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"00", true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"01", true, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            true,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, false, true, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedCallerPauses(bob, false, false, true, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"00", false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(bob, hex"01", false, false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(32),
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
        test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
            bob,
            new bytes(256),
            false,
            false,
            true
        );
        assertTrue(vm.revertToState(checkpoint), "Restore independent pause seed");
    }
}
