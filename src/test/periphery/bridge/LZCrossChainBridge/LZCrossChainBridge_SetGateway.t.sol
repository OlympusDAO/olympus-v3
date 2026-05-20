// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

/// @dev `setGateway` is gated to the configurator. The bootstrap-pre-set path is exercised by
///      the `LZCrossChainBridge_SetConfigurator.t.sol` test suite.
contract LZCrossChainBridgeTests_SetGateway is LZCrossChainBridgeTestBase {
    function test_setGateway_configuratorCanCall() external {
        address newGateway = makeAddr("newGateway");

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.GatewaySet(newGateway);

        vm.prank(bridgeConfiguratorContract);
        bridge.setGateway(newGateway);

        assertEq(bridge.gateway(), newGateway, "Gateway should be updated");
    }

    function test_setGateway_revertsIfOwner() external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, owner, "configurator")
        );
        vm.prank(owner);
        bridge.setGateway(makeAddr("newGateway"));
    }

    function testFuzz_setGateway_revertsIfNotConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfiguratorContract);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, caller_, "configurator")
        );
        vm.prank(caller_);
        bridge.setGateway(makeAddr("newGateway"));
    }

    function test_setGateway_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "gateway"
            )
        );
        vm.prank(bridgeConfiguratorContract);
        bridge.setGateway(address(0));
    }
}
