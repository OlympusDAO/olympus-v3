// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract PolicyEnablerSupportsInterfaceTest is PolicyEnablerTest {
    function test_supportsInterface() public view {
        ERC165Helper.validateSupportsInterface(address(policyEnabler));
        assertEq(
            policyEnabler.supportsInterface(type(IERC165).interfaceId),
            true,
            "IERC165 mismatch"
        );
        assertEq(
            policyEnabler.supportsInterface(type(IEnabler).interfaceId),
            true,
            "IEnabler mismatch"
        );

        // Test non-implemented interfaces (should be false)
        assertEq(
            policyEnabler.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
    }
}
