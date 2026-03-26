// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_Constructor is LZCrossChainBridgeTestBase {
    function test_constructor() external {
        LZCrossChainBridge fresh = new LZCrossChainBridge(
            address(ohm),
            address(this),
            address(gateway)
        );

        assertEq(fresh.OHM(), address(ohm), "OHM should be set");
        assertEq(fresh.owner(), address(this), "Owner should be the deployer");
        assertEq(fresh.gateway(), address(gateway), "Gateway should be set from constructor");
        assertFalse(fresh.isEnabled(), "Bridge should start disabled");
    }

    function test_constructor_revertsIfOhmZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "ohm"
            )
        );
        new LZCrossChainBridge(address(0), address(this), address(gateway));
    }

    function test_constructor_revertsIfOwnerZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "owner"
            )
        );
        new LZCrossChainBridge(address(ohm), address(0), address(gateway));
    }

    function test_constructor_revertsIfGatewayZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        new LZCrossChainBridge(address(ohm), address(this), address(0));
    }
}
