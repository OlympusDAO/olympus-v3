// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev One-shot bootstrap of the canonical bridged supply. Callable by `bridge_admin` /
///      `admin`, only on the canonical chain, and only while `bridgedSupplyInitialized` is
///      false and `bridgedSupply` is zero.
contract LZBridgeGatewayTests_InitializeBridgedSupply is LZBridgeGatewayTestBase {
    uint256 internal constant _INITIAL_AMOUNT = 1_000_000e9;

    function test_initializeBridgedSupply_setsBridgedSupplyAndApproval() external {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should start zero");
        assertFalse(gateway.bridgedSupplyInitialized(), "Bootstrap flag should start cleared");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyInitialized(_INITIAL_AMOUNT);

        vm.prank(bridgeAdmin);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);

        assertEq(
            gateway.bridgedSupply(),
            _INITIAL_AMOUNT,
            "Bridged supply should be set to the initial amount"
        );
        assertEq(
            mintr.mintApproval(address(gateway)),
            _INITIAL_AMOUNT,
            "Mint approval should match the bridged supply"
        );
        assertTrue(gateway.bridgedSupplyInitialized(), "Bootstrap flag should be set after init");
    }

    function test_initializeBridgedSupply_adminCanCall() external {
        vm.prank(admin);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);

        assertEq(gateway.bridgedSupply(), _INITIAL_AMOUNT, "Bridged supply set by admin");
    }

    function test_initializeBridgedSupply_revertsIfAlreadyInitialized() external {
        vm.prank(bridgeAdmin);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);

        // Drain the supply, then try to re-initialize.
        vm.prank(bridgeConfigurator);
        gateway.decreaseBridgedSupply(_INITIAL_AMOUNT);
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply drained to zero");
        assertTrue(gateway.bridgedSupplyInitialized(), "Bootstrap flag is sticky");

        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_BridgedSupplyAlreadyInitialized.selector);
        vm.prank(bridgeAdmin);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);
    }

    function test_initializeBridgedSupply_revertsIfBridgedSupplyAlreadyNonZero() external {
        // Inflate the supply via the `bridge_configurator` path so the flag is still cleared
        // but `bridgedSupply` is non-zero.
        uint256 stale = 5e9;
        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(stale);
        assertEq(gateway.bridgedSupply(), stale, "Stale supply primed");
        assertFalse(gateway.bridgedSupplyInitialized(), "Bootstrap flag still cleared");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyAlreadyNonZero.selector,
                stale
            )
        );
        vm.prank(bridgeAdmin);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);
    }

    function test_initializeBridgedSupply_revertsIfZeroAmount() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_ZeroAmount.selector);
        vm.prank(bridgeAdmin);
        gateway.initializeBridgedSupply(0);
    }

    function test_initializeBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector);
        vm.prank(bridgeAdmin);
        gateway2.initializeBridgedSupply(_INITIAL_AMOUNT);
    }

    function testFuzz_initializeBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != bridgeAdmin && caller_ != admin);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        gateway.initializeBridgedSupply(_INITIAL_AMOUNT);
    }
}
