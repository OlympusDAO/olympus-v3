// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {ChainlinkPriceFeedsTest} from "../ChainlinkPriceFeeds.t.sol";

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ISubmodule} from "src/interfaces/ISubmodule.sol";

contract ChainlinkPriceFeedsSupportsInterfaceTest is ChainlinkPriceFeedsTest {
    // Single test function checking all three interfaces
    function test_supportsInterface_returnsTrueForAllInterfaces() public view {
        // Check IERC165
        bytes4 ierc165 = type(IERC165).interfaceId;
        assertTrue(chainlinkSubmodule.supportsInterface(ierc165), "Should support IERC165");

        // Check ISubmodule (which inherits IVersioned)
        bytes4 isubmodule = type(ISubmodule).interfaceId;
        assertTrue(chainlinkSubmodule.supportsInterface(isubmodule), "Should support ISubmodule");

        // Check IVersioned (via ISubmodule inheritance)
        bytes4 iversioned = type(IVersioned).interfaceId;
        assertTrue(chainlinkSubmodule.supportsInterface(iversioned), "Should support IVersioned");
    }

    function test_supportsInterface_unsupported_returnsFalse() public view {
        bytes4 interfaceId = 0x12345678;
        assertFalse(
            chainlinkSubmodule.supportsInterface(interfaceId),
            "Should not support unsupported"
        );
    }
}
