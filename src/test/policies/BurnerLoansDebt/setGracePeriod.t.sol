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
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansDebtLifecycleTest} from "src/test/policies/BurnerLoansDebt/fixtures/BurnerLoansDebtLifecycleTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(unsafe-typecast)

contract BurnerLoansDebtSetGracePeriodTest is BurnerLoansDebtLifecycleTest {
    // Scenarios: BLDEBTGR-P01.
    function test_whenGraceSetToSameValue_thenStillEmits(uint32 grace_) public {
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        _debt.setGracePeriod(grace_);
        uint48 last = _debt.lastTransitionAt();
        vm.expectEmit(address(_debt));
        emit IGracePeriod.GracePeriodSet(grace_);
        _debt.setGracePeriod(grace_);
        assertEq(_debt.gracePeriod(), grace_, "Same period retained");
        assertEq(_debt.lastTransitionAt(), last, "Setter is not a transition");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-I01.
    function test_whenGraceIsZero_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _debt.setGracePeriod(0);
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-A01, BLDEBTGR-A02.
    function test_whenUnauthorizedGraceSetter_revertsBeforeInput(
        address caller_,
        bool zero_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _debt.setGracePeriod(zero_ ? 0 : 1);
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-L01, BLDEBTGR-L02.
    function test_givenDisabled_whenGraceSet_thenPauseWins(address caller_, bool zero_) public {
        _debt.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _debt.setGracePeriod(zero_ ? 0 : 1);
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-L03, BLDEBTGR-L04, BLDEBTGR-L05, BLDEBTGR-L06, BLDEBTGR-N01.
    function test_givenCoreState_whenGraceSet_thenControllerIndependent(
        bool coreActive_,
        bool coreEnabled_,
        uint32 period_
    ) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        uint48 last = _debt.lastTransitionAt();
        vm.expectEmit(address(_debt));
        emit IGracePeriod.GracePeriodSet(period_);
        _debt.setGracePeriod(period_);
        assertEq(_debt.gracePeriod(), period_, "Full width grace stored");
        assertEq(_debt.lastTransitionAt(), last, "Grace setter leaves transition time unchanged");
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-L07.
    function test_givenInactiveSubject_whenGraceSet_reverts() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            )
        );
        _debt.setGracePeriod(1);
        _assertLoansPreserved();
    }

    // Scenarios: BLDEBTGR-N01, BLDEBTGR-P01.
    function test_whenPeriodIsOne_thenStoredAndEmitted() public {
        test_whenGraceSetToSameValue_thenStillEmits(1);
    }

    // Scenarios: BLDEBTGR-N01, BLDEBTGR-P01.
    function test_whenPeriodIsMaximum_thenStoredAndEmitted() public {
        test_whenGraceSetToSameValue_thenStillEmits(type(uint32).max);
    }

    // Scenarios: BLDEBTGR-L07.
    function test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts(address caller_) public {
        _debt.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            )
        );
        vm.prank(caller_);
        _debt.setGracePeriod(0);
    }
}

// forge-lint: disable-end(unsafe-typecast)
