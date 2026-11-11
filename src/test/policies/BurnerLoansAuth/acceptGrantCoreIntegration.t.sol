// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCoreTest} from "src/test/policies/BurnerLoansCore/BurnerLoansCoreTest.sol";

/// @dev Signed approval integration targets Auth with a real Core. Cryptographic edge cases are also
/// covered by the generic OperatorAuth suite; these cases bind the real lending permissions.
contract BurnerLoansAuthAcceptGrantCoreIntegrationTest is BurnerLoansCoreTest {
    // Scenarios: BLAUTH-ACCEPT-P04.
    function test_whenSignedGrantAcceptedByOperator() public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
        assertEq(_auth.pairEpochs(grant.account, grant.operator), 1, "Pair epoch consumed once");
        assertTrue(
            _isSenderAuthorized(grant.operator, grant.account),
            "Accepted lending grant usable"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-A02.
    function test_whenSignedGrantSubmittedByAccount_reverts() public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(grant.account);
        _auth.acceptGrant(grant, "", sig);
        assertFalse(
            _isSenderAuthorized(grant.operator, grant.account),
            "Account submission installs no authority"
        );
        assertEq(_auth.pairEpochs(grant.account, grant.operator), 0, "Pair epoch remains unused");
    }

    // Scenarios: BLAUTH-ACCEPT-A03.
    function test_whenUnrelatedCallerForwardsSignature_reverts(address caller_) public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        vm.assume(caller_ != grant.operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(caller_);
        _auth.acceptGrant(grant, "", sig);
        assertEq(
            _auth.pairEpochs(grant.account, grant.operator),
            0,
            "Leaked signature cannot consume epoch"
        );
    }

    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    // Scenarios: BLAUTH-ACCEPT-I04.
    function test_whenSignedFieldsTampered_reverts(uint8 field_) public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        uint8 field = uint8(bound(field_, 0, 5));
        if (field == 0) grant.deadline--;
        if (field == 1) grant.multiple = false;
        if (field == 2) grant.actions = 1;
        if (field == 3) grant.permissions[63] = bytes1(uint8(1));
        if (field == 4) grant.operator = address(0x123);
        if (field == 5) grant.account = _borrower;
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
        assertEq(
            _auth.pairEpochs(grant.account, grant.operator),
            0,
            "Tampering rolls back acceptance"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLAUTH-ACCEPT-I05.
    function test_whenWrongSigningDomain_reverts(bool wrongChain_) public {
        (IOperatorAuth.Grant memory grant, ) = _grant();
        bytes32 domain = _auth.DOMAIN_SEPARATOR();
        if (wrongChain_) vm.chainId(block.chainid + 1);
        else domain = bytes32(uint256(domain) ^ 1);
        bytes memory sig = _sign(grant, _SIGNER_KEY, domain);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
    }

    // Scenarios: BLAUTH-ACCEPT-I06.
    function test_whenWrongSigner_reverts() public {
        (IOperatorAuth.Grant memory grant, ) = _grant();
        bytes memory sig = _sign(grant, _SIGNER_KEY + 1, _auth.DOMAIN_SEPARATOR());
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidSignature.selector);
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
    }

    // Scenarios: BLAUTH-ACCEPT-I07.
    function test_whenSignatureReplayed_reverts() public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        vm.startPrank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidEpoch.selector);
        _auth.acceptGrant(grant, "", sig);
        vm.stopPrank();
        assertEq(
            _auth.pairEpochs(grant.account, grant.operator),
            1,
            "Replay cannot consume epoch twice"
        );
    }

    // Scenarios: BLAUTH-ACCEPT-I08.
    function test_whenCancelledSignature_reverts(bool all_) public {
        (IOperatorAuth.Grant memory grant, bytes memory sig) = _grant();
        vm.prank(grant.account);
        if (all_) _auth.cancelAllGrants();
        else _auth.cancelGrant(grant.operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidEpoch.selector);
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
    }

    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    // Scenarios: BLAUTH-ACCEPT-I09.
    function test_whenExpiredSignedGrant_reverts() public {
        (IOperatorAuth.Grant memory grant, ) = _grant();
        uint256 timestamp = vm.getBlockTimestamp();
        grant.deadline = uint48(timestamp);
        bytes memory sig = _sign(grant, _SIGNER_KEY, _auth.DOMAIN_SEPARATOR());
        vm.warp(timestamp + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, grant.deadline)
        );
        vm.prank(grant.operator);
        _auth.acceptGrant(grant, "", sig);
    }
    // forge-lint: disable-end(unsafe-typecast)
}
