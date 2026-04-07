// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev LZ endpoint delegate assignment.
contract LZBridgeGatewayTests_SetDelegate is LZBridgeGatewayTestBase {
    function test_setDelegate() external {
        address newDelegate = makeAddr("newDelegate");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.DelegateSet(newDelegate);

        vm.prank(bridgeAdmin);
        gateway.setDelegate(newDelegate);
    }

    function test_setDelegate_adminCanCall() external {
        address newDelegate = makeAddr("newDelegate");

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.DelegateSet(newDelegate);

        vm.prank(admin);
        gateway.setDelegate(newDelegate);
    }

    function testFuzz_setDelegate_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setDelegate(makeAddr("delegate2"));
    }
}
