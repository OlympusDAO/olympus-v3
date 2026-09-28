// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";
import {IYieldRepurchaseFacilityConfigTimelock} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityConfigTimelock.sol";

// Contracts
import {Actions, Kernel, Module, Permissions, Policy} from "src/Kernel.sol";
import {YieldRepurchaseFacilityV2} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2.sol";
import {YieldRepurchaseFacilityConfigTimelock} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock.sol";

import {YieldRepurchaseFacilityConfigTimelockTestBase} from "src/test/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityConfigTimelock/YieldRepurchaseFacilityConfigTimelockTestBase.sol";

contract YieldRepurchaseFacilityConfigTimelockTests_Constructor is
    YieldRepurchaseFacilityConfigTimelockTestBase
{
    // constructor
    // given the kernel address is zero
    //  when deploying the timelock
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_InvalidAddress("kernel")
    function test_constructor_givenZeroKernel_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityConfigTimelock
                    .IYieldRepurchaseFacilityConfigTimelock_InvalidAddress
                    .selector,
                "kernel"
            )
        );
        new YieldRepurchaseFacilityConfigTimelock(
            Kernel(address(0)),
            configTimelockDelay,
            gracePeriod
        );
    }

    // constructor
    // given the initial delay is below MIN_TIMELOCK_DELAY
    //  when deploying the timelock with any such delay
    //   then it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    function test_constructor_givenDelayBelowMinimum_reverts(uint48 delay_) public {
        uint48 minDelay = configTimelock.MIN_TIMELOCK_DELAY();
        delay_ = uint48(bound(delay_, 0, minDelay - 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                minDelay,
                configTimelock.MAX_TIMELOCK_DELAY()
            )
        );
        new YieldRepurchaseFacilityConfigTimelock(kernel, delay_, gracePeriod);
    }

    // constructor
    // given the initial delay is above MAX_TIMELOCK_DELAY
    //  when deploying the timelock with any such delay
    //   then it reverts with ITimelockBatchQueue_TimelockDelayInvalid
    function test_constructor_givenDelayAboveMaximum_reverts(uint48 delay_) public {
        uint48 maxDelay = configTimelock.MAX_TIMELOCK_DELAY();
        delay_ = uint48(bound(delay_, uint256(maxDelay) + 1, type(uint48).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockBatchQueue.ITimelockBatchQueue_TimelockDelayInvalid.selector,
                delay_,
                configTimelock.MIN_TIMELOCK_DELAY(),
                maxDelay
            )
        );
        new YieldRepurchaseFacilityConfigTimelock(kernel, delay_, gracePeriod);
    }

    // constructor
    // given the initial delay is exactly MIN_TIMELOCK_DELAY
    //  when deploying the timelock
    //   then it succeeds (inclusive boundary)
    function test_constructor_givenDelayAtMinimum_succeeds() public {
        YieldRepurchaseFacilityConfigTimelock timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelock.MIN_TIMELOCK_DELAY(),
            gracePeriod
        );

        assertEq(timelock.timelockDelay(), timelock.MIN_TIMELOCK_DELAY(), "timelock delay");
    }

    // constructor
    // given the initial delay is exactly MAX_TIMELOCK_DELAY
    //  when deploying the timelock
    //   then it succeeds (inclusive boundary)
    function test_constructor_givenDelayAtMaximum_succeeds() public {
        YieldRepurchaseFacilityConfigTimelock timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelock.MAX_TIMELOCK_DELAY(),
            gracePeriod
        );

        assertEq(timelock.timelockDelay(), timelock.MAX_TIMELOCK_DELAY(), "timelock delay");
    }

    // constructor
    // given the grace period is zero
    //  when deploying the timelock
    //   then it reverts with GracePeriod_ZeroPeriod
    function test_constructor_givenZeroGracePeriod_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        new YieldRepurchaseFacilityConfigTimelock(kernel, configTimelockDelay, 0);
    }

    // constructor
    // given the grace period is at or above MAX_GRACE_PERIOD
    //  when deploying the timelock
    //   then it reverts with IYieldRepurchaseFacilityConfigTimelock_GracePeriodTooLong
    function test_constructor_givenGracePeriodAtOrAboveMax_reverts(uint32 gracePeriod_) public {
        gracePeriod_ = uint32(bound(gracePeriod_, 7 days, type(uint32).max));

        vm.expectRevert(
            IYieldRepurchaseFacilityConfigTimelock
                .IYieldRepurchaseFacilityConfigTimelock_GracePeriodTooLong
                .selector
        );
        new YieldRepurchaseFacilityConfigTimelock(kernel, configTimelockDelay, gracePeriod_);
    }

    // constructor
    // given valid parameters
    //  when deploying the timelock
    //   then the delay, grace period, next action id, and version constants are set,
    //   and the configuration events are emitted
    function test_constructor_givenValidParams_setsInitialState() public {
        uint48 delay = 2 days;
        uint32 grace = 5 days;

        // The grace window is configured by the ReEnablerGracePeriod base before the
        // TimelockBatchQueue base sets the delay, so the events arrive in that order.
        vm.expectEmit(false, false, false, true);
        emit IGracePeriod.GracePeriodSet(grace);
        vm.expectEmit(false, false, false, true);
        emit ITimelockBatchQueue.TimelockDelaySet(delay);
        YieldRepurchaseFacilityConfigTimelock timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            delay,
            grace
        );

        assertEq(timelock.timelockDelay(), delay, "timelock delay");
        assertEq(timelock.gracePeriod(), grace, "grace period");
        assertEq(timelock.nextActionId(), 1, "next action id");
        assertEq(timelock.MIN_TIMELOCK_DELAY(), 1 days, "min timelock delay");
        assertEq(timelock.MAX_TIMELOCK_DELAY(), 30 days, "max timelock delay");
        assertEq(timelock.EXECUTION_WINDOW(), 3 days, "execution window");
        assertEq(timelock.MAX_GRACE_PERIOD(), 7 days, "max grace period");

        (uint8 major, uint8 minor) = timelock.VERSION();
        assertEq(major, 1, "major version");
        assertEq(minor, 0, "minor version");
    }

    // constructor
    // given valid parameters
    //  when deploying the timelock
    //   then the policy starts disabled and the facility slot is unset
    function test_constructor_givenValidParams_startsDisabledWithoutFacility() public {
        YieldRepurchaseFacilityConfigTimelock timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelockDelay,
            gracePeriod
        );

        assertFalse(timelock.isEnabled(), "enabled flag");
        assertEq(timelock.lastTransitionAt(), 0, "last transition timestamp");
        assertEq(timelock.facility(), address(0), "facility slot");
        assertEq(timelock.pendingInitialDiscountActionId(), 0, "pending discount action id");
        assertEq(
            timelock.pendingYieldBuybackShareActionId(address(sReserve)),
            0,
            "pending share action id"
        );
    }

    // configureDependencies
    // given the installed ROLES module reports a major version other than 1
    //  when the kernel activates the policy
    //   then it reverts with Policy_WrongModuleVersion(abi.encode([1]))
    function test_configureDependencies_givenWrongRolesVersion_reverts() public {
        YieldRepurchaseFacilityConfigTimelock timelock = new YieldRepurchaseFacilityConfigTimelock(
            kernel,
            configTimelockDelay,
            gracePeriod
        );
        vm.mockCall(
            address(ROLES),
            abi.encodeWithSelector(Module.VERSION.selector),
            abi.encode(uint8(2), uint8(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1]))
        );
        kernel.executeAction(Actions.ActivatePolicy, address(timelock));
    }

    // requestPermissions
    // given the policy calls the facility directly, gated on its address
    //  when reading the requested permissions
    //   then the array is empty
    function test_requestPermissions_returnsEmpty() public view {
        Permissions[] memory permissions = configTimelock.requestPermissions();

        assertEq(permissions.length, 0, "permissions length");
    }

    // pairing (facility constructor)
    // given a timelock deployed on another kernel
    //  when deploying a facility pinned to it
    //   then the facility constructor reverts with
    //   IYieldRepurchaseFacilityV2_TimelockKernelMismatch
    function test_facilityConstructor_givenTimelockOnOtherKernel_reverts() public {
        Kernel otherKernel = new Kernel();
        vm.label(address(otherKernel), "otherKernel");
        YieldRepurchaseFacilityConfigTimelock foreignTimelock = new YieldRepurchaseFacilityConfigTimelock(
                otherKernel,
                configTimelockDelay,
                gracePeriod
            );
        vm.label(address(foreignTimelock), "foreignTimelock");

        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseFacilityV2
                    .IYieldRepurchaseFacilityV2_TimelockKernelMismatch
                    .selector,
                address(foreignTimelock)
            )
        );
        new YieldRepurchaseFacilityV2(
            kernel,
            address(ohm),
            address(backingOracle),
            address(auctioneer),
            address(foreignTimelock),
            gracePeriod
        );
    }
}
