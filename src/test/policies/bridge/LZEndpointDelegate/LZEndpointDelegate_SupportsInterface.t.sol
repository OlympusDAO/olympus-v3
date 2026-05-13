// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {ILZEndpointDelegate} from "src/policies/interfaces/ILZEndpointDelegate.sol";
import {ILZEndpointV2Authorized} from "src/policies/interfaces/ILZEndpointV2Authorized.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

/// @dev ERC-165 interface detection.
contract LZEndpointDelegateTests_SupportsInterface is LZEndpointDelegateTestBase {
    function test_supportsInterface_validatesIERC165Self() external view {
        ERC165Helper.validateSupportsInterface(address(lzDelegate));
    }

    function test_supportsInterface_returnsTrueForILZEndpointDelegate() external view {
        assertTrue(
            lzDelegate.supportsInterface(type(ILZEndpointDelegate).interfaceId),
            "Should support ILZEndpointDelegate"
        );
    }

    function test_supportsInterface_returnsTrueForILZEndpointV2Authorized() external view {
        assertTrue(
            lzDelegate.supportsInterface(type(ILZEndpointV2Authorized).interfaceId),
            "Should support ILZEndpointV2Authorized"
        );
    }

    function test_supportsInterface_returnsTrueForIVersioned() external view {
        assertTrue(
            lzDelegate.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(
            lzDelegate.supportsInterface(type(IERC165).interfaceId),
            "Should support IERC165"
        );
    }

    function test_supportsInterface_returnsFalseForUnsupportedInterface() external view {
        assertFalse(
            lzDelegate.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support a random interface"
        );
    }
}
