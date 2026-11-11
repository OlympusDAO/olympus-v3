// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetReferralFeeBpsTest is BurnerLoansRiskTest {
    function _setBps(address caller_, uint16 bps_) private {
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IBurnerLoansRisk.ReferralFeeBpsSet(bps_);
        vm.recordLogs();
        vm.prank(caller_);
        _risk.setReferralFeeBps(bps_);
        assertEq(_risk.referralFeeBps(), bps_, "exact percentage stored");
        assertEq(vm.getRecordedLogs().length, 1, "changed percentage event once");
        assertFalse(_risk.isReferrerAllowed(address(0)), "unrelated membership unchanged");
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A03, BLRISK-REFERRAL-BPS-A04.
    function test_whenUnauthorizedCaller_reverts(
        address caller_,
        uint16 bps_
    ) public givenOperator {
        vm.assume(caller_ != address(this) && caller_ != _operator);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.setReferralFeeBps(bps_);
        assertEq(_risk.referralFeeBps(), 0, "percentage unchanged");
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A04.
    function test_whenUnauthorizedSameValue_reverts() public {
        test_whenUnauthorizedCaller_reverts(address(0), 0);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-I01.
    function test_whenInvalidPercentage_reverts(uint16 bps_) public {
        uint16 bps = uint16(bound(bps_, 10001, type(uint16).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoansRisk_InvalidReferralFeeBps.selector,
                bps
            )
        );
        _risk.setReferralFeeBps(bps);
        assertEq(_risk.referralFeeBps(), 0, "invalid percentage unchanged");
    }

    // Scenarios: BLRISK-REFERRAL-BPS-I01.
    function test_whenInvalidPercentageBoundaries_reverts() public {
        test_whenInvalidPercentage_reverts(10001);
        test_whenInvalidPercentage_reverts(type(uint16).max);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A01, BLRISK-REFERRAL-BPS-N01.
    function test_givenAdmin_whenPercentageChanges(
        uint16 bps_,
        address caller_,
        address operator_
    ) public {
        if (_risk.configOperator() != operator_) _risk.setConfigOperator(operator_);
        _grantAdmin(caller_);
        _setBps(caller_, uint16(bound(bps_, 1, 10000)));
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A01, BLRISK-REFERRAL-BPS-A02, BLRISK-REFERRAL-BPS-N01, BLRISK-REFERRAL-BPS-P02.
    function test_whenPercentageBoundaryTransitions() public givenOperator {
        _setBps(address(this), 10000);
        _setBps(_operator, 1);
        _setBps(_operator, 9999);
        _setBps(address(this), 0);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A02, BLRISK-REFERRAL-BPS-N01.
    function test_givenOperator_whenPercentageChanges(uint16 bps_) public givenOperator {
        _setBps(_operator, uint16(bound(bps_, 1, 10000)));
    }

    // Scenarios: BLRISK-REFERRAL-BPS-P01.
    function test_whenSamePercentage(uint16 bps_) public {
        uint16 bps = uint16(bound(bps_, 0, 10000));
        _risk.setReferralFeeBps(bps);
        vm.recordLogs();
        _risk.setReferralFeeBps(bps);
        assertEq(_risk.referralFeeBps(), bps, "same value retained");
        assertEq(vm.getRecordedLogs().length, 0, "same percentage emits no event");
    }

    // Scenarios: BLRISK-REFERRAL-BPS-L01, BLRISK-REFERRAL-BPS-L02.
    function test_givenInactive_whenPercentageChanges_reverts(
        bool enabled_,
        bool operator_
    ) public givenOperator {
        if (!enabled_) _risk.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _expectInactive();
        vm.prank(operator_ ? _operator : address(this));
        _risk.setReferralFeeBps(type(uint16).max);
        assertEq(_risk.referralFeeBps(), 0, "inactive configuration unchanged");
    }

    // Scenarios: BLRISK-REFERRAL-BPS-L03.
    function test_givenDisabled_whenPercentageChanges_reverts(
        bool operator_
    ) public givenOperator givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(operator_ ? _operator : address(this));
        _risk.setReferralFeeBps(type(uint16).max);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-L04.
    function test_givenReEnabled_whenPercentageChanges() public givenReEnabled {
        _setBps(address(this), 1);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _setBps(address(this), 10000);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-D01.
    function test_givenUnreadableController_whenPercentageChanges(
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
        _setBps(_operator, 2500);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A01, BLRISK-REFERRAL-BPS-A02.
    function test_givenEachAdminOperatorSelection_whenChanged() public {
        address caller = address(0xA11);
        uint256 checkpoint = vm.snapshotState();
        test_givenAdmin_whenPercentageChanges(1, caller, address(0));
        assertTrue(vm.revertToState(checkpoint), "restore unset operator case");
        test_givenAdmin_whenPercentageChanges(10000, caller, _operator);
        assertTrue(vm.revertToState(checkpoint), "restore distinct operator case");
        test_givenAdmin_whenPercentageChanges(9999, caller, caller);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A03, BLRISK-REFERRAL-BPS-A04.
    function test_givenBlaOnly_whenSettingChanged_reverts(uint16 bps_) public givenOperator {
        address caller = address(0xB1A0);
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, caller);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _risk.setReferralFeeBps(bps_);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A03, BLRISK-REFERRAL-BPS-A04.
    function test_givenEmergencyOnly_whenSettingChanged_reverts(uint16 bps_) public givenOperator {
        address caller = address(0xE110);
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller);
        _risk.setReferralFeeBps(bps_);
    }

    // Scenarios: BLRISK-REFERRAL-BPS-A03, BLRISK-REFERRAL-BPS-A04.
    function test_givenFormerOperator_whenSettingChanged_reverts(uint16 bps_) public givenOperator {
        _risk.setConfigOperator(address(0xF000));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_operator);
        _risk.setReferralFeeBps(bps_);
    }
}
