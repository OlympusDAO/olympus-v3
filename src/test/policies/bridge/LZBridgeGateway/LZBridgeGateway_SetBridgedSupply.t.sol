// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Bridged supply tracking and cap enforcement.
contract LZBridgeGatewayTests_SetBridgedSupply is LZBridgeGatewayTestBase {
    function test_setBridgedSupply() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplySet(42e9);

        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should be set");
    }

    function test_setBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.setBridgedSupply(100);
    }

    function test_setBridgedSupply_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setBridgedSupply(100);
    }

    function test_setBridgedSupplyCap() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyCapSet(1_000_000);

        vm.prank(admin);
        gateway.setBridgedSupplyCap(1_000_000);

        assertEq(gateway.bridgedSupplyCap(), 1_000_000, "Cap should be set");
    }

    function test_setBridgedSupplyCap_lessThanCurrentSupplyPreventsNewBridgings() external {
        // 1. Preparation: build up bridged supply
        uint256 bridgedAmount = 10_000e9;
        _sendCanonicalToNonCanonical(recipient, bridgedAmount);
        assertEq(gateway.bridgedSupply(), bridgedAmount, "Bridged supply should match");

        // Set cap below current bridged supply
        uint256 lowCap = 5_000e9;
        vm.prank(admin);
        gateway.setBridgedSupplyCap(lowCap);

        // 2. Test: new bridgings should revert due to cap exceeded
        uint256 newAmount = 1e9;
        ohm.mint(facilitator, newAmount);

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), newAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyCapExceeded.selector,
                bridgedAmount + newAmount,
                lowCap
            )
        );
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            newAmount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_setBridgedSupplyCap_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(admin);
        gateway2.setBridgedSupplyCap(100);
    }

    function test_setBridgedSupplyCap_revertsIfNotAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user);
        gateway.setBridgedSupplyCap(100_000e9);
    }
}
