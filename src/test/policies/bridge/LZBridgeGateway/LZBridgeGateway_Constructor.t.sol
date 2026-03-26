// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";

/// @dev Deployment and immutable state validation.
contract LZBridgeGatewayTests_Constructor is LZBridgeGatewayTestBase {
    function test_constructor_canonical() external {
        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel,
            address(endpointSetup.endpointList[0]),
            true
        );

        // Immutables
        assertEq(
            fresh.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[0]),
            "LZ_ENDPOINT should be set"
        );
        assertTrue(fresh.IS_CANONICAL(), "IS_CANONICAL should be true");

        // State
        assertEq(address(fresh.kernel()), address(kernel), "Kernel should be set");
        assertFalse(fresh.isEnabled(), "Should start disabled");
        assertEq(fresh.bridgedSupply(), 0, "Bridged supply should be zero");
        assertEq(fresh.bridgedSupplyCap(), 0, "Bridged supply cap should be zero");
    }

    function test_constructor_nonCanonical() external {
        LZBridgeGateway fresh = new LZBridgeGateway(
            kernel2,
            address(endpointSetup.endpointList[1]),
            false
        );

        assertEq(address(fresh.kernel()), address(kernel2), "Kernel should be set");
        assertEq(
            fresh.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[1]),
            "LZ_ENDPOINT should be the non-canonical endpoint"
        );
        assertFalse(fresh.IS_CANONICAL(), "IS_CANONICAL should be false");
        assertFalse(fresh.isEnabled(), "Should start disabled");
    }

    function test_constructor_revertsIfKernelZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "kernel"
            )
        );
        new LZBridgeGateway(Kernel(address(0)), address(1), true);
    }

    function test_constructor_revertsIfEndpointZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector,
                "lzEndpoint"
            )
        );
        new LZBridgeGateway(kernel, address(0), true);
    }
}
