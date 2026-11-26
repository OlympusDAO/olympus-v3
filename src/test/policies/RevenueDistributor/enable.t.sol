// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {RevenueDistributorHarness} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorHarness.sol";

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorEnableTest is RevenueDistributorTest {
    function test_givenDisabled_whenAdminEnables_preservesConfiguration() public {
        _disableDistributor();
        uint48 transitionTime = distributor.lastTransitionAt() + 1;
        vm.warp(transitionTime);

        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(admin, true, "", transitionTime);
        vm.prank(admin);
        distributor.enable("");

        assertTrue(distributor.isEnabled(), "admin enables distributor");
        assertEq(distributor.lastTransitionAt(), transitionTime, "enable records timestamp");
        assertEq(
            distributor.configOperator(),
            address(configTimelock),
            "enable preserves config operator"
        );
    }

    function test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization(address caller_) public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        distributor.enable("");
    }

    function test_givenDisabled_whenNonAdminEnables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.prank(admin);
        distributor.disable("");

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        distributor.enable("");

        assertFalse(distributor.isEnabled(), "unauthorized enable preserves disabled state");
    }

    function test_givenPolicyInactiveAndDisabled_whenAdminEnables_reverts() public {
        vm.startPrank(admin);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        _expectPolicyInactive();
        distributor.enable("");
        vm.stopPrank();

        assertFalse(distributor.isEnabled(), "Inactive policy remains disabled");
    }

    function test_givenDisabled_whenAdminEnablesWithNonemptyData_reverts(
        bytes memory data_
    ) public {
        vm.assume(data_.length != 0);
        _disableDistributor();
        uint48 beforeTransition = distributor.lastTransitionAt();
        _expectInvalidData();
        vm.prank(admin);
        distributor.enable(data_);
        assertFalse(distributor.isEnabled(), "Invalid payload leaves policy disabled");
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

    function test_givenEnabledPolicy_whenAnyCallerEnablesWithData_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        if (!active_) _setPolicyActive(address(distributor), false);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        distributor.enable(data_);
        assertTrue(distributor.isEnabled(), "Failed enable retains enabled state");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Failed enable retains timestamp");
    }

    function test_givenDisabledPolicy_whenNonemptyData_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0);
        vm.prank(admin);
        distributor.disable("");
        if (!active_) _setPolicyActive(address(distributor), false);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_InvalidData.selector);
        vm.prank(admin);
        distributor.enable(data_);
        assertFalse(distributor.isEnabled(), "Payload rejection retains disabled state");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Payload rejection retains timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Payload rejection emits no logs");
    }

    function test_givenDisabledPolicy_whenPayloadBoundaries_reverts() public {
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"00", true);
        vm.prank(admin);
        distributor.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"01", true);
        vm.prank(admin);
        distributor.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(32), true);
        vm.prank(admin);
        distributor.enable("");
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(256), true);
    }

    // Scenarios: RD-ENABLE-L03.
    function test_givenInactivePolicy_whenEmptyEnable_reverts() public {
        _seedLifecycleRevenue();
        vm.prank(admin);
        distributor.disable("");
        _setPolicyActive(address(distributor), false);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            )
        );
        vm.prank(admin);
        distributor.enable("");
        assertFalse(distributor.isEnabled(), "Inactive policy stays disabled");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Inactive enable preserves timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RD-ENABLE-L05.
    function test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts(address caller_) public {
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
        // A fresh policy has no cached ROLES; the reached external call returns no ABI word.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RD-ENABLE-I02, RD-ENABLE-L02, RD-ENABLE-L04.
    function test_givenEnabled_whenAnyCallerEnables_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        distributor.enable(data_);
        assertTrue(distributor.isEnabled(), "Enabled guard preserves enabled state");
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

    // Scenarios: RD-ENABLE-A01, RD-ENABLE-I03.
    function test_givenDisabled_whenCallerLacksAdmin_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        uint64 queueId = _seedLifecycleQueue();
        vm.prank(admin);
        distributor.disable("");
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        distributor.enable(data_);
        assertFalse(distributor.isEnabled(), "Unauthorized enable leaves policy disabled");
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

    // Scenarios: RD-ENABLE-I01.
    function test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0 && data_.length <= 256);
        uint64 queueId = _seedLifecycleQueue();
        vm.prank(admin);
        distributor.disable("");
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_InvalidData.selector);
        vm.prank(admin);
        distributor.enable(data_);
        assertFalse(distributor.isEnabled(), "Nonempty payload leaves policy disabled");
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

    // Scenarios: RD-ENABLE-L01.
    function test_givenPreviouslyEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        vm.prank(admin);
        distributor.disable("");
        timestamp_ = uint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _distributorStateDigest(queueId);
        vm.expectEmit(address(distributor));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller_, true, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.enable("");
        assertTrue(distributor.isEnabled(), "Admin enables policy");
        assertEq(distributor.lastTransitionAt(), timestamp_, "Enable stores exact timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Enable emits exactly two lifecycle events");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RD-ENABLE-P01.
    function test_givenNeverEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
        _setPolicyActive(address(fresh), true);
        assertEq(fresh.lastTransitionAt(), 0, "Fresh active policy has never transitioned");
        timestamp_ = uint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _distributorStateDigest(queueId);
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
        assertEq(fresh.configOperator(), address(0), "First enable does not select a controller");
        assertEq(vm.getRecordedLogs().length, 2, "First enable emits exactly two lifecycle events");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RD-ENABLE-A01, RD-ENABLE-I01, RD-ENABLE-I02, RD-ENABLE-I03, RD-ENABLE-L01, RD-ENABLE-L02, RD-ENABLE-L04, RD-ENABLE-P01.
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
