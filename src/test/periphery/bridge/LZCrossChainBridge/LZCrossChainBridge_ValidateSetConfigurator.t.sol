// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Contracts
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {MockERC165NonConfig} from "src/test/periphery/bridge/LZCrossChainBridge/MockERC165NonConfig.sol";

/// @dev Direct unit coverage for the `validateSetConfigurator` mirror used by the config
///      policy at queue time. The view path mirrors the payload checks of `setConfigurator`
///      without the bootstrap-vs-rotation authorization branch.
contract LZCrossChainBridgeTests_ValidateSetConfigurator is LZCrossChainBridgeTestBase {
    function test_validateSetConfigurator_acceptsValidConfig() external {
        // The test base already wired the bridge to the config policy
        bridge.validateSetConfigurator(bridgeConfiguratorContract);
    }

    function test_validateSetConfigurator_acceptsSecondaryConfig() external {
        LZBridgeAndDelegateConfig secondary = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(bridge),
            1 days
        );

        bridge.validateSetConfigurator(address(secondary));
    }

    function test_validateSetConfigurator_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        bridge.validateSetConfigurator(address(0));
    }

    function test_validateSetConfigurator_revertsIfErc165Rejects() external {
        MockERC165NonConfig nonConfig = new MockERC165NonConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidConfigurator.selector,
                address(nonConfig)
            )
        );
        bridge.validateSetConfigurator(address(nonConfig));
    }
}
