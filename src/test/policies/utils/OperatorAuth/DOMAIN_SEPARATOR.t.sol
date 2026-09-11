// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {OperatorAuthTest} from "../OperatorAuth.t.sol";

contract OperatorAuthDomainSeparatorTest is OperatorAuthTest {
    function test_DOMAIN_SEPARATOR_matchesDeploymentDomain() public view {
        assertEq(
            auth.DOMAIN_SEPARATOR(),
            _domainSeparator(block.chainid, address(auth)),
            "domain separator"
        );
    }

    function test_DOMAIN_SEPARATOR_givenChainIdChanges_usesCurrentChain() public {
        uint256 newChainId = block.chainid + 1;
        vm.chainId(newChainId);

        assertEq(
            auth.DOMAIN_SEPARATOR(),
            _domainSeparator(newChainId, address(auth)),
            "current-chain domain separator"
        );
    }
}
