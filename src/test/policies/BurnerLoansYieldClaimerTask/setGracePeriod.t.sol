// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansYieldClaimerTaskSetGracePeriodTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-GRACE-L01, BLYC-GRACE-L03.
    function test_givenDisabled_revertsBeforeAuthorizationOrValidation(
        address caller_,
        uint32 period_
    ) public {
        _setClaimerLifecycle(true, false);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(caller_);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-L02, BLYC-GRACE-L04.
    function test_givenInactiveDisabled_revertsBeforeAuthorizationOrValidation(
        address caller_,
        uint32 period_
    ) public {
        _setClaimerLifecycle(false, false);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(caller_);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-A01, BLYC-GRACE-A02.
    function test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != admin);
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        claimer.setGracePeriod(period_);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-N02.
    function test_givenZeroPeriod_reverts() public {
        uint32 periodBefore = claimer.gracePeriod();

        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(admin);
        claimer.setGracePeriod(0);

        assertEq(claimer.gracePeriod(), periodBefore, "grace period unchanged");
    }

    // Scenarios: BLYC-GRACE-N01, BLYC-GRACE-L05.
    function test_givenDifferentValidPeriod_setsPeriod(uint32 period_) public {
        period_ = _boundUint32(period_, 1, type(uint32).max);
        uint32 currentPeriod = claimer.gracePeriod();
        vm.assume(period_ != currentPeriod);
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

    // Scenarios: BLYC-GRACE-N01.
    function test_whenGracePeriodBoundaryUsed_storesExactPeriod(bool maximum_) public {
        uint32 period = maximum_ ? type(uint32).max : 1;

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(period);
        vm.prank(admin);
        claimer.setGracePeriod(period);

        assertEq(claimer.gracePeriod(), period, "boundary grace period stored");
    }

    // Scenarios: BLYC-GRACE-P02.
    function test_givenCurrentPeriod_emitsEvent(uint32 period_) public {
        uint32 currentPeriod = _boundUint32(period_, 1, type(uint32).max);
        vm.prank(admin);
        claimer.setGracePeriod(currentPeriod);
        uint48 transitionAt = claimer.lastTransitionAt();

        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(currentPeriod);
        vm.prank(admin);
        claimer.setGracePeriod(currentPeriod);

        assertEq(claimer.gracePeriod(), currentPeriod, "same grace period retained");
        assertEq(claimer.lastTransitionAt(), transitionAt, "transition timestamp unchanged");
    }

    // Scenarios: BLYC-GRACE-L06, BLYC-GRACE-L08, BLYC-GRACE-L10, BLYC-GRACE-L12.
    function test_givenInactivePolicy_whenGraceSet_reverts(
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setTargetLifecycle(coreActive_, coreEnabled_);
        _setClaimerLifecycle(false, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(claimer)
            )
        );
        vm.prank(admin);
        claimer.setGracePeriod(1);
    }

    // Scenarios: BLYC-GRACE-A03, BLYC-GRACE-N01, BLYC-GRACE-L05, BLYC-GRACE-L07, BLYC-GRACE-L09, BLYC-GRACE-L11.
    function test_givenArbitraryAdmin_whenGraceSet(
        address caller_,
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _grantClaimerAdmin(caller_, 0);
        period_ = _boundUint32(period_, 1, type(uint32).max);
        _setTargetLifecycle(coreActive_, coreEnabled_);
        uint48 before = claimer.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        claimer.setGracePeriod(period_);
        assertEq(claimer.gracePeriod(), period_, "Full uint32 range retained");
        assertEq(claimer.lastTransitionAt(), before, "No lifecycle transition");
    }

    // Scenarios: BLYC-GRACE-N01, BLYC-GRACE-P02.
    function test_whenPeriodSeeds() public {
        test_givenCurrentPeriod_emitsEvent(1);
        test_givenCurrentPeriod_emitsEvent(type(uint32).max);
        test_givenArbitraryAdmin_whenGraceSet(address(0xBEEF), 1, true, true);
        test_givenArbitraryAdmin_whenGraceSet(address(0xBEEF1), type(uint32).max, true, true);
        uint32 current = claimer.gracePeriod();
        vm.expectEmit(false, false, false, true, address(claimer));
        emit IGracePeriod.GracePeriodSet(current);
        vm.prank(admin);
        claimer.setGracePeriod(current);
        assertEq(claimer.gracePeriod(), current, "Same period retained");
    }
}
