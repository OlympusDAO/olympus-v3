// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthCaptureAuthorizationTest is OperatorAuthTest {
    // Scenarios: OACAPTURE-A02.
    function test_givenOperatorGrantsAnotherOperator_whenOriginalAccountCaptured_reverts(
        address third_
    ) public {
        vm.assume(third_ != address(0) && third_ != _account && third_ != _operator);
        IOperatorAuth.Grant memory grant = _grant(true);
        _approve(grant);
        bytes32 original = _auth.captureAuthorization(_account, _operator, 1);
        // O may authorize X for O's own account; this must not subdelegate A's grant to O.
        grant.account = _operator;
        grant.operator = third_;
        _approve(grant);
        bytes32 delegated = _auth.captureAuthorization(_operator, third_, 1);
        _expectInvalidContext();
        _auth.captureAuthorization(_account, third_, 1);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            original,
            "Account's original grant remains unchanged"
        );
        assertEq(
            _auth.captureAuthorization(_operator, third_, 1),
            delegated,
            "Operator controls only its own account grant"
        );
    }

    // Scenarios: OACAPTURE-P01.
    function test_whenOwnerCaptures_hasIntrinsicAuthority(address owner_) public view {
        vm.assume(owner_ != address(0));
        assertEq(
            _auth.captureAuthorization(owner_, owner_, 1),
            bytes32(0),
            "Owners use zero grant stamp"
        );
        assertEq(
            _auth.validateAuthorization(owner_, owner_, 1, 0).length,
            0,
            "Owner permissions are empty"
        );
    }

    // Scenarios: OACAPTURE-I01.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenOwnerChecksUnsupportedAction_reverts(uint8 action_) public {
        action_ = uint8(bound(action_, 16, 255));
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidAction.selector, action_)
        );
        _auth.captureAuthorization(_account, _account, action_);
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: OACAPTURE-I02.
    function test_whenOwnerChecksCompositeAction_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidAction.selector, 3)
        );
        _auth.captureAuthorization(_account, _account, 3);
    }

    // Scenarios: OACAPTURE-I03.
    function test_whenOwnerChecksZeroAction_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidAction.selector, 0)
        );
        _auth.captureAuthorization(_account, _account, 0);
    }

    // Scenarios: OACAPTURE-I04.
    function test_whenZeroIdentities_reverts() public {
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        _auth.captureAuthorization(address(0), address(0), 1);
    }

    // Scenarios: OACAPTURE-I05.
    function test_givenNoGrant_whenCaptured_reverts() public {
        _expectInvalidContext();
        _auth.captureAuthorization(_account, _operator, 1);
    }

    // Scenarios: OACAPTURE-A01.
    function test_givenGrantToOperator_whenOtherOperatorCaptured_reverts(address other_) public {
        vm.assume(other_ != _account && other_ != _operator && other_ != address(0));
        _approve(_grant(true));
        _expectInvalidContext();
        _auth.captureAuthorization(_account, other_, 1);
    }

    // Scenarios: OACAPTURE-P02.
    function test_givenGrant_whenUnrelatedViewerChecks_sameAuthority(address viewer_) public {
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.prank(viewer_);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Permissionless view is not bearer authority"
        );
    }
}
// forge-lint: disable-end(unused-return)
