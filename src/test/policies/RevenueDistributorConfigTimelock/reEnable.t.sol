// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {RevenueDistributorConfigTimelockTest} from "./RevenueDistributorConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";

contract RevenueDistributorConfigTimelockReEnableTest is RevenueDistributorConfigTimelockTest {
    uint48 internal constant DISABLED_AT = 1_000;

    event Enabled();
    event Transition(address indexed by, bool indexed enable, bytes data, uint48 at_);

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
    }

    function test_whenPermittedCallerReEnablesWithinGrace_recordsTransition(
        bool useAdmin_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = DISABLED_AT;
        // bound() guarantees that the result fits uint32.
        // forge-lint: disable-next-line(unsafe-typecast)
        elapsed_ = SafeCast.toUint32(bound(elapsed_, 0, configTimelock.gracePeriod()));
        vm.warp(disabledAt);
        _disablePolicy(address(configTimelock), emergency);
        address caller = useAdmin_ ? admin : alice;
        vm.warp(uint256(disabledAt) + elapsed_);
        // The bounded disabledAt and elapsed values keep the timestamp within uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 transitionAt = uint48(block.timestamp);

        vm.expectEmit(address(configTimelock));
        emit Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit Transition(caller, true, "", transitionAt);
        vm.prank(caller);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "timelock re-enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp");
    }

    function test_whenExactGraceDeadline_reenables() public {
        uint48 disabledAt = DISABLED_AT;
        vm.warp(disabledAt);
        _disablePolicy(address(configTimelock), emergency);
        uint48 deadline = disabledAt + configTimelock.gracePeriod();
        vm.warp(deadline);

        vm.prank(alice);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "deadline remains inside grace period");
        assertEq(configTimelock.lastTransitionAt(), deadline, "deadline transition recorded");
    }

    function test_whenNeverEnabled_reverts() public {
        RevenueDistributorConfigTimelock freshTimelock = _newActivatedTimelock();

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        freshTimelock.reEnable();

        assertFalse(freshTimelock.isEnabled(), "fresh timelock remains disabled");
        assertEq(freshTimelock.lastTransitionAt(), 0, "timestamp remains zero");
    }

    // Scenarios: RDCT-REENABLE-A02.
    function test_whenUnauthorizedCallerReEnables_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != alice);
        _disablePolicy(address(configTimelock), emergency);
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenAlreadyEnabled_revertsBeforeAuthorization(address caller_) public {
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.reEnable();

        assertTrue(configTimelock.isEnabled(), "timelock remains enabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
    }

    function test_whenGracePeriodExpired_reverts(uint48 now_) public {
        uint48 disabledAt = DISABLED_AT;
        vm.warp(disabledAt);
        _disablePolicy(address(configTimelock), emergency);
        uint48 deadline = disabledAt + configTimelock.gracePeriod();
        // bound() guarantees that the result fits uint48.
        // forge-lint: disable-next-line(unsafe-typecast)
        now_ = SafeCast.toUint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(alice);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), disabledAt, "timestamp unchanged");
    }

    function test_givenOwnPolicyInactive_whenPermittedCallerReEnables_reverts(
        bool useAdmin_
    ) public {
        _disablePolicy(address(configTimelock), emergency);
        _setPolicyActive(address(configTimelock), false);
        address caller = useAdmin_ ? admin : alice;

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyNotActive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(caller);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Inactive timelock remains disabled");
    }

    function test_whenDistributorKernelMismatches_reverts(bool useAdmin_) public {
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
        vm.prank(useAdmin_ ? admin : alice);
        configTimelock.reEnable();

        assertFalse(configTimelock.isEnabled(), "timelock remains disabled");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "timestamp unchanged");
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
        configTimelock.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
        assertEq(
            configTimelock.lastTransitionAt(),
            disabledAt_,
            "Disable establishes grace origin"
        );
        vm.warp(now_);
        vm.expectEmit(false, false, false, false, address(configTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        configTimelock.reEnable();
        assertTrue(configTimelock.isEnabled(), "Permitted caller re-enables inside grace");
        assertEq(configTimelock.lastTransitionAt(), now_, "Re-enable records current timestamp");
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
        configTimelock.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
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
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Overflow leaves policy disabled");
        assertEq(configTimelock.lastTransitionAt(), disabledAt_, "Overflow preserves grace origin");
        assertEq(vm.getRecordedLogs().length, 0, "Overflow emits no transition");
        _assertLifecycleRevenue();
    }

    function test_givenInactivePolicy_whenPermittedReEnable_reverts(bool revenueAdmin_) public {
        _seedLifecycleRevenue();
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
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
        vm.prank(bob);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Inactive policy stays disabled");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Inactive re-enable preserves timestamp"
        );
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-REENABLE-L05, RDCT-REENABLE-P01, RDCT-REENABLE-P02.
    function test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts(
        address caller_,
        bool activated_
    ) public {
        RevenueDistributorConfigTimelock fresh = _newTimelock();
        _setPolicyActive(address(fresh), activated_);
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
        configTimelock.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(bob);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Expired grace keeps policy disabled");
        assertEq(
            configTimelock.lastTransitionAt(),
            disabledAt_,
            "Expired grace preserves timestamp"
        );
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-REENABLE-D06.
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
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Kernel drift prevents activation");
    }

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
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Unavailable service prevents activation");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Failed activation preserves timestamp"
        );
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

    // Scenarios: RDCT-REENABLE-P03.
    function test_givenRestoredDistributor_whenActivation_succeeds() public {
        test_givenUnavailableDistributor_whenActivation_reverts(false, false);
        _setPolicyActive(address(distributor), true);
        _enablePolicy(address(distributor));
        vm.prank(admin);
        configTimelock.reEnable();
        assertTrue(configTimelock.isEnabled(), "Restored service permits activation");
        _assertLifecycleRevenue();
    }

    // Scenarios: RDCT-REENABLE-L02, RDCT-REENABLE-L04.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(
        address caller_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _setPolicyActive(address(configTimelock), active_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        configTimelock.reEnable();
        assertTrue(configTimelock.isEnabled(), "Enabled guard preserves enabled state");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-L03.
    function test_givenInactive_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), false);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_PolicyNotActive
                    .selector,
                address(configTimelock)
            )
        );
        vm.prank(caller_);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Inactive subject stays disabled");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-D01, RDCT-REENABLE-L01, RDCT-REENABLE-N02, RDCT-REENABLE-N03.
    function test_givenRepresentableDeadline_whenAuthorizedCallerReEnables(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(bound(disabledAt_, 1, uint256(type(uint48).max) - grace_));
        now_ = SafeCast.toUint48(bound(now_, disabledAt_, uint256(disabledAt_) + grace_));
        vm.prank(admin);
        configTimelock.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
        assertEq(configTimelock.lastTransitionAt(), disabledAt_, "Disable sets grace origin");
        vm.warp(now_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        vm.expectEmit(address(configTimelock));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.recordLogs();
        vm.prank(caller_);
        configTimelock.reEnable();
        assertTrue(
            configTimelock.isEnabled(),
            "Permitted caller re-enables within inclusive grace"
        );
        assertEq(configTimelock.lastTransitionAt(), now_, "Re-enable stores exact timestamp");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Successful re-enable preserves configuration, queue and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 2, "Re-enable emits exactly two lifecycle events");
    }

    // Scenarios: RDCT-REENABLE-N01.
    function test_givenOverflowingDeadline_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max)
        );
        vm.prank(admin);
        configTimelock.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt_) + grace_
            )
        );
        vm.prank(caller_);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Unrepresentable grace leaves policy disabled");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-N04.
    function test_givenExpiredDeadline_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        uint32 grace_,
        uint48 disabledAt_,
        uint48 now_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        grace_ = SafeCast.toUint32(bound(grace_, 1, type(uint32).max));
        disabledAt_ = SafeCast.toUint48(
            bound(disabledAt_, 1, uint256(type(uint48).max) - grace_ - 1)
        );
        uint48 deadline = disabledAt_ + grace_;
        now_ = SafeCast.toUint48(bound(now_, uint256(deadline) + 1, type(uint48).max));
        vm.prank(admin);
        configTimelock.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        _disablePolicy(address(configTimelock), admin);
        vm.warp(now_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Expired grace leaves policy disabled");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-D01, RDCT-REENABLE-L01, RDCT-REENABLE-L02, RDCT-REENABLE-L03, RDCT-REENABLE-L04, RDCT-REENABLE-N01, RDCT-REENABLE-N02, RDCT-REENABLE-N03, RDCT-REENABLE-N04.
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

    // Scenarios: RDCT-REENABLE-D02, RDCT-REENABLE-D03, RDCT-REENABLE-D04.
    function test_givenUnavailableDistributor_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_,
        bool distributorActive_,
        bool distributorEnabled_
    ) public {
        vm.assume(!distributorActive_ || !distributorEnabled_);
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _disablePolicy(address(configTimelock), admin);
        _setRevenuePolicyLifecycle(address(distributor), distributorActive_, distributorEnabled_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(distributor)
            )
        );
        vm.prank(caller_);
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Unavailable dependency retains disabled subject");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-D02, RDCT-REENABLE-D03, RDCT-REENABLE-D04.
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
            _enablePolicy(address(distributor));
        }
        bytes32 beforeAccounting = _revenueAccountingDigest();
        vm.prank(caller_);
        configTimelock.reEnable();
        assertTrue(configTimelock.isEnabled(), "Restoration permits the same authorized retry");
        assertEq(
            _revenueAccountingDigest(),
            beforeAccounting,
            "Restored retry preserves all accounting"
        );
    }

    // Scenarios: RDCT-REENABLE-D02, RDCT-REENABLE-D03, RDCT-REENABLE-D04.
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

    // Scenarios: RDCT-REENABLE-D05.
    function test_givenDistributorKernelDrift_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        _disablePolicy(address(configTimelock), admin);
        Kernel otherKernel = _moveDistributorToDifferentKernel();
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
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
        configTimelock.reEnable();
        assertFalse(configTimelock.isEnabled(), "Kernel drift prevents re-enable");
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RDCT-REENABLE-D05.
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
