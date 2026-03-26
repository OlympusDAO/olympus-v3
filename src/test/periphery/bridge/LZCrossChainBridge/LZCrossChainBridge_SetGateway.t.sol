// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_SetGateway is LZCrossChainBridgeTestBase {
    function test_setGateway() external {
        address newGateway = makeAddr("newGateway");

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.GatewaySet(newGateway);

        bridge.setGateway(newGateway);

        assertEq(bridge.gateway(), newGateway, "Gateway should be updated");
    }

    function test_setGateway_revertsIfNotOwner() external {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(user);
        bridge.setGateway(makeAddr("newGateway"));
    }

    function test_setGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        bridge.setGateway(address(0));
    }
}
