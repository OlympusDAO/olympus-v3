// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";

contract RevenueDistributorConfigTimelockDisableTest is RevenueDistributorConfigTimelockTest {
    event Disabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    function test_whenPermittedCallerDisables_recordsTransitionAndPreservesQueue(
        bool useAdmin_,
        bool active_,
        uint48 timestamp_
    ) public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRoutes(address(token), 0, routes);
        _setPolicyActive(address(configTimelock), active_);

        address caller = useAdmin_ ? admin : emergency;
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);

        vm.expectEmit(address(configTimelock));
        emit Disabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(caller, false, "", timestamp_);
        vm.prank(caller);
        configTimelock.disable("");

        assertFalse(configTimelock.isEnabled(), "timelock disabled");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "transition timestamp");
        assertEq(configTimelock.getQueuedActionLength(actionId), 1, "queued action preserved");
    }

    function test_whenAlreadyDisabled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_
    ) public {
        _disablePolicy(address(configTimelock), emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenUnauthorizedCallerDisables_reverts(
        address caller_,
        bytes calldata data_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_givenEnabledPolicy_whenNonemptyDisableData_reverts(
        bytes memory data_,
        bool active_,
        bool adminCalls_
    ) public {
        vm.assume(data_.length > 0);
        _seedLifecycleRevenue();
        _setPolicyActive(address(configTimelock), active_);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData.selector
        );
        vm.prank(adminCalls_ ? admin : emergency);
        configTimelock.disable(data_);
        assertTrue(configTimelock.isEnabled(), "Invalid pause payload preserves enabled state");
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Invalid pause preserves timestamp");
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
        _setPolicyActive(address(configTimelock), active_);
        uint48 transitionAt = 2 days;
        vm.warp(transitionAt);
        vm.expectEmit(false, false, false, false, address(configTimelock));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(caller_, false, "", transitionAt);
        vm.prank(caller_);
        configTimelock.disable("");
        assertFalse(configTimelock.isEnabled(), "Authorized caller pauses policy");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "Pause records timestamp");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-DISABLE-L07.
    function test_givenNeverActivatedPolicy_whenAnyCallerDisables_reverts(address caller_) public {
        RevenueDistributorConfigTimelock fresh = _newTimelock();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        fresh.disable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RDCT-DISABLE-D01.
    function test_givenBrokenDistributor_whenEmergencyPauses_succeeds(bool active_) public {
        _seedLifecycleRevenue();
        _moveDistributorToDifferentKernel();
        vm.mockCallRevert(
            address(distributor),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSignature("Unavailable()")
        );
        _setPolicyActive(address(configTimelock), active_);
        vm.prank(emergency);
        configTimelock.disable("");
        assertFalse(configTimelock.isEnabled(), "Broken service cannot prevent emergency pause");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-DISABLE-I03, RDCT-DISABLE-L03, RDCT-DISABLE-L06.
    function test_givenDisabled_whenAnyCallerPauses_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);
        assertFalse(configTimelock.isEnabled(), "Already disabled policy remains disabled");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDCT-DISABLE-A03, RDCT-DISABLE-I04.
    function test_givenEnabled_whenCallerLacksPauseRoles_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(!roles.hasRole(caller_, EMERGENCY_ROLE));
        uint64 queueId = _seedLifecycleQueue();
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.disable(data_);
        assertTrue(configTimelock.isEnabled(), "Unauthorized pause preserves enabled state");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDCT-DISABLE-I01.
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
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData.selector
        );
        vm.prank(caller_);
        configTimelock.disable(data_);
        assertTrue(configTimelock.isEnabled(), "Invalid pause data preserves enabled state");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected lifecycle call preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected lifecycle call commits no logs");
    }

    // Scenarios: RDCT-DISABLE-L01, RDCT-DISABLE-L04, RDCT-DISABLE-L08, RDCT-DISABLE-P02.
    function test_givenEnabled_whenAuthorizedCallerPauses(
        address caller_,
        bool active_,
        bool emergencyOnly_,
        bool overlap_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, EMERGENCY_ROLE, emergencyOnly_, overlap_);
        _setPolicyActive(address(configTimelock), active_);
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        vm.expectEmit(address(configTimelock));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(caller_, false, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        configTimelock.disable("");
        assertFalse(configTimelock.isEnabled(), "Permitted authority pauses policy");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "Pause stores timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Pause emits exactly two lifecycle events");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDCT-DISABLE-A03, RDCT-DISABLE-I01, RDCT-DISABLE-I03, RDCT-DISABLE-I04, RDCT-DISABLE-L01, RDCT-DISABLE-L03, RDCT-DISABLE-L04, RDCT-DISABLE-L06, RDCT-DISABLE-L08, RDCT-DISABLE-P02.
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
