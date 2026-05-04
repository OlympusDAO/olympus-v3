// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev End-to-end rate-limiting behaviour through `burnAndSend` and `lzReceive`.
contract LZBridgeGatewayTests_RateLimitingBehaviour is LZBridgeGatewayTestBase {
    // ========== OUTFLOW ========== //

    /// @notice After half the configured window elapses, half the outbound capacity is
    ///         restored linearly.
    function test_burnAndSend_outLinearDecayRestoresCapacityMidWindow() external {
        uint256 limit = 10_000e9;
        uint32 window = 3600;
        _setOutRateLimit(gateway, NONCANONICAL_EID, limit, window);

        // Exhaust the full outbound limit.
        _sendCanonicalToNonCanonical(recipient, limit);

        (, uint256 available) = gateway.sendable(NONCANONICAL_EID);
        assertEq(available, 0, "No outbound capacity right after exhaustion");

        // After half the window, half the limit should be restored.
        skip(uint256(window) / 2);

        (, available) = gateway.sendable(NONCANONICAL_EID);
        assertEq(available, limit / 2, "Half of the outbound capacity should be restored");
    }

    // ========== INFLOW ========== //

    /// @notice Inbound capacity is restored linearly across the configured window.
    /// @dev Decay rate equals `limit / window` per second. Filling half of a 10_000e9
    ///      limit takes 1800 seconds to fully decay, so we skip a quarter of the window
    ///      (900s) to verify the partial midpoint recovery.
    function test_lzReceive_inLimitDecaysOverWindow() external {
        uint256 inLimit = 10_000e9;
        uint32 window = 3600;
        _setInRateLimit(gateway2, CANONICAL_EID, inLimit, window);

        // Deliver an inbound transfer that fills half the inbound capacity.
        _sendCanonicalToNonCanonical(recipient, inLimit / 2);

        (, uint256 receivable) = gateway2.receivable(CANONICAL_EID);
        assertEq(receivable, inLimit / 2, "Half inbound capacity should remain");

        // Skip a quarter of the window: linear decay = limit * elapsed / window
        // = 10_000e9 * 900 / 3600 = 2_500e9. inFlight = 5_000e9 - 2_500e9 = 2_500e9.
        // Available = limit - inFlight = 7_500e9.
        skip(uint256(window) / 4);

        (, receivable) = gateway2.receivable(CANONICAL_EID);
        assertEq(receivable, (inLimit * 3) / 4, "Three quarters inbound capacity after decay");
    }
}
