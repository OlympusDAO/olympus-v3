// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {Kernel} from "src/Kernel.sol";
import {IRevenueDistributorTask} from "src/policies/interfaces/IRevenueDistributorTask.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorTask} from "src/policies/RevenueDistributorTask.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTaskTest} from "./RevenueDistributorTaskTest.sol";

contract RevenueDistributorTaskEnableTest is RevenueDistributorTaskTest {
    function test_givenDisabled_whenAdminEnables_preservesConfiguration() public {
        _disableTask("");
        uint32 executionLimit = task.executionGasLimit();
        uint32 threshold = task.minimumGasToAttempt();
        uint32 reserve = task.gasReserve();
        uint48 transitionTime = 2 days;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(admin, true, "", transitionTime);
        vm.prank(admin);
        task.enable("");

        assertTrue(task.isEnabled(), "admin enables task");
        assertEq(task.lastTransitionAt(), transitionTime, "enable records timestamp");
        assertEq(task.executionGasLimit(), executionLimit, "execution limit preserved");
        assertEq(task.minimumGasToAttempt(), threshold, "threshold preserved");
        assertEq(task.gasReserve(), reserve, "reserve preserved");
    }

    function test_givenNeverEnabled_whenAdminEnables() public {
        RevenueDistributorTask fresh = _newActivatedTask();

        vm.prank(admin);
        fresh.enable("");

        assertTrue(fresh.isEnabled(), "fresh task enabled");
        assertEq(fresh.lastTransitionAt(), block.timestamp, "transition timestamp recorded");
    }

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

    function test_givenDistributorInactive_whenAdminEnables_reverts(
        bool distributorEnabled_
    ) public {
        _disableTask("");
        _setDistributorLifecycle(false, distributorEnabled_);

        _expectDistributorNotActive();
        vm.prank(admin);
        task.enable("");

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    function test_givenDistributorDisabled_whenAdminEnables_reverts() public {
        _disableTask("");
        _disableDistributor();

        _expectDistributorNotActive();
        vm.prank(admin);
        task.enable("");

        assertFalse(task.isEnabled(), "task remains disabled");
    }

    function test_givenEnabledPolicy_whenAnyCallerEnablesWithData_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        if (!active_) _setPolicyActive(address(task), false);
        uint48 beforeAt = task.lastTransitionAt();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        task.enable(data_);
        assertTrue(task.isEnabled(), "Failed enable retains enabled state");
        assertEq(task.lastTransitionAt(), beforeAt, "Failed enable retains timestamp");
    }

    function test_givenDisabledPolicy_whenNonemptyData_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0);
        vm.prank(admin);
        task.disable("");
        if (!active_) _setPolicyActive(address(task), false);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidData.selector);
        vm.prank(admin);
        task.enable(data_);
        assertFalse(task.isEnabled(), "Payload rejection retains disabled state");
        assertEq(task.lastTransitionAt(), beforeAt, "Payload rejection retains timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Payload rejection emits no logs");
    }

    function test_givenDisabledPolicy_whenPayloadBoundaries_reverts() public {
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"00", true);
        vm.prank(admin);
        task.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"01", true);
        vm.prank(admin);
        task.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(32), true);
        vm.prank(admin);
        task.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(256), true);
    }

    // Scenarios: RDTASK-ENABLE-L03.
    function test_givenInactivePolicy_whenEmptyEnable_reverts() public {
        _seedLifecycleRevenue();
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
        vm.prank(admin);
        task.enable("");
        assertFalse(task.isEnabled(), "Inactive policy stays disabled");
        assertEq(task.lastTransitionAt(), beforeAt, "Inactive enable preserves timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-ENABLE-L05.
    function test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts(address caller_) public {
        RevenueDistributorTask fresh = new RevenueDistributorTask(
            kernel,
            address(distributor),
            5_000_000
        );
        // A fresh policy has no cached ROLES; the reached external call returns no ABI word.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RDTASK-ENABLE-D06.
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
        task.enable("");
        assertFalse(task.isEnabled(), "Kernel drift prevents activation");
    }

    // Scenarios: RDTASK-ENABLE-D01, RDTASK-ENABLE-D02, RDTASK-ENABLE-D03.
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
        task.enable("");
        assertFalse(task.isEnabled(), "Unavailable service prevents activation");
        assertEq(task.lastTransitionAt(), beforeAt, "Failed activation preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Failed activation emits no logs");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-ENABLE-D01, RDTASK-ENABLE-D02, RDTASK-ENABLE-D03.
    function test_givenDistributorStateSeeds_whenActivation_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenUnavailableDistributor_whenActivation_reverts(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive disabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(true, false);
    }

    // Scenarios: RDTASK-ENABLE-P02.
    function test_givenRestoredDistributor_whenActivation_succeeds() public {
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        _setPolicyActive(address(distributor), true);
        vm.prank(admin);
        distributor.enable("");
        vm.prank(admin);
        task.enable("");
        assertTrue(task.isEnabled(), "Restored service permits activation");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDTASK-ENABLE-I02, RDTASK-ENABLE-L02, RDTASK-ENABLE-L04.
    function test_givenEnabled_whenAnyCallerEnables_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        task.enable(data_);
        assertTrue(task.isEnabled(), "Enabled guard preserves enabled state");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-ENABLE-A01, RDTASK-ENABLE-I03.
    function test_givenDisabled_whenCallerLacksAdmin_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        uint64 queueId = _seedTaskLifecycleQueue();
        vm.prank(admin);
        task.disable("");
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        task.enable(data_);
        assertFalse(task.isEnabled(), "Unauthorized enable leaves policy disabled");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-ENABLE-I01.
    function test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0 && data_.length <= 256);
        uint64 queueId = _seedTaskLifecycleQueue();
        vm.prank(admin);
        task.disable("");
        if (!active_) _setPolicyActive(address(task), false);
        bytes32 beforeState = _taskStateDigest(queueId);
        uint48 beforeAt = task.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributorTask.RevenueDistributorTask_InvalidData.selector);
        vm.prank(admin);
        task.enable(data_);
        assertFalse(task.isEnabled(), "Nonempty payload leaves policy disabled");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(task.lastTransitionAt(), beforeAt, "Rejected lifecycle call preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDTASK-ENABLE-L01.
    function test_givenPreviouslyEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        vm.prank(admin);
        task.disable("");
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _taskStateDigest(queueId);
        vm.expectEmit(address(task));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(task));
        emit IEnablerV2.Transition(caller_, true, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        task.enable("");
        assertTrue(task.isEnabled(), "Admin enables policy");
        assertEq(task.lastTransitionAt(), timestamp_, "Enable stores exact timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Enable emits exactly two lifecycle events");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDTASK-ENABLE-P01.
    function test_givenNeverEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedTaskLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        RevenueDistributorTask fresh = new RevenueDistributorTask(
            kernel,
            address(distributor),
            5_000_000
        );
        _setPolicyActive(address(fresh), true);
        assertEq(fresh.lastTransitionAt(), 0, "Fresh active policy has never transitioned");
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _taskStateDigest(queueId);
        vm.expectEmit(address(fresh));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(fresh));
        emit IEnablerV2.Transition(caller_, true, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        fresh.enable("");
        assertTrue(fresh.isEnabled(), "Fresh policy enables");
        assertEq(fresh.lastTransitionAt(), timestamp_, "First enable records timestamp");
        assertEq(fresh.gracePeriod(), 7 days, "First enable preserves default grace");
        assertEq(fresh.executionGasLimit(), 5_000_000, "First enable preserves gas limit");
        assertEq(fresh.nextAssetIndex(), 0, "First enable preserves zero cursor");
        assertEq(vm.getRecordedLogs().length, 2, "First enable emits exactly two lifecycle events");
        assertEq(
            _taskStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDTASK-ENABLE-A01, RDTASK-ENABLE-I01, RDTASK-ENABLE-I02, RDTASK-ENABLE-I03, RDTASK-ENABLE-L01, RDTASK-ENABLE-L02, RDTASK-ENABLE-L04, RDTASK-ENABLE-P01.
    function test_givenEnableBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenEnabled_whenAnyCallerEnables_reverts(address(0), hex"00", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenEnabled_whenAnyCallerEnables_reverts(address(0), hex"01", false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenCallerLacksAdmin_reverts(address(0), "", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenCallerLacksAdmin_reverts(address(0), new bytes(256), false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(hex"00", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(hex"00", false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(hex"01", true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(hex"01", false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(new bytes(32), true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(new bytes(32), false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(new bytes(256), true);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(new bytes(256), false);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenPreviouslyEnabled_whenAuthorizedAdminEnables(bob, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenPreviouslyEnabled_whenAuthorizedAdminEnables(bob, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenNeverEnabled_whenAuthorizedAdminEnables(bob, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
        test_givenNeverEnabled_whenAuthorizedAdminEnables(bob, type(uint48).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent enable seed");
    }
}
