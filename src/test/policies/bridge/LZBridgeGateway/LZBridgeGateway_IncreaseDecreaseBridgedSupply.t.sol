// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Bridged supply tracking via the delta increase/decrease functions. Both are gated to
///      `bridge_configurator`; the one-shot bootstrap path lives in
///      `LZBridgeGateway_InitializeBridgedSupply.t.sol`.
contract LZBridgeGatewayTests_SetBridgedSupply is LZBridgeGatewayTestBase {
    // ========== INCREASE ========== //

    function test_increaseBridgedSupply_syncsMintApproval() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyIncreased(42e9);

        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should increase");
        assertEq(
            mintr.mintApproval(address(gateway)),
            42e9,
            "Mint approval should match bridged supply"
        );
    }

    function test_increaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(0);
    }

    function test_increaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeConfigurator);
        gateway2.increaseBridgedSupply(100);
    }

    function testFuzz_increaseBridgedSupply_revertsIfNotBridgeConfigurator(
        address caller_
    ) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.increaseBridgedSupply(100);
    }

    // ========== DECREASE ========== //

    function test_decreaseBridgedSupply_syncsMintApproval() external {
        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(100e9);
        assertEq(mintr.mintApproval(address(gateway)), 100e9, "Initial approval");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyDecreased(70e9);

        vm.prank(bridgeConfigurator);
        gateway.decreaseBridgedSupply(70e9);

        assertEq(gateway.bridgedSupply(), 30e9, "Bridged supply should decrease");
        assertEq(
            mintr.mintApproval(address(gateway)),
            30e9,
            "Mint approval should decrease with supply"
        );
    }

    function test_decreaseBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeConfigurator);
        gateway.decreaseBridgedSupply(0);
    }

    function test_decreaseBridgedSupply_revertsIfUnderflow() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                100
            )
        );
        vm.prank(bridgeConfigurator);
        gateway.decreaseBridgedSupply(100);
    }

    function test_decreaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeConfigurator);
        gateway2.decreaseBridgedSupply(100);
    }

    function testFuzz_decreaseBridgedSupply_revertsIfNotBridgeConfigurator(
        address caller_
    ) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.decreaseBridgedSupply(100);
    }
}
