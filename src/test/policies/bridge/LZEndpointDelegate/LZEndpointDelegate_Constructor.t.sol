// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";
import {MockLZBridgeGateway} from "src/test/policies/bridge/LZEndpointDelegate/MockLZBridgeGateway.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";

/// @dev Deployment and immutable state validation.
contract LZEndpointDelegateTests_Constructor is LZEndpointDelegateTestBase {
    function test_constructor_setsImmutables() external {
        LZEndpointDelegate fresh = new LZEndpointDelegate(kernel, gateway);
        assertEq(address(fresh.kernel()), address(kernel), "Kernel should be set");
        assertEq(fresh.GATEWAY(), gateway, "GATEWAY should be set");
        assertEq(
            fresh.LZ_ENDPOINT(),
            lzEndpoint,
            "LZ_ENDPOINT should be read from the gateway at construction"
        );
    }

    function test_constructor_startsDisabled() external {
        LZEndpointDelegate fresh = new LZEndpointDelegate(kernel, gateway);
        assertFalse(fresh.isEnabled(), "isEnabled should be false on a fresh deployment");
        assertEq(
            uint256(fresh.lastTransitionAt()),
            0,
            "lastTransitionAt should be zero on a fresh deployment"
        );
    }

    function test_constructor_readsEndpointFromGateway() external {
        address otherEndpoint = makeAddr("otherEndpoint");
        MockLZBridgeGateway otherGateway = new MockLZBridgeGateway(otherEndpoint);

        LZEndpointDelegate fresh = new LZEndpointDelegate(kernel, address(otherGateway));
        assertEq(
            fresh.GATEWAY(),
            address(otherGateway),
            "GATEWAY should match the constructor argument"
        );
        assertEq(fresh.LZ_ENDPOINT(), otherEndpoint, "LZ_ENDPOINT should mirror gateway");
    }

    function test_constructor_revertsIfKernelZero() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.BadInput.selector, "kernel"));
        new LZEndpointDelegate(Kernel(address(0)), gateway);
    }

    function test_constructor_revertsIfGatewayZero() external {
        vm.expectRevert(abi.encodeWithSelector(Errors.BadInput.selector, "gateway"));
        new LZEndpointDelegate(kernel, address(0));
    }

    function test_constructor_revertsIfGatewayReportsZeroEndpoint() external {
        // Defence in depth: if a misconfigured gateway returns the zero address from
        // `LZ_ENDPOINT()`.
        MockLZBridgeGateway brokenGateway = new MockLZBridgeGateway(address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.BadInput.selector, "lzEndpoint"));
        new LZEndpointDelegate(kernel, address(brokenGateway));
    }
}
