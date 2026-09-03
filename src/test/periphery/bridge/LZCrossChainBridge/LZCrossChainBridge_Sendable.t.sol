// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev `LZCrossChainBridge.sendable` proxies to the gateway's bidirectional limiter.
contract LZCrossChainBridgeTests_Sendable is LZCrossChainBridgeTestBase {
    function test_sendable_matchesGatewayState() external view {
        (uint256 expectedInFlight, uint256 expectedAvailable) = gateway.sendable(NONCANONICAL_EID);
        (uint256 actualInFlight, uint256 actualAvailable) = bridge.sendable(NONCANONICAL_EID);
        assertEq(actualInFlight, expectedInFlight, "Sendable inFlight should mirror gateway state");
        assertEq(
            actualAvailable,
            expectedAvailable,
            "Sendable available should mirror gateway state"
        );
    }

    function test_sendable_reflectsOutflowAfterSend() external {
        uint256 amount = 5_000e9;

        vm.prank(user);
        bridge.sendOhm{value: 1 ether}(NONCANONICAL_EID, recipient, amount);

        (uint256 inFlight, uint256 available) = bridge.sendable(NONCANONICAL_EID);
        assertEq(inFlight, amount, "Sendable inFlight should grow by the sent amount");
        assertEq(
            available,
            DEFAULT_RATE_LIMIT - amount,
            "Sendable available should decrease by the sent amount"
        );
    }

    function test_sendable_reflectsTighterLimitAfterReconfig() external {
        uint256 newLimit = 100e9;
        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: newLimit,
            window: DEFAULT_RATE_WINDOW
        });
        vm.prank(bridgeConfiguratorRole);
        gateway.setOutRateLimits(configs);

        (, uint256 available) = bridge.sendable(NONCANONICAL_EID);
        assertEq(available, newLimit, "Sendable available should track the new outbound limit");
    }
}
