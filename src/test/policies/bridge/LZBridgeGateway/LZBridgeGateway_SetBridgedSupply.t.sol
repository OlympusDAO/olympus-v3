// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Bridged supply tracking and cap enforcement.
contract LZBridgeGatewayTests_SetBridgedSupply is LZBridgeGatewayTestBase {
    function test_setBridgedSupply_increaseSyncsMintApproval() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplySet(42e9);

        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should be set");
        assertEq(
            mintr.mintApproval(address(gateway)),
            42e9,
            "Mint approval should match bridged supply"
        );
    }

    function test_setBridgedSupply_adminCanCall() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplySet(42e9);

        vm.prank(admin);
        gateway.setBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should be set");
        assertEq(
            mintr.mintApproval(address(gateway)),
            42e9,
            "Mint approval should match bridged supply"
        );
    }

    function test_setBridgedSupply_decreaseSyncsMintApproval() external {
        // Set initial supply
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(100e9);
        assertEq(mintr.mintApproval(address(gateway)), 100e9, "Initial approval");

        // Decrease supply
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(30e9);

        assertEq(gateway.bridgedSupply(), 30e9, "Bridged supply should decrease");
        assertEq(
            mintr.mintApproval(address(gateway)),
            30e9,
            "Mint approval should decrease with supply"
        );
    }

    function test_setBridgedSupply_sameValueNoChange() external {
        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(50e9);

        uint256 approvalBefore = mintr.mintApproval(address(gateway));

        vm.prank(bridgeAdmin);
        gateway.setBridgedSupply(50e9);

        assertEq(
            mintr.mintApproval(address(gateway)),
            approvalBefore,
            "Mint approval should not change when supply unchanged"
        );
    }

    function test_setBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.setBridgedSupply(100);
    }

    function testFuzz_setBridgedSupply_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setBridgedSupply(100);
    }
}
