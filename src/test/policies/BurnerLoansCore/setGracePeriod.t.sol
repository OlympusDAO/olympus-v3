// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansCoreSetGracePeriodTest is BurnerLoansCoreTest {
    // Scenarios: BLCOREGR-L01, BLCOREGR-N01.
    function test_givenAdmin_whenGraceSet(address caller_, uint32 period_) public {
        _grantAdmin(caller_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        uint48 transition = _core.lastTransitionAt();
        bytes32 ledger = _ledger();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _core.setGracePeriod(period_);
        assertEq(_core.gracePeriod(), period_, "Exact period stored");
        assertEq(_core.lastTransitionAt(), transition, "Grace update does not restart window");
        assertEq(_ledger(), ledger, "Grace update has no accounting effects");
    }

    // Scenarios: BLCOREGR-N01.
    function test_whenGracePeriodBoundarySeeds() public {
        test_givenAdmin_whenGraceSet(_recipient, 1);
        test_givenAdmin_whenGraceSet(_recipient, 7 days);
        test_givenAdmin_whenGraceSet(_recipient, type(uint32).max);
    }

    // Scenarios: BLCOREGR-P01.
    function test_givenSamePeriod_whenGraceSet(uint32 period_) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _core.setGracePeriod(period_);
        uint48 transition = _core.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(_core));
        emit IGracePeriod.GracePeriodSet(period_);
        _core.setGracePeriod(period_);
        assertEq(_core.gracePeriod(), period_, "Same nonzero period accepted");
        assertEq(
            _core.lastTransitionAt(),
            transition,
            "Same period emits without restarting grace"
        );
    }

    // Scenarios: BLCOREGR-A01, BLCOREGR-A02.
    function test_givenUnauthorized_whenGraceSet_reverts(address caller_, bool zero_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setGracePeriod(zero_ ? 0 : 1);
    }

    // Scenarios: BLCOREGR-L02, BLCOREGR-L03, BLCOREGR-L04.
    function test_givenUnavailableCore_whenGraceSet_reverts(bool enabled_) public {
        _setCoreLifecycle(false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        _core.setGracePeriod(0);
    }

    // Scenarios: BLCOREGR-L02.
    function test_givenActiveDisabled_whenGraceSet_reverts() public {
        _setCoreLifecycle(true, false);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _core.setGracePeriod(0);
    }

    // Scenarios: BLCOREGR-I01.
    function test_whenZeroGraceSet_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _core.setGracePeriod(0);
    }

    // Scenarios: BLCOREGR-C01.
    function test_givenBusyCore_whenGraceSet_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("setGracePeriod(uint32)", uint32(1)),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized grace callback reaches guard"
        );
        assertEq(_core.gracePeriod(), 7 days, "No nested grace write");
    }
}
