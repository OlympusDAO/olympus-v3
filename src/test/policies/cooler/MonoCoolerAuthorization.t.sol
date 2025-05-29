// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IMonoCooler} from "policies/interfaces/cooler/IMonoCooler.sol";

contract MonoCoolerAuthorization is MonoCoolerBaseTest {
    event AuthorizationSet(
        address indexed caller,
        address indexed account,
        address indexed authorized,
        uint96 authorizationDeadline
    );

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)"
        );

    function buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(cooler)));
    }

    function signedAuth(
        address account,
        uint256 accountPk,
        address authorized,
        uint96 authorizationDeadline,
        uint256 signatureDeadline
    )
        internal
        view
        returns (IMonoCooler.Authorization memory auth, IMonoCooler.Signature memory sig)
    {
        bytes32 domainSeparator = buildDomainSeparator();
        auth = IMonoCooler.Authorization({
            account: account,
            authorized: authorized,
            authorizationDeadline: authorizationDeadline,
            nonce: cooler.authorizationNonces(account),
            signatureDeadline: signatureDeadline
        });
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, auth));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (sig.v, sig.r, sig.s) = vm.sign(accountPk, typedDataHash);
    }

    function test_isSenderAuthorized_self() public view {
        assertEq(cooler.isSenderAuthorized(BOB, ALICE), false);
        assertEq(cooler.isSenderAuthorized(ALICE, ALICE), true);
    }

    function test_setAuthorization_beforeAtAfterDeadline() public {
        assertEq(cooler.isSenderAuthorized(BOB, ALICE), false);
        vm.startPrank(ALICE);
        vm.expectEmit(address(cooler));
        emit AuthorizationSet(ALICE, ALICE, BOB, uint96(vm.getBlockTimestamp() + 1));
        cooler.setAuthorization(BOB, uint96(vm.getBlockTimestamp() + 1));
        assertEq(cooler.isSenderAuthorized(BOB, ALICE), true);

        // Still ok on the deadline
        skip(1);
        assertEq(cooler.isSenderAuthorized(BOB, ALICE), true);

        // Rugged 1sec later
        skip(1);
        assertEq(cooler.isSenderAuthorized(BOB, ALICE), false);
    }

    function test_setAuthorizationWithSig() public {
        (address accountOwner, uint256 accountOwnerPk) = makeAddrAndKey("ACCOUNT_OWNER");
        uint96 authorizationDeadline = uint96(vm.getBlockTimestamp() + 1);

        // Starts as not authorized
        assertEq(cooler.isSenderAuthorized(BOB, accountOwner), false);

        // Check for expired deadlines
        uint256 signatureDeadline = vm.getBlockTimestamp() - 1;
        IMonoCooler.Authorization memory auth;
        IMonoCooler.Signature memory sig;
        {
            (auth, sig) = signedAuth(
                accountOwner,
                accountOwnerPk,
                BOB,
                authorizationDeadline,
                signatureDeadline
            );
            vm.expectRevert(
                abi.encodeWithSelector(IMonoCooler.ExpiredSignature.selector, signatureDeadline)
            );
            cooler.setAuthorizationWithSig(auth, sig);
        }

        // Successfully gives authorization if in future
        // ALICE actually calls using the signature pre-signed by `accountOwner`
        {
            signatureDeadline = vm.getBlockTimestamp() + 3600;
            (auth, sig) = signedAuth(
                accountOwner,
                accountOwnerPk,
                BOB,
                authorizationDeadline,
                signatureDeadline
            );

            vm.startPrank(ALICE);
            vm.expectEmit(address(cooler));
            emit AuthorizationSet(ALICE, accountOwner, BOB, authorizationDeadline);
            cooler.setAuthorizationWithSig(auth, sig);
            assertEq(cooler.isSenderAuthorized(BOB, accountOwner), true);
            assertEq(cooler.isSenderAuthorized(ALICE, accountOwner), false);

            // Still ok 1sec later (on the deadline)
            skip(1);
            assertEq(cooler.isSenderAuthorized(BOB, accountOwner), true);
            assertEq(cooler.isSenderAuthorized(ALICE, accountOwner), false);

            // Rugged 1sec later
            skip(1);
            assertEq(cooler.isSenderAuthorized(BOB, accountOwner), false);
            assertEq(cooler.isSenderAuthorized(ALICE, accountOwner), false);
        }

        // Can't re-use the same signature for another permit (the nonce was incremented)
        {
            vm.expectRevert(abi.encodeWithSelector(IMonoCooler.InvalidNonce.selector, 0));
            cooler.setAuthorizationWithSig(auth, sig);
        }

        // Success again to show nonce increment works
        {
            (auth, sig) = signedAuth(
                accountOwner,
                accountOwnerPk,
                BOB,
                authorizationDeadline + 10,
                signatureDeadline
            );
            cooler.setAuthorizationWithSig(auth, sig);
            assertEq(cooler.isSenderAuthorized(BOB, accountOwner), true);
            assertEq(cooler.isSenderAuthorized(ALICE, accountOwner), false);
            assertEq(cooler.authorizationNonces(accountOwner), 2);
        }

        // Fails with an incorrect signature
        {
            (auth, sig) = signedAuth(
                accountOwner,
                accountOwnerPk,
                BOB,
                authorizationDeadline + 10,
                signatureDeadline
            );
            auth.account = ALICE;
            auth.nonce = 0;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IMonoCooler.InvalidSigner.selector,
                    0xD36ED23d73671445c86Ef402F5F5035Ba1B2D4f3,
                    ALICE
                )
            );
            cooler.setAuthorizationWithSig(auth, sig);
        }
    }
}
