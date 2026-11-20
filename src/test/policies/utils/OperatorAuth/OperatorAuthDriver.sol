// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

contract OperatorAuthDriver {
    error IntentionalFailure();
    error UnexpectedState();
    IOperatorAuth internal immutable _auth;
    address internal immutable _operator;
    uint256 public uses;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(IOperatorAuth auth_, address operator_) {
        _auth = auth_;
        _operator = operator_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function _grant(
        bool multiple_,
        bytes memory permissions_
    ) internal view returns (IOperatorAuth.Grant memory) {
        return
            IOperatorAuth.Grant(
                address(this),
                _operator,
                _auth.accountEpochs(address(this)),
                _auth.pairEpochs(address(this), _operator),
                type(uint48).max,
                multiple_,
                15,
                _auth.authorizationContext(address(this), _operator),
                permissions_
            );
    }

    function approve(bool multiple_) external {
        _auth.approveGrant(_grant(multiple_, hex"010203"));
    }

    function approveTemporaryAndUseRepeatedly() external {
        _auth.approveGrant(_grant(false, hex"010203"));
        bytes32 stamp = _auth.captureAuthorization(address(this), _operator, 2);
        _auth.validateAuthorization(address(this), _operator, 2, stamp);
        uses++;
        _auth.validateAuthorization(address(this), _operator, 1, stamp);
        uses++;
        _auth.validateAuthorization(address(this), _operator, 2, stamp);
        uses++;
    }

    function approveTemporaryAndRead(
        bytes memory permissions_
    ) external returns (IOperatorAuth.Grant memory) {
        _auth.approveGrant(_grant(false, permissions_));
        bytes32 stamp = _auth.captureAuthorization(address(this), _operator, 1);
        if (
            keccak256(_auth.validateAuthorization(address(this), _operator, 1, stamp)) !=
            keccak256(permissions_)
        ) revert UnexpectedState();
        return _auth.getGrant(address(this), _operator);
    }

    function temporaryThenReusable() external {
        _auth.approveGrant(_grant(false, hex"ff"));
        _auth.approveGrant(_grant(true, hex"010203"));
        _auth.captureAuthorization(address(this), _operator, 1);
    }

    function longThenShortTemporary() external returns (bytes memory) {
        _auth.approveGrant(_grant(false, new bytes(320)));
        _auth.approveGrant(_grant(false, hex"ff"));
        return
            _auth.validateAuthorization(
                address(this),
                _operator,
                1,
                _auth.captureAuthorization(address(this), _operator, 1)
            );
    }

    function approveThenRevert() external {
        _auth.approveGrant(_grant(false, hex"ff"));
        revert IntentionalFailure();
    }

    function acceptThenCatchFailure() external returns (bytes memory) {
        _auth.approveGrant(_grant(false, hex"ff"));
        try this.failAction() {
            revert UnexpectedState();
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(IntentionalFailure.selector)))
                revert UnexpectedState();
        }
        return
            _auth.validateAuthorization(
                address(this),
                _operator,
                1,
                _auth.captureAuthorization(address(this), _operator, 1)
            );
    }

    function failAction() external pure {
        revert IntentionalFailure();
    }

    function replaceThenComplete() external {
        bytes32 stamp = _auth.captureAuthorization(address(this), _operator, 1);
        _auth.approveGrant(_grant(true, hex"010203"));
        _auth.validateAuthorization(address(this), _operator, 1, stamp);
    }
}
// forge-lint: disable-end(unused-return)
