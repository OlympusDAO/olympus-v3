// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthCancelGrantTest is OperatorAuthTest {
    // Scenarios: OACANCEL-I01.
    function test_whenZeroOperator_reverts() public {
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.cancelGrant(address(0));
        assertEq(_auth.pairEpochs(_account, address(0)), 0, "Invalid pair unchanged");
    }

    // Scenarios: OACANCEL-I02.
    function test_whenSelfOperator_reverts(address account_) public {
        vm.assume(account_ != address(0));
        vm.prank(account_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfGrant.selector);
        _auth.cancelGrant(account_);
        assertEq(_auth.pairEpochs(account_, account_), 0, "Self pair unchanged");
    }

    // Scenarios: OACANCEL-P01.
    function test_givenGrant_whenCancelled_invalidatesOriginal() public {
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.prank(_account);
        _auth.cancelGrant(_operator);
        assertEq(_auth.pairEpochs(_account, _operator), 2, "Cancellation advances pair");
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, stamp);
        _assertNoGrant(_account, _operator);
    }

    // Scenarios: OACANCEL-A01.
    function test_givenGrant_whenUnrelatedAccountCancels_authorityUnchanged(
        address caller_
    ) public {
        vm.assume(caller_ != _account && caller_ != _operator);
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.prank(caller_);
        _auth.cancelGrant(_operator);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Cannot cancel another account"
        );
    }

    // Scenarios: OACANCEL-L01.
    function test_givenAdmissionDisabled_whenCancelled() public {
        _approve(_grant(true));
        _auth.setCreationAllowed(false);
        _auth.setUseAllowed(false);
        vm.prank(_account);
        _auth.cancelGrant(_operator);
        assertEq(_auth.pairEpochs(_account, _operator), 2, "Cancellation bypasses readiness");
    }

    // Scenarios: OACANCEL-N01.
    function test_givenPairMax_whenCancelled_reverts() public {
        _pairEpoch(type(uint256).max);
        vm.prank(_account);
        vm.expectRevert(IOperatorAuth.OperatorAuth_EpochExhausted.selector);
        _auth.cancelGrant(_operator);
    }

    // Scenarios: OACANCEL-P02.
    function test_whenOtherOperatorCancelled_preservesCurrentPair() public {
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.prank(_account);
        _auth.cancelGrant(address(0xCAFE));
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Pairs are independent"
        );
    }
}
// forge-lint: disable-end(unused-return)
