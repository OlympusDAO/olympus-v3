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
}
