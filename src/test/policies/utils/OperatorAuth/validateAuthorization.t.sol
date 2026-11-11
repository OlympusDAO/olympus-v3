// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthHarness} from "./OperatorAuthHarness.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthValidateAuthorizationTest is OperatorAuthTest {
    // Scenarios: OAVALIDATE-A01.
    function test_givenSameOperatorForTwoAccounts_whenOtherAccountStampUsed_reverts(
        address other_
    ) public {
        vm.assume(other_ != address(0) && other_ != _account && other_ != _operator);
        IOperatorAuth.Grant memory grant = _grant(true);
        _approve(grant);
        bytes32 original = _auth.captureAuthorization(_account, _operator, 1);
        grant.account = other_;
        _approve(grant);
        bytes32 other = _auth.captureAuthorization(other_, _operator, 1);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _auth.validateAuthorization(other_, _operator, 1, original);
        assertEq(
            _auth.captureAuthorization(other_, _operator, 1),
            other,
            "Wrong account stamp preserves current authority"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            original,
            "Original account authority remains isolated"
        );
    }

    // Scenarios: OAVALIDATE-A02.
    function test_givenTwoOperatorsForAccount_whenOtherOperatorStampUsed_reverts(
        address other_
    ) public {
        vm.assume(other_ != address(0) && other_ != _account && other_ != _operator);
        IOperatorAuth.Grant memory grant = _grant(true);
        _approve(grant);
        bytes32 original = _auth.captureAuthorization(_account, _operator, 1);
        grant.operator = other_;
        _approve(grant);
        bytes32 other = _auth.captureAuthorization(_account, other_, 1);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        _auth.validateAuthorization(_account, other_, 1, original);
        assertEq(
            _auth.captureAuthorization(_account, other_, 1),
            other,
            "Wrong operator stamp preserves current authority"
        );
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            original,
            "Original operator authority remains isolated"
        );
    }

    // Scenarios: OAVALIDATE-P01.
    function test_givenOriginalStamp_whenValidated() public {
        _approve(_grant(true));
        bytes32 s = _auth.captureAuthorization(_account, _operator, 1);
        assertEq(
            _auth.validateAuthorization(_account, _operator, 1, s),
            hex"010203",
            "Original returns stored bytes"
        );
    }

    // Scenarios: OAVALIDATE-I01.
    function test_givenGrant_whenWrongStamp_reverts() public {
        _approve(_grant(true));
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, bytes32(uint256(1)));
    }

    // Scenarios: OAVALIDATE-I02.
    function test_whenOwnerSuppliesNonzeroStamp_reverts() public {
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _account, 1, bytes32(uint256(1)));
    }

    // Scenarios: OAVALIDATE-P02.
    function test_givenCapturedStamp_whenIdenticalPayloadReplaced_reverts() public {
        _approve(_grant(true));
        bytes32 s = _auth.captureAuthorization(_account, _operator, 1);
        _approve(_grant(true));
        _expectInvalidContext();
        _auth.validateAuthorization(_account, _operator, 1, s);
    }

    // Scenarios: OAVALIDATE-L01.
    function test_givenUseDisabled_whenOwnerValidates_reverts() public {
        _auth.setUseAllowed(false);
        vm.expectRevert(OperatorAuthHarness.UseDisabled.selector);
        _auth.validateAuthorization(_account, _account, 1, 0);
    }
}
// forge-lint: disable-end(unused-return)
