// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetReferrerAllowedTest is BurnerLoansRiskTest {
    function _setAllowed(address caller_, address referrer_, bool allowed_) private {
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IBurnerLoansRisk.ReferrerAllowedSet(referrer_, allowed_);
        vm.recordLogs();
        vm.prank(caller_);
        _risk.setReferrerAllowed(referrer_, allowed_);
        assertEq(_risk.isReferrerAllowed(referrer_), allowed_, "exact membership stored");
        assertEq(vm.getRecordedLogs().length, 1, "changed membership event once");
        assertEq(_risk.referralFeeBps(), 0, "percentage unchanged");
    }

    // Scenarios: BLRISK-REFERRER-A03, BLRISK-REFERRER-A04.
    function test_whenUnauthorizedCaller_reverts(
        address caller_,
        address referrer_,
        bool allowed_
    ) public givenOperator {
        vm.assume(caller_ != address(this) && caller_ != _operator);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.setReferrerAllowed(referrer_, allowed_);
        assertFalse(_risk.isReferrerAllowed(referrer_), "unauthorized membership unchanged");
    }

    // Scenarios: BLRISK-REFERRER-A04.
    function test_whenUnauthorizedSameValue_reverts() public {
        test_whenUnauthorizedCaller_reverts(address(0), _operator, false);
    }

    // Scenarios: BLRISK-REFERRER-I01.
    function test_whenZeroReferrer_reverts(bool allowed_) public {
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        _risk.setReferrerAllowed(address(0), allowed_);
        assertFalse(_risk.isReferrerAllowed(address(0)), "zero never admitted");
    }

    // Scenarios: BLRISK-REFERRER-I01.
    function test_whenZeroReferrerBoundaries_reverts() public {
        test_whenZeroReferrer_reverts(false);
        test_whenZeroReferrer_reverts(true);
    }

    // Scenarios: BLRISK-REFERRER-A01, BLRISK-REFERRER-P01, BLRISK-REFERRER-P02.
    function test_givenAdmin_whenMembershipChanges(
        address referrer_,
        address caller_,
        address operator_
    ) public {
        vm.assume(referrer_ != address(0));
        if (_risk.configOperator() != operator_) _risk.setConfigOperator(operator_);
        _grantAdmin(caller_);
        _setAllowed(caller_, referrer_, true);
        _setAllowed(caller_, referrer_, false);
    }

    // Scenarios: BLRISK-REFERRER-A02, BLRISK-REFERRER-P01, BLRISK-REFERRER-P02.
    function test_givenOperator_whenMembershipChanges(address referrer_) public givenOperator {
        vm.assume(referrer_ != address(0));
        _setAllowed(_operator, referrer_, true);
        _setAllowed(_operator, referrer_, false);
    }

    // Scenarios: BLRISK-REFERRER-P03, BLRISK-REFERRER-P04.
    function test_whenSameMembership(address referrer_, bool allowed_) public {
        vm.assume(referrer_ != address(0));
        _risk.setReferrerAllowed(referrer_, allowed_);
        vm.recordLogs();
        _risk.setReferrerAllowed(referrer_, allowed_);
        assertEq(_risk.isReferrerAllowed(referrer_), allowed_, "same membership retained");
        assertEq(vm.getRecordedLogs().length, 0, "same membership emits no event");
    }

    // Scenarios: BLRISK-REFERRER-P05.
    function test_whenIndependentReferrersChange() public {
        address r1 = address(0xB0B);
        address r2 = address(_asset);
        _setAllowed(address(this), r1, true);
        _setAllowed(address(this), r2, true);
        _setAllowed(address(this), r1, false);
        assertTrue(_risk.isReferrerAllowed(r2), "other referrer retained");
        _setAllowed(address(this), r1, true);
        assertTrue(_risk.isReferrerAllowed(r2), "readding leaves other referrer unchanged");
    }

    // Scenarios: BLRISK-REFERRER-L01, BLRISK-REFERRER-L02.
    function test_givenInactive_whenMembershipChanges_reverts(
        bool enabled_,
        bool operator_
    ) public givenOperator {
        if (!enabled_) _risk.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _expectInactive();
        vm.prank(operator_ ? _operator : address(this));
        _risk.setReferrerAllowed(address(0), true);
        assertFalse(_risk.isReferrerAllowed(address(0)), "inactive membership unchanged");
    }

    // Scenarios: BLRISK-REFERRER-L03.
    function test_givenDisabled_whenMembershipChanges_reverts(
        bool operator_
    ) public givenOperator givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(operator_ ? _operator : address(this));
        _risk.setReferrerAllowed(address(0), true);
    }

    // Scenarios: BLRISK-REFERRER-L04.
    function test_givenReEnabled_whenMembershipChanges() public givenReEnabled {
        _setAllowed(address(this), _operator, true);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _setAllowed(address(this), _operator, false);
    }

    // Scenarios: BLRISK-REFERRER-D01.
    function test_givenUnreadableController_whenMembershipChanges(
        bool active_,
        bool enabled_
    ) public givenOperator {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, _operator),
            abi.encode(active_)
        );
        vm.mockCallRevert(
            _operator,
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(_operator, abi.encodeWithSignature("isEnabled()"), abi.encode(enabled_));
        _setAllowed(_operator, _operator, true);
    }

    // Scenarios: BLRISK-REFERRER-A01, BLRISK-REFERRER-A02.
    function test_givenEachAdminOperatorSelection_whenChanged() public {
        address caller = address(0xA11);
        uint256 checkpoint = vm.snapshotState();
        test_givenAdmin_whenMembershipChanges(address(this), caller, address(0));
        assertTrue(vm.revertToState(checkpoint), "restore unset operator case");
        test_givenAdmin_whenMembershipChanges(_operator, caller, _operator);
        assertTrue(vm.revertToState(checkpoint), "restore distinct operator case");
        test_givenAdmin_whenMembershipChanges(address(_asset), caller, caller);
    }

    // Scenarios: BLRISK-REFERRER-A03, BLRISK-REFERRER-A04.
    function test_givenBlaOnly_whenSettingChanged_reverts(bool allowed_) public givenOperator {
        address caller = address(0xB1A0);
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _risk.setReferrerAllowed(_operator, allowed_);
    }

    // Scenarios: BLRISK-REFERRER-A03, BLRISK-REFERRER-A04.
    function test_givenEmergencyOnly_whenSettingChanged_reverts(
        bool allowed_
    ) public givenOperator {
        address caller = address(0xE110);
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _risk.setReferrerAllowed(_operator, allowed_);
    }

    // Scenarios: BLRISK-REFERRER-A03, BLRISK-REFERRER-A04.
    function test_givenFormerOperator_whenSettingChanged_reverts(
        bool allowed_
    ) public givenOperator {
        _risk.setConfigOperator(address(0xF000));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_operator);
        _risk.setReferrerAllowed(_operator, allowed_);
    }
}
