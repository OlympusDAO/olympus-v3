// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ECDSA} from "@openzeppelin-5.7.0/utils/cryptography/ECDSA.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreService} from "./fixtures/CoreService.sol";

contract BurnerLoansCoreSetAuthorizationWithSigTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-AUTH-SIG-A02, BLCORE-AUTH-SIG-A03, BLCORE-AUTH-SIG-A04, BLCORE-AUTH-SIG-P02, BLCORE-AUTH-SIG-V01, BLCORE-AUTH-SIG-P06.
    function test_givenValidSignature_whenRelayed(
        address relayer_,
        uint48 now_,
        uint48 deadline_,
        uint48 signatureDeadline_,
        uint256 nonce_
    ) public {
        vm.warp(now_);
        deadline_ = _bounds48(deadline_, now_, type(uint48).max);
        signatureDeadline_ = _bounds48(signatureDeadline_, now_, type(uint48).max);
        nonce_ = bound(nonce_, 0, type(uint256).max - 1);
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        auth.authorizationDeadline = deadline_;
        auth.signatureDeadline = signatureDeadline_;
        auth.nonce = nonce_;
        _setNonce(auth.account, nonce_);
        IOperatorAuth.Signature memory sig = _sign(auth, _SIGNER_KEY, _core.DOMAIN_SEPARATOR());
        vm.expectEmit(true, true, true, true, address(_core));
        emit IOperatorAuth.AuthorizationSet(relayer_, auth.account, auth.authorized, deadline_);
        vm.prank(relayer_);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), nonce_ + 1, "Only signer nonce consumed");
        assertEq(
            _core.authorizationDeadlines(auth.account, auth.authorized),
            deadline_,
            "Signed deadline stored unchanged"
        );
        assertTrue(
            _core.isSenderAuthorized(auth.authorized, auth.account),
            "Signed operator authorized"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A02, BLCORE-AUTH-SIG-A04, BLCORE-AUTH-SIG-V01, BLCORE-AUTH-SIG-P06.
    function test_whenSignatureBoundarySeeds() public {
        test_givenValidSignature_whenRelayed(address(0), 0, 0, 0, 0);
        test_givenValidSignature_whenRelayed(_recipient, 1, 1, 1, 1);
        test_givenValidSignature_whenRelayed(
            _recipient,
            type(uint48).max,
            type(uint48).max,
            type(uint48).max,
            type(uint256).max - 1
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A01, BLCORE-AUTH-SIG-V02.
    function test_givenExpiredSignature_whenRelayed_reverts(
        uint48 now_,
        uint48 deadline_,
        bool bothExpired_
    ) public {
        now_ = _bounds48(now_, 1, type(uint48).max);
        deadline_ = _bounds48(deadline_, 0, now_ - 1);
        vm.warp(now_);
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        auth.signatureDeadline = deadline_;
        if (bothExpired_) auth.authorizationDeadline = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredSignature.selector, deadline_)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Signature expiry leaves nonce unchanged"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A01, BLCORE-AUTH-SIG-V02.
    function test_whenSignatureExpiryBoundarySeeds_reverts() public {
        test_givenExpiredSignature_whenRelayed_reverts(1, 0, true);
        test_givenExpiredSignature_whenRelayed_reverts(
            type(uint48).max,
            type(uint48).max - 1,
            false
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A05.
    function test_givenExpiredAuthorizationAndSelf_whenRelayed_reverts() public {
        vm.warp(1);
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        auth.authorizationDeadline = 0;
        auth.authorized = auth.account;
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_ExpiredAuthorization.selector,
                uint48(0)
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Authorization expiry precedes self check"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-P01.
    function test_givenSelfGrant_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        auth.authorized = auth.account;
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfAuthorization.selector);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Self grant consumes no nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A06.
    function test_givenWrongNonce_whenRelayed_reverts(uint256 nonce_) public {
        vm.assume(nonce_ != 0);
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        auth.nonce = nonce_;
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, nonce_)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Wrong nonce cannot advance signer state"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A11.
    function test_givenExhaustedNonce_whenMatchingSignatureRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        auth.nonce = type(uint256).max;
        _setNonce(auth.account, auth.nonce);
        IOperatorAuth.Signature memory sig = _sign(auth, _SIGNER_KEY, _core.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_NonceExhausted.selector, auth.account)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationDeadlines(auth.account, auth.authorized),
            0,
            "Exhaustion cannot create grant"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A06.
    function test_givenExhaustedNonceAndMismatch_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        _setNonce(auth.account, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 0)
        );
        _core.setAuthorizationWithSig(auth, sig);
    }

    // Scenarios: BLCORE-AUTH-SIG-A07.
    function test_givenHighS_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        sig.s = bytes32(
            uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141) -
                uint256(sig.s)
        );
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, sig.s));
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Failed recovery rolls back provisional nonce"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A08.
    function test_givenBadV_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        sig.v = 0;
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Invalid ECDSA rolls back provisional nonce"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A08.
    function test_givenZeroRecovery_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        sig = IOperatorAuth.Signature(27, bytes32(0), bytes32(0));
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Invalid ECDSA rolls back provisional nonce"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A09.
    function test_givenDifferentSigner_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Signature memory sig = _sign(auth, 0xBEEF, _core.DOMAIN_SEPARATOR());
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                vm.addr(0xBEEF),
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Wrong signer consumes no nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenWrongChain_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid + 1,
                address(_core)
            )
        );
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenWrongCore_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                block.chainid,
                address(_debt)
            )
        );
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenWrongDomain_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        domain = bytes32(uint256(1));
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenAlteredAccount_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        signed.account = address(0xBEEF);
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenAlteredOperator_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        signed.authorized = address(0xCAFE);
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenAlteredAuthorizationDeadline_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        signed.authorizationDeadline--;
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenAlteredNonce_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        signed.nonce = 1;
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A10.
    function test_givenAlteredSignatureDeadline_whenRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        IOperatorAuth.Authorization memory signed = IOperatorAuth.Authorization(
            auth.account,
            auth.authorized,
            auth.authorizationDeadline,
            auth.nonce,
            auth.signatureDeadline
        );
        bytes32 domain = _core.DOMAIN_SEPARATOR();
        signed.signatureDeadline--;
        IOperatorAuth.Signature memory sig = _sign(signed, _SIGNER_KEY, domain);
        bytes32 typeHash = keccak256(
            "Authorization(address account,address authorized,uint48 authorizationDeadline,uint256 nonce,uint48 signatureDeadline)"
        );
        address recovered = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _core.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(typeHash, auth))
                )
            ),
            sig.v,
            sig.r,
            sig.s
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IOperatorAuth.OperatorAuth_InvalidSigner.selector,
                recovered,
                auth.account
            )
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Tampered payload rolls back nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A13.
    function test_givenValidSignature_whenReplayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        _core.setAuthorizationWithSig(auth, sig);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 0)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 1, "Replay cannot consume another nonce");
    }

    // Scenarios: BLCORE-AUTH-SIG-A14.
    function test_givenCancellation_whenOldSignatureRelayed_reverts() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        vm.prank(auth.account);
        _core.cancelAuthorization(auth.authorized);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 0)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationDeadlines(auth.account, auth.authorized),
            0,
            "Old signature cannot restore cancelled grant"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-L01, BLCORE-AUTH-SIG-L02, BLCORE-AUTH-SIG-L03.
    function test_givenUnavailableCore_whenRelayed_reverts(
        address relayer_,
        bool active_,
        bool enabled_,
        bool malformed_
    ) public {
        vm.assume(!active_ || !enabled_);
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        if (malformed_) sig = IOperatorAuth.Signature(0, bytes32(0), bytes32(0));
        _setCoreLifecycle(active_, enabled_);
        vm.recordLogs();
        vm.expectRevert(
            active_
                ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                : abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
        );
        vm.prank(relayer_);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(_core.authorizationNonces(auth.account), 0, "Unavailable Core consumes no nonce");
        assertEq(
            _core.authorizationDeadlines(auth.account, auth.authorized),
            0,
            "Unavailable Core creates no grant"
        );
        assertEq(vm.getRecordedLogs().length, 0, "Admission failure emits no grant logs");
    }

    // Scenarios: BLCORE-AUTH-SIG-P07.
    function test_givenRestoredCore_whenSignatureRetried(
        address relayer_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        _setCoreLifecycle(active_, enabled_);
        vm.expectRevert(
            active_
                ? abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                : abi.encodeWithSelector(
                    IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                    address(_core)
                )
        );
        _core.setAuthorizationWithSig(auth, sig);
        _restoreCore(active_, enabled_);
        vm.prank(relayer_);
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            1,
            "Only successful retry consumes nonce"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidNonce.selector, 0)
        );
        _core.setAuthorizationWithSig(auth, sig);
    }

    // Scenarios: BLCORE-AUTH-SIG-P08.
    function test_givenExpiryDuringPause_whenRetried_reverts(
        uint48 deadline_,
        uint48 elapsed_
    ) public {
        deadline_ = _bounds48(deadline_, uint48(vm.getBlockTimestamp()), type(uint48).max - 1);
        elapsed_ = _bounds48(elapsed_, 1, type(uint48).max - deadline_);
        (IOperatorAuth.Authorization memory auth, ) = _grant();
        auth.signatureDeadline = deadline_;
        IOperatorAuth.Signature memory sig = _sign(auth, _SIGNER_KEY, _core.DOMAIN_SEPARATOR());
        _core.disable("");
        vm.warp(uint256(deadline_) + elapsed_);
        _core.enable("");
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredSignature.selector, deadline_)
        );
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            0,
            "Pause does not extend signed validity"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A12.
    function test_givenActionReplacement_whenRelayed() public {
        (IOperatorAuth.Authorization memory auth, IOperatorAuth.Signature memory sig) = _grant();
        CoreService replacement = _service();
        _rolesAdmin.revokeRole(BL_DEBT_POLICY_ROLE, address(_debt));
        _rolesAdmin.grantRole(BL_DEBT_POLICY_ROLE, address(replacement));
        _core.setAuthorizationWithSig(auth, sig);
        assertEq(
            _core.authorizationNonces(auth.account),
            1,
            "Core domain survives public action replacement"
        );
    }

    // Scenarios: BLCORE-AUTH-SIG-A06.
    function test_whenNonceMismatchMaximumSeed_reverts() public {
        test_givenWrongNonce_whenRelayed_reverts(type(uint256).max);
    }
}
