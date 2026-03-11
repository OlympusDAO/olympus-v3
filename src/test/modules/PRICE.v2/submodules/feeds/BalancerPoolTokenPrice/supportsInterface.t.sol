// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {BalancerPoolTokenPriceStableTest} from "../BalancerPoolTokenPriceStable.t.sol";

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ISubmodule} from "src/interfaces/ISubmodule.sol";

contract BalancerPoolTokenPriceStableSupportsInterfaceTest is BalancerPoolTokenPriceStableTest {
    // Single test function checking all three interfaces
    function test_supportsInterface_returnsTrueForAllInterfaces() public view {
        // Check IERC165
        bytes4 ierc165 = type(IERC165).interfaceId;
        assertTrue(balancerSubmodule.supportsInterface(ierc165), "Should support IERC165");

        // Check ISubmodule (which inherits IVersioned)
        bytes4 isubmodule = type(ISubmodule).interfaceId;
        assertTrue(balancerSubmodule.supportsInterface(isubmodule), "Should support ISubmodule");

        // Check IVersioned (via ISubmodule inheritance)
        bytes4 iversioned = type(IVersioned).interfaceId;
        assertTrue(balancerSubmodule.supportsInterface(iversioned), "Should support IVersioned");
    }

    function test_supportsInterface_unsupported_returnsFalse() public view {
        bytes4 interfaceId = 0x12345678;
        assertFalse(
            balancerSubmodule.supportsInterface(interfaceId),
            "Should not support unsupported"
        );
    }
}
