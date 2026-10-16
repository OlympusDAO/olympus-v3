// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansYieldClaimerTest} from "./BurnerLoansYieldClaimerTest.sol";

contract BurnerLoansYieldClaimerSetGracePeriodTest is BurnerLoansYieldClaimerTest {
    // Scenarios: BLYC-GRACE-L01.
    function test_givenDisabled_revertsBeforeAuthorizationOrValidation(
        address caller_,
        uint32 period_,
        bool active_
    ) public {
        _setClaimerLifecycle(active_, false);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-A01.
    function test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts(
        address caller_,
        uint32 period_,
        bool active_
    ) public {
        vm.assume(caller_ != admin);
        _setClaimerLifecycle(active_, true);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-I01.
    function test_givenZeroPeriod_reverts(bool active_) public {
        _setClaimerLifecycle(active_, true);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        claimer.setGracePeriod(0);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-P01.
    function test_givenDifferentValidPeriod_setsPeriod(uint32 period_, bool active_) public {
        period_ = _boundUint32(period_, 1, type(uint32).max);
        uint32 currentPeriod = claimer.gracePeriod();
        if (period_ == currentPeriod) {
            period_ = currentPeriod == type(uint32).max ? currentPeriod - 1 : currentPeriod + 1;
        }
        _setClaimerLifecycle(active_, true);
        uint48 transitionAt = claimer.lastTransitionAt();
        uint32 executionLimit = claimer.executionGasLimit();
        uint32 threshold = claimer.minimumGasToAttempt();
        uint32 reserve = claimer.gasReserve();
        uint256 cursor = claimer.nextAssetIndex();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(admin);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), period_, "grace period equals input");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
        assertEq(claimer.executionGasLimit(), executionLimit, "execution limit unchanged");
        assertEq(claimer.minimumGasToAttempt(), threshold, "threshold unchanged");
        assertEq(claimer.gasReserve(), reserve, "reserve unchanged");
        assertEq(claimer.nextAssetIndex(), cursor, "cursor unchanged");
    }

    // Scenarios: BLYC-GRACE-P01.
    function test_whenGracePeriodBoundaryUsed_storesExactPeriod(
        bool maximum_,
        bool active_
    ) public {
        uint32 period = maximum_ ? type(uint32).max : 1;
        _setClaimerLifecycle(active_, true);

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(period);
        vm.prank(admin);
        claimer.setGracePeriod(period);

        assertEq(claimer.gracePeriod(), period, "boundary grace period stored");
    }

    // Scenarios: BLYC-GRACE-P02.
    function test_givenCurrentPeriod_emitsEvent(bool active_) public {
        uint32 currentPeriod = claimer.gracePeriod();
        _setClaimerLifecycle(active_, true);
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        claimer.setGracePeriod(currentPeriod);

        assertEq(claimer.gracePeriod(), currentPeriod, "same grace period retained");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }
}
