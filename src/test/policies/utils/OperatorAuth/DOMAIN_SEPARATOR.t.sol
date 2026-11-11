// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Contracts
import {OperatorAuthHarness} from "./OperatorAuthHarness.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthDomainSeparatorTest is OperatorAuthTest {
    // Scenarios: OADOMAIN-P01.
    function test_whenDomainRead_bindsCurrentChainAndAuth() public view {
        assertEq(
            _auth.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"),
                    block.chainid,
                    address(_auth)
                )
            ),
            "Current chain/Auth domain"
        );
    }

    // Scenarios: OADOMAIN-P02.
    function test_whenChainChanges_updatesSignatureDomain() public {
        bytes32 old = _auth.DOMAIN_SEPARATOR();
        vm.chainId(block.chainid + 1);
        assertNotEq(_auth.DOMAIN_SEPARATOR(), old, "Signature domain follows chain");
    }

    // Scenarios: OADOMAIN-P03.
    function test_givenAcceptedGrant_whenChainChanges_keepsAuthority() public {
        _approve(_grant(true));
        bytes32 stamp = _auth.captureAuthorization(_account, _operator, 1);
        vm.chainId(block.chainid + 1);
        assertEq(
            _auth.captureAuthorization(_account, _operator, 1),
            stamp,
            "Acceptance lifetime does not depend on new signing domain"
        );
    }

    // Scenarios: OADOMAIN-P04.
    function test_whenOtherAuthDeployed_domainDiffers() public {
        OperatorAuthHarness other = new OperatorAuthHarness();
        assertNotEq(
            other.DOMAIN_SEPARATOR(),
            _auth.DOMAIN_SEPARATOR(),
            "Auth instances are independent domains"
        );
    }
}
