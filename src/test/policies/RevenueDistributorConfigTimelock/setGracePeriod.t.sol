// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockSetGracePeriodTest is RevenueDistributorTest {
    // Scenarios: RDCT-GRACE-P04.
    function test_whenBoundaryPeriodsSet_storesEachValue() public {
        uint32[2] memory periods = [uint32(1), type(uint32).max];

        // The fixed two-value loop exercises each semantic boundary.
        // forge-lint: disable-start(calls-loop)
        for (uint256 i; i < periods.length; ++i) {
            vm.prank(admin);
            configTimelock.setGracePeriod(periods[i]);
            assertEq(configTimelock.gracePeriod(), periods[i], "boundary period stored");
        }
        // forge-lint: disable-end(calls-loop)
    }

    // Scenarios: RDCT-GRACE-P04.
    function test_whenAdminSetsNonzeroPeriod_storesValue(uint32 period_) public {
        // bound() guarantees that the result fits uint32.
        // forge-lint: disable-next-line(unsafe-typecast)
        period_ = uint32(bound(period_, 1, type(uint32).max));
        vm.assume(period_ != configTimelock.gracePeriod());
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), period_, "grace period stored");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    function test_whenAdminSetsCurrentGracePeriod_emitsEvent() public {
        uint32 currentPeriod = configTimelock.gracePeriod();
        uint48 transitionAt = configTimelock.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        configTimelock.setGracePeriod(currentPeriod);

        assertEq(configTimelock.gracePeriod(), currentPeriod, "grace period unchanged");
        assertEq(configTimelock.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: RDCT-GRACE-I03.
    function test_whenAdminSetsZeroPeriod_reverts() public {
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        configTimelock.setGracePeriod(0);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    function test_whenDisabled_revertsBeforeAuthorizationAndValidation(
        address caller_,
        uint32 period_
    ) public {
        _disablePolicy(address(configTimelock), emergency);
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // Scenarios: RDCT-GRACE-A04.
    function test_whenNonAdminSetsPeriod_reverts(address caller_, uint32 period_) public {
        vm.assume(caller_ != admin);
        uint32 gracePeriod = configTimelock.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        configTimelock.setGracePeriod(period_);

        assertEq(configTimelock.gracePeriod(), gracePeriod, "grace period unchanged");
    }

    // Scenarios: RDCT-GRACE-L02, RDCT-GRACE-P06.
    function test_givenInactivePolicy_whenAdminChangesGrace_reverts(uint32 period_) public {
        _setPolicyActive(address(configTimelock), false);
        uint32 beforePeriod = configTimelock.gracePeriod();
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
        vm.prank(admin);
        configTimelock.setGracePeriod(period_);
        assertEq(configTimelock.gracePeriod(), beforePeriod, "Inactive setter preserves grace");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Inactive setter preserves timestamp"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Inactive setter emits no logs");
    }

    // Scenarios: RDCT-GRACE-P05.
    function test_givenCurrentGrace_whenAdminSetsSameValue(uint32 period_) public {
        uint64 queueId = _seedLifecycleQueue();
        period_ = SafeCast.toUint32(bound(period_, 1, type(uint32).max));
        vm.prank(admin);
        configTimelock.setGracePeriod(period_);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(configTimelock));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.recordLogs();
        vm.prank(admin);
        configTimelock.setGracePeriod(period_);
        assertEq(configTimelock.gracePeriod(), period_, "Same valid duration is preserved");
        assertEq(
            configTimelock.lastTransitionAt(),
            beforeAt,
            "Same duration preserves transition timestamp"
        );
        assertEq(
            _timelockStateDigest(queueId),
            beforeState,
            "Same duration preserves configuration, queue and custody"
        );
        assertEq(
            vm.getRecordedLogs().length,
            1,
            "Same valid duration still emits exactly one event"
        );
    }

    // Scenarios: RDCT-GRACE-L01.
    function test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
        _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), true);
        bytes32 beforeState = _timelockStateDigest(queueId);
        uint48 beforeAt = configTimelock.lastTransitionAt();
        vm.recordLogs();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        configTimelock.setGracePeriod(period_);
        assertFalse(configTimelock.isEnabled(), "Disabled setter preserves disabled state");
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

    // Scenarios: RDCT-GRACE-L03.
    function test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_,
        uint32 period_
    ) public {
        uint64 queueId = _seedLifecycleQueue();
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
        configTimelock.setGracePeriod(period_);
        assertFalse(configTimelock.isEnabled(), "Disabled setter preserves disabled state");
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

    // Scenarios: RDCT-GRACE-L01, RDCT-GRACE-L03, RDCT-GRACE-P05.
    function test_givenGraceSetterBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenCurrentGrace_whenAdminSetsSameValue(1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenCurrentGrace_whenAdminSetsSameValue(type(uint32).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), 0);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), type(uint32).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), 0);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), 1);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
        test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts(address(0), type(uint32).max);
        assertTrue(vm.revertToState(checkpoint), "Restore independent grace setter seed");
    }

    // Scenarios: RDCT-GRACE-L04.
    function test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts(
        address caller_,
        bool enabled_,
        uint32 period_
    ) public {
        if (!enabled_) _disablePolicy(address(configTimelock), admin);
        _setPolicyActive(address(configTimelock), false);
        vm.etch(address(configTimelock.ROLES()), hex"fe");
        uint32 beforePeriod = configTimelock.gracePeriod();
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
        configTimelock.setGracePeriod(period_);
        assertEq(configTimelock.gracePeriod(), beforePeriod, "Rejected setter preserves period");
        assertEq(configTimelock.lastTransitionAt(), beforeAt, "Rejected setter preserves history");
        assertEq(vm.getRecordedLogs().length, 0, "Rejected setter commits no logs");
    }
}
