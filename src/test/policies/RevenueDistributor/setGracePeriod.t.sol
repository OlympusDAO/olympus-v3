// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";

import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

contract RevenueDistributorSetGracePeriodTest is RevenueDistributorTest {
    // Scenarios: RD-GRACE-P04.
    function test_whenAdminSetsPositiveGracePeriod_updatesValue(uint32 period_) public {
        vm.assume(period_ != 0);
        vm.assume(period_ != distributor.gracePeriod());
        uint48 transitionBefore = distributor.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        distributor.setGracePeriod(period_);

        assertEq(distributor.gracePeriod(), period_, "grace period equals input");
        assertEq(
            distributor.lastTransitionAt(),
            transitionBefore,
            "grace update preserves transition timestamp"
        );
    }

    function test_whenAdminSetsCurrentGracePeriod_emitsEvent() public {
        uint32 currentPeriod = distributor.gracePeriod();
        uint48 transitionBefore = distributor.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        distributor.setGracePeriod(currentPeriod);

        assertEq(distributor.gracePeriod(), currentPeriod, "grace period unchanged");
        assertEq(
            distributor.lastTransitionAt(),
            transitionBefore,
            "transition timestamp unchanged"
        );
    }

    // Scenarios: RD-GRACE-I03.
    function test_whenAdminSetsZeroGracePeriod_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        distributor.setGracePeriod(0);
    }

    function test_givenDisabled_whenGracePeriodSet_revertsBeforeAuthorization(
        address caller_,
        uint32 period_
    ) public {
        _disableDistributor();

        _expectNotEnabled();
        vm.prank(caller_);
        distributor.setGracePeriod(period_);
    }

    // Scenarios: RD-GRACE-A04.
    function test_givenEnabled_whenNonAdminSetsGracePeriod_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        distributor.setGracePeriod(period_);
    }

    function test_givenPolicyInactive_whenAdminSetsGracePeriod_reverts(uint32 period_) public {
        vm.assume(period_ != 0);
        _setPolicyActive(address(distributor), false);

        _expectPolicyInactive();
        vm.prank(admin);
        distributor.setGracePeriod(period_);

        assertEq(distributor.gracePeriod(), 7 days, "Inactive policy preserves grace period");
    }

    // Scenarios: RD-GRACE-L02, RD-GRACE-P06.
    function test_givenInactivePolicy_whenAdminChangesGrace_reverts(uint32 period_) public {
        _setPolicyActive(address(distributor), false);
        uint32 beforePeriod = distributor.gracePeriod();
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            )
        );
        vm.prank(admin);
        distributor.setGracePeriod(period_);
        assertEq(distributor.gracePeriod(), beforePeriod, "Inactive setter preserves grace");
        assertEq(distributor.lastTransitionAt(), beforeAt, "Inactive setter preserves timestamp");
        assertEq(vm.getRecordedLogs().length, 0, "Inactive setter emits no logs");
    }

    // Scenarios: RD-GRACE-P05.
    function test_givenCurrentGrace_whenAdminSetsSameValue(uint32 period_) public {
        uint64 queueId = _seedLifecycleQueue();
        period_ = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        vm.prank(admin);
        distributor.setGracePeriod(period_);
        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(distributor));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.recordLogs();
        vm.prank(admin);
        distributor.setGracePeriod(period_);
        assertEq(distributor.gracePeriod(), period_, "Same valid duration is preserved");
        assertEq(
            distributor.lastTransitionAt(),
            beforeAt,
            "Same duration preserves transition timestamp"
        );
        assertEq(
            _distributorStateDigest(queueId),
            beforeState,
            "Same duration preserves configuration, queue and custody"
        );
        assertEq(
            vm.getRecordedLogs().length,
            1,
            "Same valid duration still emits exactly one event"
        );
    }

    // Scenarios: RD-GRACE-L01.
    function test_givenDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        vm.prank(admin);
        distributor.disable("");

        bytes32 beforeState = _distributorStateDigest(queueId);
        uint48 beforeAt = distributor.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        distributor.setGracePeriod(period_);
        assertFalse(distributor.isEnabled(), "Disabled setter preserves disabled state");
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

    // Scenarios: RD-GRACE-L03.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
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
        distributor.setGracePeriod(period_);
        assertFalse(distributor.isEnabled(), "Disabled setter preserves disabled state");
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

    // Scenarios: RD-GRACE-L01, RD-GRACE-L03, RD-GRACE-P05.
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
