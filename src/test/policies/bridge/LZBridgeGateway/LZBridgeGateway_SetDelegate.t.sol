// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev LZ endpoint delegate assignment.
contract LZBridgeGatewayTests_SetDelegate is LZBridgeGatewayTestBase {
    function test_setDelegate() external {
        address newDelegate = makeAddr("newDelegate");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.DelegateSet(newDelegate);

        vm.prank(bridgeAdmin);
        gateway.setDelegate(newDelegate);
    }

    function test_setDelegate_revertsIfNotBridgeAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setDelegate(makeAddr("delegate2"));
    }
}
