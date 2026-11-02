// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansCollateralTest} from "./BurnerLoansCollateralTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralSetGracePeriodTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOLGR-L03, BLCOLGR-L04, BLCOLGR-L05, BLCOLGR-L06, BLCOLGR-N01.
    function test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges(
        bool active_,
        bool enabled_,
        address caller_,
        uint32 period_
    ) public givenCollateralEnabled {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _grantCaller(caller_, 1, ADMIN_ROLE);
        _setPolicyState(policy, active_, enabled_);
        uint48 last = _collateral.lastTransitionAt();
        vm.expectEmit(address(_collateral));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _collateral.setGracePeriod(period_);
        assertEq(_collateral.gracePeriod(), period_, "Full input stored");
        _assertRejection(true, last);
    }

    // Scenarios: BLCOLGR-P01.
    function test_whenGraceEqualsCurrentValue_thenEventStillEmitted(
        address caller_,
        uint32 period_
    ) public givenCollateralEnabled {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _grantCaller(caller_, 1, ADMIN_ROLE);
        vm.startPrank(caller_);
        _collateral.setGracePeriod(period_);
        vm.expectEmit(address(_collateral));
        emit IGracePeriod.GracePeriodSet(period_);
        _collateral.setGracePeriod(period_);
        vm.stopPrank();
        assertEq(_collateral.gracePeriod(), period_, "Same period preserved");
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOLGR-N01, BLCOLGR-P01, BLCOLGR-L03, BLCOLGR-L04, BLCOLGR-L05, BLCOLGR-L06.
    function test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored() public {
        for (uint256 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges(
                flags & 1 != 0,
                flags & 2 != 0,
                address(0),
                1
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before maximum period seed");
            test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges(
                flags & 1 != 0,
                flags & 2 != 0,
                address(0),
                type(uint32).max
            );
            assertTrue(vm.revertToState(checkpoint), "Restore before next Core state");
        }
        test_whenGraceEqualsCurrentValue_thenEventStillEmitted(address(0), type(uint32).max);
    }

    // Scenarios: BLCOLGR-A01.
    function test_whenUnauthorizedCallerSetsValidPeriod_reverts(
        address caller_
    ) public givenCollateralEnabled {
        _expectRoleError(caller_, 1);
    }

    // Scenarios: BLCOLGR-A02.
    function test_whenUnauthorizedCallerSetsZero_reverts(
        address caller_
    ) public givenCollateralEnabled {
        _expectRoleError(caller_, 0);
    }

    // Scenarios: BLCOLGR-L01.
    function test_givenDisabled_whenValidPeriod_reverts(address caller_) public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.setGracePeriod(1);
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOLGR-L02.
    function test_givenDisabled_whenZeroPeriod_reverts(address caller_) public {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.setGracePeriod(0);
        _assertLifecycle(false, 0);
    }

    // Scenarios: BLCOLGR-I01.
    function test_whenAdminSetsZero_reverts(address caller_) public givenCollateralEnabled {
        _grantCaller(caller_, 1, ADMIN_ROLE);
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(caller_);
        _collateral.setGracePeriod(0);
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOLGR-L07.
    function test_givenInactive_whenAdminSetsPeriod_reverts(
        address caller_
    ) public givenCollateralEnabled givenCollateralInactive {
        _grantCaller(caller_, 1, ADMIN_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            )
        );
        vm.prank(caller_);
        _collateral.setGracePeriod(1);
        _assertRejection(true, START_TIMESTAMP);
    }

    function _expectRoleError(address caller_, uint32 period_) internal {
        vm.assume(!roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _collateral.setGracePeriod(period_);
        _assertLifecycle(true, START_TIMESTAMP);
    }

    // Scenarios: BLCOLGR-L01, BLCOLGR-L02.
    function test_givenDisabledAfterEnable_whenGraceSet_thenPauseWins(
        address caller_,
        bool zero_
    ) public givenCollateralDisabledAfterEnable {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _collateral.setGracePeriod(zero_ ? 0 : 1);
        _assertRejection(false, START_TIMESTAMP);
    }

    // Scenarios: BLCOLGR-L07.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts(
        address caller_
    ) public givenCollateralEnabled {
        _collateral.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_collateral));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_collateral)
            )
        );
        vm.prank(caller_);
        _collateral.setGracePeriod(0);
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
