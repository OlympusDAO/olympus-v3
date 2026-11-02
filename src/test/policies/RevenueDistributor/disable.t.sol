// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorDisableTest is RevenueDistributorTest {
    function test_whenPermittedCallerDisables_preservesConfiguration(bool adminCalls_) public {
        address caller = adminCalls_ ? admin : emergency;
        uint48 transitionTime = distributor.lastTransitionAt() + 1;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller, false, "", transitionTime);
        vm.prank(caller);
        distributor.disable("");

        assertFalse(distributor.isEnabled(), "permitted caller disables distributor");
        assertEq(distributor.lastTransitionAt(), transitionTime, "disable records timestamp");
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "disable preserves config operator"
        );
    }

    function test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization(
        address caller_
    ) public {
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.disable("");
    }

    function test_givenEnabled_whenUnauthorizedCallerDisables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        distributor.disable("");

        assertTrue(distributor.isEnabled(), "unauthorized disable preserves enabled state");
    }

    function test_givenPolicyInactive_whenPermittedCallerDisables_succeeds(
        bool adminCalls_
    ) public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));

        vm.prank(adminCalls_ ? admin : emergency);
        distributor.disable("");

        assertFalse(distributor.isEnabled(), "Kernel inactivity does not gate inherited disable");
    }

    function test_whenPermittedCallerDisablesWithNonemptyData_reverts(
        bool adminCalls_,
        bytes memory data_
    ) public {
        vm.assume(data_.length != 0);
        uint48 beforeTransition = distributor.lastTransitionAt();
        _expectInvalidData();
        vm.prank(adminCalls_ ? admin : emergency);
        distributor.disable(data_);
        assertTrue(distributor.isEnabled(), "Invalid payload leaves policy enabled");
        assertEq(
            distributor.lastTransitionAt(),
            beforeTransition,
            "Invalid payload preserves transition timestamp"
        );
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "Invalid payload preserves configuration"
        );
    }

    function test_givenEnabledPolicy_whenNonemptyDisableData_reverts(
        bytes memory data_,
        bool active_,
        bool adminCalls_
    ) public {
        vm.assume(data_.length > 0);
        _seedLifecycleRevenue();
        if (!active_) _setPolicyActive(address(distributor), false);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_InvalidData.selector);
        vm.prank(adminCalls_ ? admin : emergency);
        distributor.disable(data_);
        assertTrue(distributor.isEnabled(), "Invalid pause payload preserves enabled state");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Invalid pause preserves timestamp");
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
        if (!active_) _setPolicyActive(address(distributor), false);
        uint48 transitionAt = 2 days;
        vm.warp(transitionAt);
        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller_, false, "", transitionAt);
        vm.prank(caller_);
        distributor.disable("");
        assertFalse(distributor.isEnabled(), "Authorized caller pauses policy");
        assertEq(distributor.lastTransitionAt(), transitionAt, "Pause records timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RD-DISABLE-L07.
    function test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts(address caller_) public {
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RD-DISABLE-I03, RD-DISABLE-L03, RD-DISABLE-L06.
    function test_givenDisabled_whenAnyCallerPauses_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        vm.prank(admin);
        distributor.disable("");
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.disable(data_);
        assertFalse(distributor.isEnabled(), "Already disabled policy remains disabled");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RD-DISABLE-A03, RD-DISABLE-I04.
    function test_givenEnabled_whenCallerLacksPauseRoles_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, EMERGENCY_ROLE));
        uint64 queueId = _seedLifecycleQueue();
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        distributor.disable(data_);
        assertTrue(distributor.isEnabled(), "Unauthorized pause preserves enabled state");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RD-DISABLE-I01.
    function test_givenEnabled_whenAuthorizedPauseDataNonempty_reverts(
        address caller_,
        bytes memory data_,
        bool active_,
        bool emergencyOnly_,
        bool overlap_
    ) public {
        vm.assume(data_.length > 0 && data_.length <= 256);
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, EMERGENCY_ROLE, emergencyOnly_, overlap_);
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_InvalidData.selector);
        vm.prank(caller_);
        distributor.disable(data_);
        assertTrue(distributor.isEnabled(), "Invalid pause data preserves enabled state");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RD-DISABLE-L01, RD-DISABLE-L04, RD-DISABLE-L08, RD-DISABLE-P02.
    function test_givenEnabled_whenAuthorizedCallerPauses(
        address caller_,
        bool active_,
        bool emergencyOnly_,
        bool overlap_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, EMERGENCY_ROLE, emergencyOnly_, overlap_);
        if (!active_) _setPolicyActive(address(distributor), false);
        timestamp_ = uint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _distributorStateDigest(queueId);
        vm.expectEmit(address(distributor));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller_, false, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.disable("");
        assertFalse(distributor.isEnabled(), "Permitted authority pauses policy");
        assertEq(distributor.lastTransitionAt(), timestamp_, "Pause stores timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Pause emits exactly two lifecycle events");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RD-DISABLE-A03, RD-DISABLE-I01, RD-DISABLE-I03, RD-DISABLE-I04, RD-DISABLE-L01, RD-DISABLE-L03, RD-DISABLE-L04, RD-DISABLE-L06, RD-DISABLE-L08, RD-DISABLE-P02.
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
