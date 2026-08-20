// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Contracts
import {Permissions} from "src/Kernel.sol";

/// @dev configureDependencies, requestPermissions, and VERSION.
contract LZEndpointDelegateTests_PolicySetup is LZEndpointDelegateTestBase {
    function test_configureDependencies_setsROLES() external view {
        assertEq(
            address(lzDelegate.ROLES()),
            address(roles),
            "ROLES should be set from the kernel"
        );
    }

    function test_requestPermissions_isEmpty() external view {
        Permissions[] memory perms = lzDelegate.requestPermissions();
        assertEq(perms.length, 0, "LZEndpointDelegate should not request any module permissions");
    }

    function test_VERSION() external view {
        (uint8 major, uint8 minor) = lzDelegate.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}
