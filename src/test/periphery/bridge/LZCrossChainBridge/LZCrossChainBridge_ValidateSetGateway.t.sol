// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

/// @dev Direct unit coverage for the `validateSetGateway` mirror used by the config policy at
///      queue time.
contract LZCrossChainBridgeTests_ValidateSetGateway is LZCrossChainBridgeTestBase {
    function test_validateSetGateway_acceptsNonzero() external {
        bridge.validateSetGateway(makeAddr("anyGateway"));
    }

    function test_validateSetGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        bridge.validateSetGateway(address(0));
    }
}
