// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {MessageHashUtils} from "@openzeppelin-5.3.0/utils/cryptography/MessageHashUtils.sol";

// Contracts
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

contract OperatorAuthHarness is OperatorAuth {
    function requireSenderAuthorized(address sender_, address onBehalfOf_) external view {
        _requireSenderAuthorized(sender_, onBehalfOf_);
    }
}

abstract contract OperatorAuthTest is Test {
    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint48 authorizationDeadline
    );

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 internal constant AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );

    uint48 internal constant START = 1000;

    OperatorAuthHarness internal auth;

    address internal owner;
    uint256 internal ownerKey;
    address internal otherOwner;
    address internal operator;
    address internal otherOperator;
    address internal caller;
    uint256 internal callerKey;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        otherOwner = makeAddr("otherOwner");
        operator = makeAddr("operator");
        otherOperator = makeAddr("otherOperator");
        (caller, callerKey) = makeAddrAndKey("caller");
        auth = new OperatorAuthHarness();
        vm.warp(START);
    }

    function _authorization(
        address account_,
        address authorized_,
        uint48 authorizationDeadline_,
        uint256 nonce_,
        uint48 signatureDeadline_
    ) internal pure returns (IOperatorAuth.Authorization memory authorization) {
        authorization = IOperatorAuth.Authorization({
            account: account_,
            authorized: authorized_,
            authorizationDeadline: authorizationDeadline_,
            nonce: nonce_,
            signatureDeadline: signatureDeadline_
        });
    }

    function _signedAuthorization(
        address account_,
        uint256 accountKey_,
        address authorized_,
        uint48 authorizationDeadline_,
        uint256 nonce_,
        uint48 signatureDeadline_
    )
        internal
        view
        returns (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        )
    {
        authorization = _authorization(
            account_,
            authorized_,
            authorizationDeadline_,
            nonce_,
            signatureDeadline_
        );
        signature = _signWithDomain(authorization, accountKey_, auth.DOMAIN_SEPARATOR());
    }

    function _signWithDomain(
        IOperatorAuth.Authorization memory authorization_,
        uint256 accountKey_,
        bytes32 domainSeparator_
    ) internal pure returns (IOperatorAuth.Signature memory signature) {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization_));
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator_, structHash);
        (signature.v, signature.r, signature.s) = vm.sign(accountKey_, digest);
    }

    function _recoverSigner(
        IOperatorAuth.Authorization memory authorization_,
        IOperatorAuth.Signature memory signature_,
        bytes32 domainSeparator_
    ) internal pure returns (address) {
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization_));
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator_, structHash);
        return ecrecover(digest, signature_.v, signature_.r, signature_.s);
    }

    function _domainSeparator(
        uint256 chainId_,
        address verifyingContract_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, chainId_, verifyingContract_));
    }

    function _setAuthorizationAndExpectEvent(
        address owner_,
        address authorized_,
        uint48 deadline_
    ) internal {
        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner_, owner_, authorized_, deadline_);

        vm.prank(owner_);
        auth.setAuthorization(authorized_, deadline_);
    }

    function _submitValidAuthorization(
        uint48 authorizationDeadline_
    ) internal returns (IOperatorAuth.Authorization memory authorization) {
        IOperatorAuth.Signature memory signature;
        (authorization, signature) = _signedAuthorization(
            owner,
            ownerKey,
            operator,
            authorizationDeadline_,
            auth.authorizationNonces(owner),
            uint48(block.timestamp + 1 hours)
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }
}
