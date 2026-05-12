// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

/// @dev Immutable view accessors.
contract LZEndpointDelegateTests_View is LZEndpointDelegateTestBase {
    function test_GATEWAY() external view {
        assertEq(lzDelegate.GATEWAY(), gateway, "GATEWAY should match the constructor argument");
    }

    function test_LZ_ENDPOINT() external view {
        assertEq(
            lzDelegate.LZ_ENDPOINT(),
            lzEndpoint,
            "LZ_ENDPOINT should match the constructor argument"
        );
    }
}
