// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ECDSA} from "@openzeppelin-5.3.0/utils/cryptography/ECDSA.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {OperatorAuthHarness, OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthSetAuthorizationWithSigTest is OperatorAuthTest {
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
