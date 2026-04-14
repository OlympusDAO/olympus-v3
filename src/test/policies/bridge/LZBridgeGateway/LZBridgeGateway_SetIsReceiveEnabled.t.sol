// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev setIsReceiveEnabled access control and state transitions.
contract LZBridgeGatewayTests_SetIsReceiveEnabled is LZBridgeGatewayTestBase {
    function test_setIsReceiveEnabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.expectEmit();
        emit ILZBridgeGateway.IsReceiveEnabledSet(true);

        vm.prank(admin);
        gateway.setIsReceiveEnabled(true);

        assertTrue(gateway.isReceiveEnabled(), "isReceiveEnabled should be true");
    }

    function test_setIsReceiveEnabled_disables() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        gateway.setIsReceiveEnabled(true);
        vm.stopPrank();

        vm.expectEmit();
        emit ILZBridgeGateway.IsReceiveEnabledSet(false);

        vm.prank(admin);
        gateway.setIsReceiveEnabled(false);

        assertFalse(gateway.isReceiveEnabled(), "isReceiveEnabled should be false");
    }

    function test_setIsReceiveEnabled_revertsIfAlreadyInDesiredState() external {
        // Default is false, setting false should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_ReceiveAlreadyInDesiredState.selector
            )
        );
        vm.prank(admin);
        gateway.setIsReceiveEnabled(false);
    }

    function testFuzz_setIsReceiveEnabled_revertsIfNotAdminOrEmergency(address caller_) external {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setIsReceiveEnabled(true);
    }
}
