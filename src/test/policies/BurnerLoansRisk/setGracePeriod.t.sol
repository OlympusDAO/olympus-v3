// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetGracePeriodTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-GRACE-L01.
    function test_givenOperational_whenGraceChanges() public {
        _risk.setGracePeriod(1);
        assertEq(_risk.gracePeriod(), 1, "grace period");
    }

    // Scenarios: BLRISK-GRACE-L02.
    function test_givenDisabled_whenGraceChanges_reverts() public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _risk.setGracePeriod(1);
    }

    // Scenarios: BLRISK-GRACE-L03.
    function test_givenInactive_whenGraceChanges_reverts() public givenInactive {
        _expectInactive();
        _risk.setGracePeriod(1);
    }

    // Scenarios: BLRISK-GRACE-L04.
    function test_givenInactiveAndDisabled_whenGraceChanges_reverts()
        public
        givenDisabled
        givenInactive
    {
        _expectInactive();
        _risk.setGracePeriod(1);
    }

    // Scenarios: BLRISK-GRACE-A01.
    function test_whenUnauthorizedCallerChangesGrace_reverts(
        address caller_,
        uint32 period_
    ) public {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setGracePeriod(uint32(bound(period_, 1, type(uint32).max)));
    }

    // Scenarios: BLRISK-GRACE-I01.
    function test_whenGraceIsZero_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        _risk.setGracePeriod(0);
    }

    function _setGrace(uint32 period_) private {
        uint48 last = _risk.lastTransitionAt();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.recordLogs();
        _risk.setGracePeriod(period_);
        assertEq(vm.getRecordedLogs().length, 1, "exact grace event count");
        assertEq(_risk.gracePeriod(), period_, "exact grace");
        assertEq(_risk.lastTransitionAt(), last, "transition timestamp unchanged");
        assertTrue(_risk.isEnabled(), "enablement unchanged");
    }

    // Scenarios: BLRISK-GRACE-N01.
    function test_whenGraceIsValid(uint32 period_) public {
        _setGrace(uint32(bound(period_, 1, type(uint32).max)));
    }

    // Scenarios: BLRISK-GRACE-N01.
    function test_whenGraceEndpoints() public {
        _setGrace(1);
        _setGrace(type(uint32).max);
    }

    // Scenarios: BLRISK-GRACE-P01.
    function test_whenGraceIsUnchanged() public {
        _setGrace(_risk.gracePeriod());
    }

    // Scenarios: BLRISK-GRACE-L03, BLRISK-GRACE-L04.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(caller_ != address(this));
        if (!enabled_) _risk.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_risk)
            )
        );
        vm.prank(caller_);
        _risk.setGracePeriod(0);
    }
}
