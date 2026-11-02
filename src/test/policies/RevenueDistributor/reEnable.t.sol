// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
// Scenario amounts stay inline for accounting clarity.
// forge-lint: disable-start(literal-instead-of-constant)

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {Actions} from "src/Kernel.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorHarness} from "./fixtures/RevenueDistributorHarness.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorReEnableTest is RevenueDistributorTest {
    function test_givenDistributorDisabled_whenRevenueAdminReEnables_thenDistributionResumes()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(bob);
        distributor.reEnable();
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 3, "configured recipient receives its share");
        assertEq(token.balanceOf(address(treasury)), 7, "Treasury receives the remainder");
    }

    // Scenarios: RD-REENABLE-A02.
    function test_givenDistributorDisabled_whenUnauthorizedCallerReEnables_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != bob);
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        distributor.reEnable();
    }

    // given the distributor was disabled with a managed balance
    //  when admin re-enables it within grace and a caller distributes
    //   then the held balance follows the existing route
    function test_givenDisabled_whenReEnabled_thenStoredBalanceDistributes()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 10);
        vm.prank(emergency);
        distributor.disable("");
        vm.prank(admin);
        distributor.reEnable();

        vm.prank(bob);
        distributor.distribute(address(token));
        assertEq(token.balanceOf(alice), 3, "route survives disablement");
        assertEq(token.balanceOf(address(treasury)), 7, "residual reaches Treasury");
    }

    function test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts() public {
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(fresh));

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(admin);
        fresh.reEnable();

        assertFalse(fresh.isEnabled(), "never-enabled policy remains disabled");
        assertEq(fresh.lastTransitionAt(), 0, "never-enabled timestamp remains zero");
    }

    function test_givenEnabled_whenReEnabled_reverts() public {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(admin);
        distributor.reEnable();
    }

    function test_givenGraceDeadline_whenAdminReEnables_succeeds() public {
        vm.prank(admin);
        distributor.disable("");
        uint48 deadline = distributor.lastTransitionAt() + distributor.gracePeriod();
        vm.warp(deadline);

        vm.prank(admin);
        distributor.reEnable();

        assertTrue(distributor.isEnabled(), "grace deadline remains inclusive");
        assertEq(distributor.lastTransitionAt(), deadline, "deadline re-enable records timestamp");
    }

    function test_givenGraceExpired_whenAdminReEnables_reverts() public {
        vm.prank(admin);
        distributor.disable("");
        uint48 deadline = distributor.lastTransitionAt() + distributor.gracePeriod();
        vm.warp(uint256(deadline) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(admin);
        distributor.reEnable();

        assertFalse(distributor.isEnabled(), "expired re-enable preserves disabled state");
    }

    function test_givenPolicyInactiveAndDisabled_whenPermittedCallerReEnables_reverts(
        bool adminCalls_
    ) public {
        vm.startPrank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, bob);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();

        _expectPolicyInactive();
        vm.prank(adminCalls_ ? admin : bob);
        distributor.reEnable();

        assertFalse(distributor.isEnabled(), "Inactive policy remains disabled");
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
        distributor.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
        assertEq(distributor.lastTransitionAt(), disabledAt_, "Disable establishes grace origin");
        vm.warp(now_);
        vm.expectEmit(false, false, false, false, address(distributor));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.prank(caller_);
        distributor.reEnable();
        assertTrue(distributor.isEnabled(), "Permitted caller re-enables inside grace");
        assertEq(distributor.lastTransitionAt(), now_, "Re-enable records current timestamp");
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
        distributor.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
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
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Overflow leaves policy disabled");
        assertEq(distributor.lastTransitionAt(), disabledAt_, "Overflow preserves grace origin");
        assertEq(vm.getRecordedLogs().length, 0, "Overflow emits no transition");
        _assertLifecycleRevenue();
    }

    function test_givenInactivePolicy_whenPermittedReEnable_reverts(bool revenueAdmin_) public {
        _seedLifecycleRevenue();
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
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
        vm.prank(bob);
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Inactive policy stays disabled");
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Inactive re-enable preserves timestamp"
        );
        _assertLifecycleRevenue();
    }

    // Scenarios: RD-REENABLE-L05, RD-REENABLE-P01, RD-REENABLE-P02.
    function test_givenNeverEnabledPolicy_whenAnyCallerReEnables_reverts(
        address caller_,
        bool activated_
    ) public {
        RevenueDistributorHarness fresh = new RevenueDistributorHarness(kernel);
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
        distributor.setGracePeriod(grace_);
        _grantReEnableCaller(bob, !revenueAdmin_, revenueAdmin_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
        vm.warp(now_);
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(bob);
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Expired grace keeps policy disabled");
        assertEq(distributor.lastTransitionAt(), disabledAt_, "Expired grace preserves timestamp");
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

    // Scenarios: RD-REENABLE-L02, RD-REENABLE-L04.
    function test_givenEnabled_whenAnyCallerReEnables_reverts(
        address caller_,
        bool active_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        if (!active_) _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        distributor.reEnable();
        assertTrue(distributor.isEnabled(), "Enabled guard preserves enabled state");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RD-REENABLE-L03.
    function test_givenInactive_whenAuthorizedCallerReEnables_reverts(
        address caller_,
        bool revenueOnly_,
        bool overlap_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _grantLifecycleAuthority(caller_, REVENUE_DISTRIBUTOR_ADMIN_ROLE, revenueOnly_, overlap_);
        vm.prank(admin);
        distributor.disable("");
        _setPolicyActive(address(distributor), false);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            )
        );
        vm.prank(caller_);
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Inactive subject stays disabled");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RD-REENABLE-L01, RD-REENABLE-N02, RD-REENABLE-N03.
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
        distributor.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
        assertEq(distributor.lastTransitionAt(), disabledAt_, "Disable sets grace origin");
        vm.warp(now_);
        bytes32 beforeState = _distributorStateDigest(queueId);
        vm.expectEmit(address(distributor));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(distributor));
        emit IEnablerV2.Transition(caller_, true, "", now_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.reEnable();
        assertTrue(distributor.isEnabled(), "Permitted caller re-enables within inclusive grace");
        assertEq(distributor.lastTransitionAt(), now_, "Re-enable stores exact timestamp");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Successful re-enable preserves configuration, queue and accounting"
        );
        assertEq(vm.getRecordedLogs().length, 2, "Re-enable emits exactly two lifecycle events");
    }

    // Scenarios: RD-REENABLE-N01.
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
        distributor.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                uint256(disabledAt_) + grace_
            )
        );
        vm.prank(caller_);
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Unrepresentable grace leaves policy disabled");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RD-REENABLE-N04.
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
        distributor.setGracePeriod(grace_);
        vm.warp(disabledAt_);
        vm.prank(admin);
        distributor.disable("");
        vm.warp(now_);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(caller_);
        distributor.reEnable();
        assertFalse(distributor.isEnabled(), "Expired grace leaves policy disabled");
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Re-enable preserves configuration, queued actions and all payout state"
        );
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Rejected re-enable preserves transition timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Rejected re-enable commits no logs");
    }

    // Scenarios: RD-REENABLE-L01, RD-REENABLE-L02, RD-REENABLE-L03, RD-REENABLE-L04, RD-REENABLE-N01, RD-REENABLE-N02, RD-REENABLE-N03, RD-REENABLE-N04.
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
}
// forge-lint: disable-end(literal-instead-of-constant)
