// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {Auth1271Wallet} from "src/test/policies/BurnerLoansAuth/fixtures/Auth1271Wallet.sol";
import {AuthKernelMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthKernelMock.sol";

contract BurnerLoansAuthAcceptGrantTest is BurnerLoansAuthTest {
    // Scenarios: BLAUTH-ACCEPT-I03.
    function test_givenSignedGrant_whenAssetUnregisteredBeforeAcceptance_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        _core.setAsset(_asset, false);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansAuth.BurnerLoansAuth_InvalidAsset.selector, _asset)
        );
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Invalid asset consumes no pair epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Invalid asset preserves account epoch");
        assertEq(_auth.getGrant(_account, _operator).account, address(0), "No grant is installed");
    }

    // Scenarios: BLAUTH-ACCEPT-D01.
    function test_givenForeignKernelReportsActive_whenSignedGrantAccepted_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        AuthKernelMock foreignKernel = new AuthKernelMock();
        vm.mockCall(
            address(_core),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(foreignKernel))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(foreignKernel)
            )
        );
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Wrong Kernel installs no signed grant");
        assertEq(
            _auth.accountEpochs(_account),
            0,
            "Wrong Kernel preserves account cancellation epoch"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-P01.
    function test_whenOperatorSubmitsEoaSignature() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
        assertEq(
            _auth.pairEpochs(_account, _operator),
            1,
            "EOA signature consumes one expected epoch"
        );
        assertTrue(
            _auth.captureAuthorization(_account, _operator, 2) != bytes32(0),
            "Accepted grant exposes a live immutable stamp"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-A01.
    function test_whenUnrelatedSubmitterForwardsSignature_reverts(address submitter_) public {
        vm.assume(submitter_ != _operator);
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(submitter_);
        _auth.acceptGrant(grant, "", signature);
    }

    // Scenarios: BLAUTH-ACCEPT-A01.
    function test_whenAccountSubmitsSignature_reverts() public {
        test_whenUnrelatedSubmitterForwardsSignature_reverts(_account);
        assertEq(_auth.pairEpochs(_account, _operator), 0, "Account submission consumes no epoch");
        assertEq(_auth.accountEpochs(_account), 0, "Account submission preserves its namespace");
        assertEq(_auth.getGrant(_account, _operator).account, address(0), "No grant is installed");
    }

    // Scenarios: BLAUTH-ACCEPT-I01.
    function test_whenSignedPermissionAltered_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        bytes memory signature = _sign(grant, _auth);
        grant.permissions[63] = bytes1(uint8(1));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", signature);
    }

    // Scenarios: BLAUTH-ACCEPT-I02.
    function test_whenExtraSignatureDataSupplied_reverts() public {
        IOperatorAuth.Grant memory grant = _grant(15, true);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnsupportedSignatureData.selector);
        vm.prank(_operator);
        _auth.acceptGrant(grant, hex"01", hex"01");
    }

    // Scenarios: BLAUTH-ACCEPT-C01.
    function test_whenContractWalletValidates_staticCallPrecedesInstallation() public {
        Auth1271Wallet wallet = new Auth1271Wallet(_auth, _operator);
        IOperatorAuth.Grant memory grant = _grant(15, true);
        grant.account = address(wallet);
        grant.context = _auth.authorizationContext(address(wallet), _operator);
        vm.prank(_operator);
        _auth.acceptGrant(grant, "", hex"1234");
        assertEq(
            _auth.pairEpochs(address(wallet), _operator),
            1,
            "Wallet observed unconsumed pair state before installation"
        );
        assertEq(
            _auth.accountEpochs(address(wallet)),
            0,
            "Static wallet could not mutate cancellation state"
        );
        wallet.setValid(false);
        assertTrue(
            _auth.captureAuthorization(address(wallet), _operator, 2) != bytes32(0),
            "Later wallet policy does not revoke accepted grant"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-P02.
    function test_givenAcceptedGrant_whenChainChanges() public {
        _approve(_grant(15, true));
        bytes32 beforeStamp = _auth.captureAuthorization(_account, _operator, 2);
        vm.chainId(block.chainid + 1);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 2),
            beforeStamp,
            "Accepted authority is not re-keyed by chain domain"
        );
    }
}
