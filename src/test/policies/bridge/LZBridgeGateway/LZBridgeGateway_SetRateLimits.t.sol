// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Libraries
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Setting rate limits.
contract LZBridgeGatewayTests_SetRateLimits is LZBridgeGatewayTestBase {
    function test_setRateLimits() external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectEmit(true, true, true, true);
        emit RateLimiter.RateLimitsChanged(configs);

        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);

        (uint192 amountInFlight, , uint192 limit, uint64 window) = gateway.rateLimits(
            NONCANONICAL_EID
        );
        assertEq(limit, 10_000e9, "Limit should be set");
        assertEq(window, 3600, "Window should be set");
        assertEq(amountInFlight, 0, "AmountInFlight should be 0");
    }

    function test_setRateLimits_revertsIfNotBridgeAdmin() external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.setRateLimits(configs);
    }
}
