// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetConfigOperatorTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-CONFIGURATOR-A04.
    function test_givenOperator_whenUnauthorizedCallerRequestsSameOperator_reverts(
        address caller_
    ) public givenOperator {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setConfigOperator(_operator);
        assertEq(_risk.configOperator(), _operator, "operator unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-A04.
    function test_givenNoOperator_whenUnauthorizedCallerRequestsZero_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setConfigOperator(address(0));
    }

    // Scenarios: BLRISK-CONFIGURATOR-P05.
    function test_whenOperatorGrantedCacheAgeAuthority() public {
        _risk.setConfigOperator(_operator);
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 1, "operator can set age");
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(_operator);
        _risk.setBackingOracle(address(_oracle));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(_operator);
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-CONFIGURATOR-L01, BLRISK-CONFIGURATOR-A02, BLRISK-CONFIGURATOR-P04, BLRISK-CONFIGURATOR-P05.
    function test_givenEnabled_whenAdminSelectsOperator(address caller_, address next_) public {
        vm.assume(next_ != address(0));
        _grantAdmin(caller_);
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IConfigOperator.ConfigOperatorSet(next_);
        vm.prank(caller_);
        _risk.setConfigOperator(next_);
        assertEq(_risk.configOperator(), next_, "selected operator");
        assertEq(_risk.priceCacheMaxAge(), 60, "other configuration unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-L02.
    function test_givenDisabled_whenAdminSelectsOperator(
        address caller_,
        address next_
    ) public givenDisabled {
        vm.assume(next_ != address(0));
        _grantAdmin(caller_);
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IConfigOperator.ConfigOperatorSet(next_);
        vm.prank(caller_);
        _risk.setConfigOperator(next_);
        assertEq(_risk.configOperator(), next_, "selected operator");
        assertEq(_risk.priceCacheMaxAge(), 60, "other configuration unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-L03.
    function test_givenInactive_whenOperatorChanges_reverts() public givenInactive {
        _expectInactive();
        _risk.setConfigOperator(_operator);
        assertEq(_risk.configOperator(), address(0), "operator unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-L04.
    function test_givenInactiveAndDisabled_whenOperatorChanges_reverts()
        public
        givenDisabled
        givenInactive
    {
        _expectInactive();
        _risk.setConfigOperator(_operator);
        assertEq(_risk.configOperator(), address(0), "operator unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-A01, BLRISK-CONFIGURATOR-A03, BLRISK-CONFIGURATOR-A04.
    function test_whenNonAdminChangesOperator_reverts(address caller_, address next_) public {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setConfigOperator(next_);
        assertEq(_risk.configOperator(), address(0), "operator unchanged");
    }

    // Scenarios: BLRISK-CONFIGURATOR-I01.
    function test_givenZero_whenUnchanged_reverts() public {
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        _risk.setConfigOperator(address(0));
        assertEq(vm.getRecordedLogs().length, 0, "no setter logs");
    }

    // Scenarios: BLRISK-CONFIGURATOR-I01.
    function test_givenSelected_whenUnchanged_reverts() public givenOperator {
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        _risk.setConfigOperator(_operator);
        assertEq(vm.getRecordedLogs().length, 0, "no setter logs");
    }

    // Scenarios: BLRISK-CONFIGURATOR-I02, BLRISK-CONFIGURATOR-P04.
    function test_whenControllerGettersRevert() public {
        address controller = address(_cache);
        vm.mockCallRevert(
            controller,
            bytes(""),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _risk.setConfigOperator(controller);
        assertEq(_risk.configOperator(), controller, "opaque controller accepted");
    }

    // Scenarios: BLRISK-CONFIGURATOR-I03.
    function test_givenOperator_whenRevoked() public givenOperator {
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IConfigOperator.ConfigOperatorSet(address(0));
        _risk.setConfigOperator(address(0));
        assertEq(_risk.configOperator(), address(0), "operator cleared");
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 1, "admin retains authority");
    }

    // Scenarios: BLRISK-CONFIGURATOR-P01.
    function test_givenOperator_whenReplaced() public givenOperator {
        address next = address(0xABCD);
        _risk.setConfigOperator(next);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        vm.prank(next);
        _risk.setPriceCacheMaxAge(1);
        _risk.setPriceCacheMaxAge(2);
        assertEq(_risk.priceCacheMaxAge(), 2, "new operator and admin retain authority");
    }
}
