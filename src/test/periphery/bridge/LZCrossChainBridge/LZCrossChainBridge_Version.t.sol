// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

contract LZCrossChainBridgeTests_Version is LZCrossChainBridgeTestBase {
    function test_VERSION() external view {
        (uint8 major, uint8 minor) = bridge.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}
