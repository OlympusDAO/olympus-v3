// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @dev `LZCrossChainBridge.receivable` proxies to the gateway's bidirectional limiter.
contract LZCrossChainBridgeTests_Receivable is LZCrossChainBridgeTestBase {
    function test_receivable_matchesGatewayState() external view {
        (uint256 expectedInFlight, uint256 expectedAvailable) = gateway.receivable(
            NONCANONICAL_EID
        );
        (uint256 actualInFlight, uint256 actualAvailable) = bridge.receivable(NONCANONICAL_EID);
        assertEq(
            actualInFlight,
            expectedInFlight,
            "Receivable inFlight should mirror gateway state"
        );
        assertEq(
            actualAvailable,
            expectedAvailable,
            "Receivable available should mirror gateway state"
        );
    }

    function test_receivable_initialStateIsFullCapacity() external view {
        (uint256 inFlight, uint256 available) = bridge.receivable(NONCANONICAL_EID);
        assertEq(inFlight, 0, "Initial inbound in-flight should be zero");
        assertEq(available, DEFAULT_RATE_LIMIT, "Initial inbound available should equal the limit");
    }

    function test_receivable_reflectsTighterLimitAfterReconfig() external {
        uint256 newLimit = 100e9;
        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: newLimit,
            window: DEFAULT_RATE_WINDOW
        });
        vm.prank(bridgeConfiguratorRole);
        gateway.setInRateLimits(configs);

        (, uint256 available) = bridge.receivable(NONCANONICAL_EID);
        assertEq(available, newLimit, "Receivable available should track the new inbound limit");
    }
}
