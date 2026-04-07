// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";

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

    function test_setRateLimits_adminCanCall() external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectEmit(true, true, true, true);
        emit RateLimiter.RateLimitsChanged(configs);

        vm.prank(admin);
        gateway.setRateLimits(configs);

        (uint192 amountInFlight, , uint192 limit, uint64 window) = gateway.rateLimits(
            NONCANONICAL_EID
        );
        assertEq(limit, 10_000e9, "Limit should be set");
        assertEq(window, 3600, "Window should be set");
        assertEq(amountInFlight, 0, "AmountInFlight should be 0");
    }

    function testFuzz_setRateLimits_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setRateLimits(configs);
    }
}
