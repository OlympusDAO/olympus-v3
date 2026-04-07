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

/// @dev Bridged supply tracking via increase/decrease delta functions.
contract LZBridgeGatewayTests_SetBridgedSupply is LZBridgeGatewayTestBase {
    // ========== INCREASE ========== //

    function test_increaseBridgedSupply_syncsMintApproval() external {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyIncreased(42e9);

        vm.prank(bridgeAdmin);
        gateway.increaseBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should increase");
        assertEq(
            mintr.mintApproval(address(gateway)),
            42e9,
            "Mint approval should match bridged supply"
        );
    }

    function _test_increaseBridgedSupply(address caller_) internal {
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyIncreased(42e9);

        vm.prank(caller_);
        gateway.increaseBridgedSupply(42e9);

        assertEq(gateway.bridgedSupply(), 42e9, "Bridged supply should increase");
        assertEq(
            mintr.mintApproval(address(gateway)),
            42e9,
            "Mint approval should match bridged supply"
        );
    }

    function test_increaseBridgedSupply_adminCanCall() external {
        _test_increaseBridgedSupply(admin);
    }

    function test_increaseBridgedSupply_bridgeAdminCanCall() external {
        _test_increaseBridgedSupply(bridgeAdmin);
    }

    function test_increaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.increaseBridgedSupply(100);
    }

    function testFuzz_increaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.increaseBridgedSupply(100);
    }

    // ========== DECREASE ========== //

    function test_decreaseBridgedSupply_syncsMintApproval() external {
        // Set initial supply
        vm.prank(bridgeAdmin);
        gateway.increaseBridgedSupply(100e9);
        assertEq(mintr.mintApproval(address(gateway)), 100e9, "Initial approval");

        // Decrease supply
        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyDecreased(70e9);

        vm.prank(bridgeAdmin);
        gateway.decreaseBridgedSupply(70e9);

        assertEq(gateway.bridgedSupply(), 30e9, "Bridged supply should decrease");
        assertEq(
            mintr.mintApproval(address(gateway)),
            30e9,
            "Mint approval should decrease with supply"
        );
    }

    function _test_decreaseBridgedSupply(address caller_) internal {
        // Set initial supply
        vm.prank(bridgeAdmin);
        gateway.increaseBridgedSupply(100e9);

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyForciblyDecreased(50e9);

        vm.prank(caller_);
        gateway.decreaseBridgedSupply(50e9);

        assertEq(gateway.bridgedSupply(), 50e9, "Bridged supply should decrease");
        assertEq(
            mintr.mintApproval(address(gateway)),
            50e9,
            "Mint approval should match bridged supply"
        );
    }

    function test_decreaseBridgedSupply_adminCanCall() external {
        _test_decreaseBridgedSupply(admin);
    }

    function test_decreaseBridgedSupply_bridgeAdminCanCall() external {
        _test_decreaseBridgedSupply(bridgeAdmin);
    }

    function test_decreaseBridgedSupply_revertsIfUnderflow() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                100
            )
        );
        vm.prank(bridgeAdmin);
        gateway.decreaseBridgedSupply(100);
    }

    function test_decreaseBridgedSupply_revertsIfNotCanonical() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NotCanonical.selector)
        );
        vm.prank(bridgeAdmin);
        gateway2.decreaseBridgedSupply(100);
    }

    function testFuzz_decreaseBridgedSupply_revertsIfNotBridgeAdminOrAdmin(
        address caller_
    ) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.decreaseBridgedSupply(100);
    }
}
