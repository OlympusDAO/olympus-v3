// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {MockERC165NonConfig} from "src/test/periphery/bridge/LZCrossChainBridge/MockERC165NonConfig.sol";

/// @dev `setConfigurator` is the bootstrap-and-rotation gate that promotes a contract to the
///      bridge's `configurator` slot. The test base seeds the slot during setUp with the real
///      `LZBridgeAndDelegateConfig` policy, so this suite mostly exercises the post-bootstrap
///      rotation path; the pre-bootstrap path is exercised on a freshly deployed bridge.
contract LZCrossChainBridgeTests_SetConfigurator is LZCrossChainBridgeTestBase {
    /// @dev Deploys a candidate configurator that implements ERC-165 but rejects every
    ///      interface query, including `ILZBridgeAndDelegateConfig`
    function _deployNonConfig() internal returns (MockERC165NonConfig nonConfig) {
        nonConfig = new MockERC165NonConfig();
    }

    /// @dev Deploys a second config policy to act as the rotation destination.
    function _deploySecondaryConfig() internal returns (LZBridgeAndDelegateConfig secondary) {
        secondary = new LZBridgeAndDelegateConfig(
            kernel,
            address(gateway),
            address(lzDelegate),
            address(bridge),
            1 days
        );
    }

    /// @dev Fresh bridge that mirrors the test base configuration, but is left with the
    ///      configurator slot unset so the bootstrap branch of `setConfigurator` can be
    ///      exercised in isolation.
    function _deployBareBridge() internal returns (LZCrossChainBridge fresh) {
        fresh = new LZCrossChainBridge(
            address(ohm),
            owner,
            address(gateway),
            reEnablerAddr,
            GRACE_SECONDS
        );
    }

    // ========== BOOTSTRAP ========== //

    function test_setConfigurator_bootstrapByOwner() external {
        LZCrossChainBridge fresh = _deployBareBridge();
        LZBridgeAndDelegateConfig newConfig = _deploySecondaryConfig();

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.ConfiguratorSet(address(newConfig));

        vm.prank(owner);
        fresh.setConfigurator(address(newConfig));

        assertEq(
            fresh.configurator(),
            address(newConfig),
            "Configurator should be set after bootstrap"
        );
    }

    function testFuzz_setConfigurator_bootstrapRevertsIfNotOwner(address caller_) external {
        LZCrossChainBridge fresh = _deployBareBridge();
        vm.assume(caller_ != owner);
        LZBridgeAndDelegateConfig newConfig = _deploySecondaryConfig();

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        fresh.setConfigurator(address(newConfig));
    }

    function test_setConfigurator_bootstrapRevertsIfZeroAddress() external {
        LZCrossChainBridge fresh = _deployBareBridge();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        vm.prank(owner);
        fresh.setConfigurator(address(0));
    }

    function test_setConfigurator_bootstrapRevertsIfErc165Rejects() external {
        LZCrossChainBridge fresh = _deployBareBridge();
        MockERC165NonConfig nonConfig = _deployNonConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidConfigurator.selector,
                address(nonConfig)
            )
        );
        vm.prank(owner);
        fresh.setConfigurator(address(nonConfig));
    }

    // ========== ROTATION ========== //

    function test_setConfigurator_rotationByCurrentConfigurator() external {
        // Test base already bootstrapped the slot with `bridgeConfiguratorContract`.
        LZBridgeAndDelegateConfig nextConfig = _deploySecondaryConfig();

        vm.expectEmit(true, true, true, true);
        emit ILZCrossChainBridge.ConfiguratorSet(address(nextConfig));

        vm.prank(bridgeConfiguratorContract);
        bridge.setConfigurator(address(nextConfig));

        assertEq(
            bridge.configurator(),
            address(nextConfig),
            "Configurator should rotate to the next one"
        );
    }

    function test_setConfigurator_rotationRevertsIfOwner() external {
        LZBridgeAndDelegateConfig nextConfig = _deploySecondaryConfig();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, owner, "configurator")
        );
        vm.prank(owner);
        bridge.setConfigurator(address(nextConfig));
    }

    function testFuzz_setConfigurator_rotationRevertsIfNotCurrentConfigurator(
        address caller_
    ) external {
        vm.assume(caller_ != bridgeConfiguratorContract);
        LZBridgeAndDelegateConfig nextConfig = _deploySecondaryConfig();

        vm.expectRevert(
            abi.encodeWithSelector(Errors.Unauthorized.selector, caller_, "configurator")
        );
        vm.prank(caller_);
        bridge.setConfigurator(address(nextConfig));
    }

    function test_setConfigurator_rotationRevertsIfErc165Rejects() external {
        MockERC165NonConfig nonConfig = _deployNonConfig();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidConfigurator.selector,
                address(nonConfig)
            )
        );
        vm.prank(bridgeConfiguratorContract);
        bridge.setConfigurator(address(nonConfig));
    }

    function test_setConfigurator_rotationRevertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZCrossChainBridge.LZCrossChainBridge_InvalidAddress.selector,
                "configurator"
            )
        );
        vm.prank(bridgeConfiguratorContract);
        bridge.setConfigurator(address(0));
    }
}
