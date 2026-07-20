// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ECDSA} from "@openzeppelin-5.3.0/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin-5.3.0/utils/cryptography/MessageHashUtils.sol";

// Contracts
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

contract OperatorAuthHarness is OperatorAuth {
    function requireSenderAuthorized(address sender_, address onBehalfOf_) external view {
        _requireSenderAuthorized(sender_, onBehalfOf_);
    }
}

contract OperatorAuthTest is Test {
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

    function test_isSenderAuthorized_givenSelf_returnsTrue() public view {
        assertEq(auth.isSenderAuthorized(owner, owner), true, "owner authorized");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "operator unauthorized");
    }

    function test_DOMAIN_SEPARATOR_matchesDeploymentDomain() public view {
        assertEq(
            auth.DOMAIN_SEPARATOR(),
            _domainSeparator(block.chainid, address(auth)),
            "domain separator"
        );
    }

    function test_setAuthorization_givenBeforeDeadline_authorizesOperator() public {
        uint48 deadline = uint48(block.timestamp + 1 days);

        _setAuthorizationAndExpectEvent(owner, operator, deadline);

        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before deadline");
    }

    function test_setAuthorization_givenTimestampUpToAndIncludingDeadline_authorizes(
        uint48 deadline_,
        uint48 checkTimestamp_
    ) public {
        uint48 deadline = uint48(bound(deadline_, block.timestamp, type(uint48).max));
        uint48 checkTimestamp = uint48(bound(checkTimestamp_, block.timestamp, deadline));

        _setAuthorizationAndExpectEvent(owner, operator, deadline);
        vm.warp(checkTimestamp);

        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized through deadline");
    }

    function test_setAuthorization_givenTimestampAfterDeadline_unauthorizes(
        uint48 deadline_,
        uint48 checkTimestamp_
    ) public {
        uint48 deadline = uint48(bound(deadline_, block.timestamp, type(uint48).max - 1));
        uint48 checkTimestamp = uint48(
            bound(checkTimestamp_, uint256(deadline) + 1, type(uint48).max)
        );

        _setAuthorizationAndExpectEvent(owner, operator, deadline);
        vm.warp(checkTimestamp);

        assertEq(auth.isSenderAuthorized(operator, owner), false, "unauthorized after deadline");
    }

    function test_setAuthorization_givenHistoricalDeadline_reverts(
        uint48 blockTimestamp_,
        uint48 deadline_
    ) public {
        uint48 blockTimestamp = uint48(bound(blockTimestamp_, 1, type(uint48).max));
        uint48 deadline = uint48(bound(deadline_, 0, uint256(blockTimestamp) - 1));
        vm.warp(blockTimestamp);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredAuthorization.selector,
                deadline
            )
        );
        auth.setAuthorization(operator, deadline);
    }

    function test_setAuthorization_givenSelfAuthorization_reverts() public {
        vm.prank(owner);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfAuthorization.selector);
        auth.setAuthorization(owner, uint48(block.timestamp + 1 days));
    }

    function test_setAuthorization_givenCallerIsNotOwner_authorizesOnlyCaller() public {
        uint48 deadline = uint48(block.timestamp + 1 days);

        vm.prank(caller);
        auth.setAuthorization(operator, deadline);

        assertEq(auth.authorizationDeadlines(caller, operator), deadline, "caller authorization");
        assertEq(auth.authorizationDeadlines(owner, operator), 0, "owner authorization");
    }

    function test_setAuthorization_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        uint256 nonceBefore = auth.authorizationNonces(owner);

        _setAuthorizationAndExpectEvent(owner, otherOperator, uint48(block.timestamp + 2 days));

        assertEq(
            auth.authorizationNonces(owner),
            nonceBefore + 1,
            "nonce after direct authorization"
        );
    }

    function test_setAuthorization_givenPendingSignature_invalidatesSignature() public {
        uint48 directDeadline = uint48(block.timestamp + 1 days);
        uint48 signedDeadline = uint48(block.timestamp + 2 days);
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                signedDeadline,
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        _setAuthorizationAndExpectEvent(owner, operator, directDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidNonce.selector,
                authorization.nonce
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(
            auth.authorizationNonces(owner),
            authorization.nonce + 1,
            "nonce after direct authorization"
        );
        assertEq(
            auth.authorizationDeadlines(owner, operator),
            directDeadline,
            "direct authorization deadline"
        );
    }

    function test_cancelAuthorization_givenNoAuthorizationExists_clearsWithoutRevert() public {
        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenDirectAuthorizationExists_clearsAuthorization() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenSignedAuthorizationExists_clearsAuthorization() public {
        _submitValidAuthorization(uint48(block.timestamp + 1 days));
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized before cancel");

        vm.expectEmit(address(auth));
        emit AuthorizationSet(owner, owner, operator, 0);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "stored deadline");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "authorized after cancel");
    }

    function test_cancelAuthorization_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        uint256 nonceBefore = auth.authorizationNonces(owner);

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationNonces(owner), nonceBefore + 1, "nonce after cancellation");
    }

    function test_cancelAuthorization_givenPendingSignature_invalidatesSignature() public {
        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 2 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        vm.prank(owner);
        auth.cancelAuthorization(operator);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidNonce.selector,
                authorization.nonce
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(
            auth.authorizationNonces(owner),
            authorization.nonce + 1,
            "nonce after cancellation"
        );
        assertEq(auth.authorizationDeadlines(owner, operator), 0, "cancelled authorization");
        assertEq(auth.isSenderAuthorized(operator, owner), false, "operator after cancellation");
    }

    function test_cancelAuthorization_givenCallerIsNotOwner_clearsOnlyCallerAuthorization() public {
        uint48 ownerDeadline = uint48(block.timestamp + 1 days);
        _setAuthorizationAndExpectEvent(owner, operator, ownerDeadline);

        vm.prank(caller);
        auth.setAuthorization(operator, uint48(block.timestamp + 2 days));

        vm.prank(caller);
        auth.cancelAuthorization(operator);

        assertEq(auth.authorizationDeadlines(caller, operator), 0, "caller authorization");
        assertEq(
            auth.authorizationDeadlines(owner, operator),
            ownerDeadline,
            "owner authorization"
        );
        assertEq(auth.isSenderAuthorized(operator, owner), true, "owner still authorized");
    }

    function test_requireSenderAuthorized_checksAuthorization() public {
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(operator, owner);

        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));

        auth.requireSenderAuthorized(operator, owner);
    }

    function test_requireSenderAuthorized_givenUnauthorizedCaller_reverts(address sender_) public {
        vm.assume(sender_ != owner);
        vm.assume(sender_ != operator);

        _setAuthorizationAndExpectEvent(owner, operator, uint48(block.timestamp + 1 days));

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        auth.requireSenderAuthorized(sender_, owner);
    }

    function test_setAuthorizationWithSig_givenValidSignature_setsAuthorizationAndConsumesNonce(
        uint48 authorizationDeadline_
    ) public {
        uint48 authorizationDeadline = uint48(
            bound(authorizationDeadline_, block.timestamp, type(uint48).max)
        );
        uint48 signatureDeadline = uint48(block.timestamp + 1 hours);
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                authorizationDeadline,
                auth.authorizationNonces(owner),
                signatureDeadline
            );

        vm.expectEmit(address(auth));
        emit AuthorizationSet(caller, owner, operator, authorizationDeadline);

        vm.prank(caller);
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 1, "nonce");
        assertEq(auth.authorizationDeadlines(owner, operator), authorizationDeadline, "deadline");
        assertEq(auth.authorizationDeadlines(owner, caller), 0, "caller not authorized");
        assertEq(auth.authorizationDeadlines(caller, operator), 0, "caller account not changed");
        assertEq(auth.isSenderAuthorized(operator, owner), true, "authorized");
    }

    function test_setAuthorizationWithSig_givenExistingNonce() public {
        _setAuthorizationAndExpectEvent(owner, otherOperator, uint48(block.timestamp + 1 days));
        uint256 nonceBefore = auth.authorizationNonces(owner);
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 2 days),
                nonceBefore,
                uint48(block.timestamp + 1 hours)
            );

        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(
            auth.authorizationNonces(owner),
            nonceBefore + 1,
            "nonce after signature authorization"
        );
    }

    function test_setAuthorizationWithSig_givenSelfAuthorization_reverts() public {
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                owner,
                uint48(block.timestamp + 1 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfAuthorization.selector);
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 0, "nonce");
        assertEq(auth.authorizationDeadlines(owner, owner), 0, "self deadline");
    }

    function test_setAuthorizationWithSig_givenHistoricalAuthorizationDeadline_reverts(
        uint48 blockTimestamp_,
        uint48 authorizationDeadline_
    ) public {
        uint48 blockTimestamp = uint48(bound(blockTimestamp_, 1, type(uint48).max));
        uint48 authorizationDeadline = uint48(
            bound(authorizationDeadline_, 0, uint256(blockTimestamp) - 1)
        );
        vm.warp(blockTimestamp);

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                authorizationDeadline,
                auth.authorizationNonces(owner),
                type(uint48).max
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredAuthorization.selector,
                authorizationDeadline
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 0, "nonce");
    }

    function test_setAuthorizationWithSig_givenExpiredSignature_reverts(
        uint48 signatureDeadline_,
        uint48 blockTimestamp_
    ) public {
        uint48 signatureDeadline = uint48(bound(signatureDeadline_, 0, type(uint48).max - 1));
        uint48 blockTimestamp = uint48(
            bound(blockTimestamp_, uint256(signatureDeadline) + 1, type(uint48).max)
        );
        vm.warp(blockTimestamp);

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                blockTimestamp,
                auth.authorizationNonces(owner),
                signatureDeadline
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredSignature.selector,
                signatureDeadline
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 0, "nonce");
    }

    function test_setAuthorizationWithSig_givenReplay_reverts() public {
        IOperatorAuth.Authorization memory authorization = _submitValidAuthorization(
            uint48(block.timestamp + 1 days)
        );
        IOperatorAuth.Signature memory signature = _signWithDomain(
            authorization,
            ownerKey,
            auth.DOMAIN_SEPARATOR()
        );

        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 0)
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenSequentialExactNonces_succeeds() public {
        _submitValidAuthorization(uint48(block.timestamp + 1 days));

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                otherOperator,
                uint48(block.timestamp + 2 days),
                1,
                uint48(block.timestamp + 1 hours)
            );

        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 2, "nonce");
        assertEq(auth.isSenderAuthorized(otherOperator, owner), true, "second operator");
    }

    function test_authorizationNonces_returnsNextSignatureNonce() public {
        assertEq(auth.authorizationNonces(owner), 0, "initial nonce");

        _submitValidAuthorization(uint48(block.timestamp + 1 days));
        assertEq(auth.authorizationNonces(owner), 1, "nonce after first authorization");

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                otherOperator,
                uint48(block.timestamp + 2 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );

        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationNonces(owner), 2, "nonce after second authorization");
    }

    function test_setAuthorizationWithSig_givenPreviousNonce_reverts(uint256 nonce_) public {
        _submitValidAuthorization(uint48(block.timestamp + 1 days));
        _submitValidAuthorization(uint48(block.timestamp + 2 days));
        uint256 nonce = bound(nonce_, 0, auth.authorizationNonces(owner) - 1);

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 3 days),
                nonce,
                uint48(block.timestamp + 1 hours)
            );

        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, nonce)
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenCallerSignsForDifferentAccount_reverts() public {
        IOperatorAuth.Authorization memory authorization = _authorization(
            owner,
            operator,
            uint48(block.timestamp + 1 days),
            auth.authorizationNonces(owner),
            uint48(block.timestamp + 1 hours)
        );
        IOperatorAuth.Signature memory signature = _signWithDomain(
            authorization,
            callerKey,
            auth.DOMAIN_SEPARATOR()
        );

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidSigner.selector, caller, owner)
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "owner authorization");
        assertEq(auth.authorizationDeadlines(caller, operator), 0, "caller authorization");
    }

    function test_setAuthorizationWithSig_givenSkippedNonce_reverts() public {
        _submitValidAuthorization(uint48(block.timestamp + 1 days));

        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 2 days),
                3,
                uint48(block.timestamp + 1 hours)
            );

        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 3)
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenDifferentOwner_reverts() public {
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                otherOwner,
                ownerKey,
                operator,
                uint48(block.timestamp + 1 days),
                auth.authorizationNonces(otherOwner),
                uint48(block.timestamp + 1 hours)
            );

        address recovered = _recoverSigner(authorization, signature, auth.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                otherOwner
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationDeadlines(otherOwner, operator), 0, "other owner authorization");
    }

    function test_setAuthorizationWithSig_givenDifferentOperator_reverts() public {
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 1 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );
        authorization.authorized = otherOperator;

        address recovered = _recoverSigner(authorization, signature, auth.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                owner
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);

        assertEq(auth.authorizationDeadlines(owner, operator), 0, "original operator");
        assertEq(auth.authorizationDeadlines(owner, otherOperator), 0, "mutated operator");
    }

    function test_setAuthorizationWithSig_givenDifferentContractDomain_reverts() public {
        OperatorAuthHarness otherAuth = new OperatorAuthHarness();
        IOperatorAuth.Authorization memory authorization = _authorization(
            owner,
            operator,
            uint48(block.timestamp + 1 days),
            auth.authorizationNonces(owner),
            uint48(block.timestamp + 1 hours)
        );
        IOperatorAuth.Signature memory signature = _signWithDomain(
            authorization,
            ownerKey,
            otherAuth.DOMAIN_SEPARATOR()
        );

        address recovered = _recoverSigner(authorization, signature, auth.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                owner
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenDifferentChainDomain_reverts() public {
        IOperatorAuth.Authorization memory authorization = _authorization(
            owner,
            operator,
            uint48(block.timestamp + 1 days),
            auth.authorizationNonces(owner),
            uint48(block.timestamp + 1 hours)
        );
        IOperatorAuth.Signature memory signature = _signWithDomain(
            authorization,
            ownerKey,
            _domainSeparator(block.chainid + 1, address(auth))
        );

        address recovered = _recoverSigner(authorization, signature, auth.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                owner
            )
        );
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenInvalidV_reverts() public {
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 1 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );
        signature.v = 1;

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        auth.setAuthorizationWithSig(authorization, signature);
    }

    function test_setAuthorizationWithSig_givenHighS_reverts() public {
        (
            IOperatorAuth.Authorization memory authorization,
            IOperatorAuth.Signature memory signature
        ) = _signedAuthorization(
                owner,
                ownerKey,
                operator,
                uint48(block.timestamp + 1 days),
                auth.authorizationNonces(owner),
                uint48(block.timestamp + 1 hours)
            );
        signature.s = bytes32(0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1);

        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, signature.s));
        auth.setAuthorizationWithSig(authorization, signature);
    }
}
