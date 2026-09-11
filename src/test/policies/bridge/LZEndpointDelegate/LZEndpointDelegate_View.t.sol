// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

/// @dev Immutable and lifecycle view accessors.
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

    function test_isEnabled_returnsTrueAfterSetUp() external view {
        assertTrue(lzDelegate.isEnabled(), "isEnabled should be true after setUp enables it");
    }

    function test_lastTransitionAt_returnsBlockTimestampOnEnable() external view {
        assertEq(
            uint256(lzDelegate.lastTransitionAt()),
            uint256(uint48(vm.getBlockTimestamp())),
            "lastTransitionAt should track the enable timestamp"
        );
    }
}
