// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";

contract RevenueDistributorConfigTimelockEnableTest is RevenueDistributorConfigTimelockTest {
    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    function test_whenAdminEnablesDisabledPolicy_recordsTransition(uint48 timestamp_) public {
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        _disablePolicy(address(configTimelock), emergency);
        uint64 nextActionId = configTimelock.nextActionId();
        vm.warp(timestamp_);

        vm.expectEmit(address(configTimelock));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(admin, true, "", timestamp_);
        vm.prank(admin);
        configTimelock.enable("");

        assertTrue(configTimelock.isEnabled(), "timelock enabled");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "transition timestamp");
        assertEq(configTimelock.nextActionId(), nextActionId, "queue state preserved");
    }

    function test_whenAlreadyEnabled_revertsBeforeAuthorization(
        address caller_,
        bytes calldata data_
    ) public {
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.enable(data_);

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenNonAdminEnables_reverts(address caller_, bytes calldata data_) public {
        vm.assume(caller_ != admin);
        _disablePolicy(address(configTimelock), emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        configTimelock.enable(data_);

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenDistributorKernelMismatches_reverts() public {
        _disablePolicy(address(configTimelock), emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();
        Kernel otherKernel = _moveDistributorToDifferentKernel();

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(distributor),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(admin);
        configTimelock.enable("");

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenNeverEnabled_adminCanEnable() public {
        RevenueDistributorConfigTimelock freshTimelock = _newActivatedTimelock();

        vm.prank(admin);
        freshTimelock.enable("");

        assertTrue(freshTimelock.isEnabled(), "fresh timelock enabled");
        assertEq(freshTimelock.lastTransitionAt(), block.timestamp, "transition recorded");
    }

    function test_givenEnabledPolicy_whenAnyCallerEnablesWithData_reverts(
        address caller_,
        bool active_,
        bytes memory data_
    ) public {
        _setPolicyActive(address(configTimelock), active_);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.enable(data_);
        assertTrue(configTimelock.isEnabled(), "Failed enable retains enabled state");
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Failed enable retains timestamp");
    }

    function test_givenDisabledPolicy_whenNonemptyData_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0);
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), active_);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData.selector
        );
        vm.prank(admin);
        configTimelock.enable(data_);
        assertFalse(configTimelock.isEnabled(), "Payload rejection retains disabled state");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Payload rejection retains timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Payload rejection emits no logs");
    }

    function test_givenDisabledPolicy_whenPayloadBoundaries_reverts() public {
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"00", true);
        _enablePolicy(address(configTimelock));
        test_givenDisabledPolicy_whenNonemptyData_reverts(hex"01", true);
        _enablePolicy(address(configTimelock));
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(32), true);
        _enablePolicy(address(configTimelock));
        test_givenDisabledPolicy_whenNonemptyData_reverts(new bytes(256), true);
    }

    // Scenarios: RDCT-ENABLE-L03.
    function test_givenInactivePolicy_whenEmptyEnable_reverts() public {
        _seedLifecycleRevenue();
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), false);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyNotActive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(admin);
        configTimelock.enable("");
        assertFalse(configTimelock.isEnabled(), "Inactive policy stays disabled");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Inactive enable preserves timestamp"
        );
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-ENABLE-L05.
    function test_givenNeverActivatedPolicy_whenAnyCallerEnables_reverts(address caller_) public {
        RevenueDistributorConfigTimelock fresh = _newTimelock();
        // A fresh policy has no cached ROLES; the reached external call returns no ABI word.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        fresh.enable("");
        assertFalse(fresh.isEnabled(), "Fresh policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "Fresh policy records no transition");
    }

    // Scenarios: RDCT-ENABLE-D05, RDCT-ENABLE-D06.
    function test_givenDistributorKernelDrift_whenActivation_reverts(
        bool distributorActive_
    ) public {
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(distributor), distributorActive_);
        Kernel otherKernel = _moveDistributorToDifferentKernel();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(distributor),
                address(kernel),
                address(otherKernel)
            )
        );
        vm.prank(admin);
        configTimelock.enable("");
        assertFalse(configTimelock.isEnabled(), "Kernel drift prevents activation");
    }

    // Scenarios: RDCT-ENABLE-D02, RDCT-ENABLE-D03, RDCT-ENABLE-D04.
    function test_givenUnavailableDistributor_whenActivation_reverts(
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(!distributorActive_ || !distributorEnabled_);
        _seedLifecycleRevenue();
        _disablePolicy(address(configTimelock), admin);
        if (!distributorEnabled_) {
            _disablePolicy(address(distributor), admin);
        }
        _setPolicyActive(address(distributor), distributorActive_);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(admin);
        configTimelock.enable("");
        assertFalse(configTimelock.isEnabled(), "Unavailable service prevents activation");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Failed activation preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Failed activation emits no logs");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-ENABLE-D02, RDCT-ENABLE-D03, RDCT-ENABLE-D04.
    function test_givenDistributorStateSeeds_whenActivation_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenUnavailableDistributor_whenActivation_reverts(false, true);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive enabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        assertTrue(vm.revertToState(checkpoint), "Restore inactive disabled dependency");
        test_givenUnavailableDistributor_whenActivation_reverts(true, false);
    }

    // Scenarios: RDCT-ENABLE-P02.
    function test_givenRestoredDistributor_whenActivation_succeeds() public {
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        _setPolicyActive(address(distributor), true);
        vm.prank(admin);
        distributor.enable("");
        vm.prank(admin);
        configTimelock.enable("");
        assertTrue(configTimelock.isEnabled(), "Restored service permits activation");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-ENABLE-I02, RDCT-ENABLE-L02, RDCT-ENABLE-L04.
    function test_givenEnabled_whenAnyCallerEnables_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.enable(data_);
        assertTrue(configTimelock.isEnabled(), "Enabled guard preserves enabled state");
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

    // Scenarios: RDCT-ENABLE-A01, RDCT-ENABLE-I03.
    function test_givenDisabled_whenCallerLacksAdmin_reverts(
        address caller_,
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        uint64 queueId = _seedLifecycleQueue();
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        configTimelock.enable(data_);
        assertFalse(configTimelock.isEnabled(), "Unauthorized enable leaves policy disabled");
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

    // Scenarios: RDCT-ENABLE-I01.
    function test_givenDisabled_whenAuthorizedEnableDataNonempty_reverts(
        bytes memory data_,
        bool active_
    ) public {
        vm.assume(data_.length > 0 && data_.length <= 256);
        uint64 queueId = _seedLifecycleQueue();
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            IRevenueDistributorConfigTimelock.RevenueDistributorConfigTimelock_InvalidData.selector
        );
        vm.prank(admin);
        configTimelock.enable(data_);
        assertFalse(configTimelock.isEnabled(), "Nonempty payload leaves policy disabled");
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

    // Scenarios: RDCT-ENABLE-D01, RDCT-ENABLE-L01.
    function test_givenPreviouslyEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        _disablePolicy(address(configTimelock), admin);
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        vm.expectEmit(address(configTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(caller_, true, "", timestamp_);
        vm.recordLogs();
        vm.prank(caller_);
        configTimelock.enable("");
        assertTrue(configTimelock.isEnabled(), "Admin enables policy");
        assertEq(configTimelock.lastTransitionAt(), timestamp_, "Enable stores exact timestamp");
        assertEq(vm.getRecordedLogs().length, 2, "Enable emits exactly two lifecycle events");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDCT-ENABLE-P01.
    function test_givenNeverEnabled_whenAuthorizedAdminEnables(
        address caller_,
        uint48 timestamp_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, ADMIN_ROLE, false, false);
        RevenueDistributorConfigTimelock fresh = _newActivatedTimelock();
        assertEq(fresh.lastTransitionAt(), 0, "Fresh active policy has never transitioned");
        timestamp_ = SafeCast.toUint48(bound(timestamp_, 1, type(uint48).max));
        vm.warp(timestamp_);
        bytes32 beforeState = _timelockStateDigest(queueId);
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
        assertEq(fresh.nextActionId(), 1, "First enable creates no queued action");
        assertEq(vm.getRecordedLogs().length, 2, "First enable emits exactly two lifecycle events");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Lifecycle preserves configuration, queue, raw obligations and custody"
        );
    }

    // Scenarios: RDCT-ENABLE-A01, RDCT-ENABLE-D01, RDCT-ENABLE-I01, RDCT-ENABLE-I02, RDCT-ENABLE-I03, RDCT-ENABLE-L01, RDCT-ENABLE-L02, RDCT-ENABLE-L04, RDCT-ENABLE-P01.
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
