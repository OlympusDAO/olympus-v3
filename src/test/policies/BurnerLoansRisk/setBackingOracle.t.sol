// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetBackingOracleTest is BurnerLoansRiskTest {
    function _select(address candidate_) private {
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IBurnerLoansRisk.BackingOracleSet(candidate_);
        _risk.setBackingOracle(candidate_);
        assertEq(_risk.backingOracle(), candidate_, "exact replacement");
    }

    function _reject(address candidate_) private {
        address previous = _risk.backingOracle();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                candidate_
            )
        );
        _risk.setBackingOracle(candidate_);
        assertEq(_risk.backingOracle(), previous, "failed setter preserves binding");
    }

    // Scenarios: BLRISK-BACKING-ORACLE-L01.
    function test_givenEnabled_whenDependencyChanges(address caller_) public givenAdmin(caller_) {
        _select(address(new MockOlympusBackingOracle(0)));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-L02.
    function test_givenDisabled_whenDependencyChanges(
        address caller_
    ) public givenDisabled givenAdmin(caller_) {
        _select(address(new MockOlympusBackingOracle(0)));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-L03.
    function test_givenInactive_whenDependencyChanges_reverts(
        address caller_
    ) public givenInactive givenAdmin(caller_) {
        _expectInactive();
        _risk.setBackingOracle(address(_cache));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-L04.
    function test_givenInactiveAndDisabled_whenDependencyChanges_reverts(
        address caller_
    ) public givenDisabled givenInactive givenAdmin(caller_) {
        _expectInactive();
        _risk.setBackingOracle(address(_cache));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public givenOperator {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setBackingOracle(address(_cache));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-I01.
    function test_whenZero_reverts(address caller_) public givenAdmin(caller_) {
        _reject(address(0));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-I02.
    function test_whenEoa_reverts(address caller_) public givenAdmin(caller_) {
        _reject(address(0xBEEF));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-I03.
    function test_whenMissingInterface_reverts(address caller_) public givenAdmin(caller_) {
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-D02.
    function test_whenUnversioned_reverts(address caller_) public givenAdmin(caller_) {
        _oracle = new MockOlympusBackingOracle(1e18);
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IVersioned).interfaceId)),
            abi.encode(false)
        );
        _reject(address(_oracle));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-I04.
    function test_whenRevertingERC165_reverts(address caller_) public givenAdmin(caller_) {
        _oracle = new MockOlympusBackingOracle(1e18);
        vm.mockCallRevert(
            address(_oracle),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _reject(address(_oracle));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-I05.
    function test_whenMalformedERC165_reverts(address caller_) public givenAdmin(caller_) {
        _oracle = new MockOlympusBackingOracle(1e18);
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            hex"01"
        );
        _reject(address(_oracle));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-P02.
    function test_whenUnchanged_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCallRevert(
            address(_oracle),
            bytes(""),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                address(_oracle)
            )
        );
        _risk.setBackingOracle(address(_oracle));
    }

    // Scenarios: BLRISK-BACKING-ORACLE-P01.
    function test_whenZeroBackingOracleSelected(address caller_) public givenAdmin(caller_) {
        MockOlympusBackingOracle next = new MockOlympusBackingOracle(0);
        _select(address(next));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        _risk.snapshot(address(_asset));
    }
}
