// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

// Test
import {PriceV2Test} from "./PRICE.v2.t.sol";

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

contract PriceV2SupportsInterfaceTest is PriceV2Test {
    // Single test function checking all interfaces
    function test_supportsInterface_returnsTrueForAllInterfaces() public view {
        // Check IERC165
        bytes4 ierc165 = type(IERC165).interfaceId;
        assertTrue(price.supportsInterface(ierc165), "Should support IERC165");

        // Check IPRICEv2
        bytes4 ipricev2 = type(IPRICEv2).interfaceId;
        assertTrue(price.supportsInterface(ipricev2), "Should support IPRICEv2");

        // Check IVersioned
        bytes4 iversioned = type(IVersioned).interfaceId;
        assertTrue(price.supportsInterface(iversioned), "Should support IVersioned");
    }

    function test_supportsInterface_unsupported_returnsFalse() public view {
        bytes4 interfaceId = 0x12345678;
        assertFalse(price.supportsInterface(interfaceId), "Should not support unsupported");
    }
}
