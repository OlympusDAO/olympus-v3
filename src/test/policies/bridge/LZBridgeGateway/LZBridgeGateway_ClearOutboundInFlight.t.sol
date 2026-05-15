// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev Clearing outbound in-flight state.
contract LZBridgeGatewayTests_ClearOutboundInFlight is LZBridgeGatewayTestBase {
    function _consumeOutbound() internal {
        // Bring the outbound rate limit down to a tighter ceiling so it can be saturated
        _setOutRateLimit(gateway, NONCANONICAL_EID, 1_000e9, 3600);
        _sendCanonicalToNonCanonical(recipient, 1_000e9);

        (uint256 inFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(inFlight, 1_000e9, "Outbound in-flight should be primed before clear");
    }

    function test_clearOutboundInFlight_resetsInFlightAndPreservesLimit() external {
        _consumeOutbound();

        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutboundInFlightCleared(eids);

        vm.prank(bridgeRateLimiter);
        gateway.clearOutboundInFlight(eids);

        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway
            .outRateLimits(NONCANONICAL_EID);
        assertEq(inFlight, 0, "Outbound in-flight should be reset");
        assertEq(limit, 1_000e9, "Outbound limit should be preserved");
        assertEq(window, 3600, "Outbound window should be preserved");
        assertEq(lastUpdated, uint48(vm.getBlockTimestamp()), "lastUpdated should be refreshed");

        (, uint256 available) = gateway.sendable(NONCANONICAL_EID);
        assertEq(available, 1_000e9, "Full outbound capacity should be available after clear");
    }

    function test_clearOutboundInFlight_doesNotAffectInbound() external {
        _consumeOutbound();
        (uint256 inInFlightBefore, uint256 inLimitBefore, uint32 inWindowBefore, ) = gateway
            .inRateLimits(NONCANONICAL_EID);

        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;
        vm.prank(bridgeRateLimiter);
        gateway.clearOutboundInFlight(eids);

        (uint256 inInFlightAfter, uint256 inLimitAfter, uint32 inWindowAfter, ) = gateway
            .inRateLimits(NONCANONICAL_EID);
        assertEq(inInFlightAfter, inInFlightBefore, "Inbound in-flight must be unchanged");
        assertEq(inLimitAfter, inLimitBefore, "Inbound limit must be unchanged");
        assertEq(inWindowAfter, inWindowBefore, "Inbound window must be unchanged");
    }

    function _runClearOutboundInFlightBy(address caller_) internal {
        _consumeOutbound();
        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.prank(caller_);
        gateway.clearOutboundInFlight(eids);

        (uint256 inFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(inFlight, 0, "Outbound in-flight should be reset by authorized caller");
    }

    function test_clearOutboundInFlight_adminCanCall() external {
        _runClearOutboundInFlightBy(admin);
    }

    function test_clearOutboundInFlight_bridgeAdminCanCall() external {
        _runClearOutboundInFlightBy(bridgeAdmin);
    }

    function test_clearOutboundInFlight_bridgeRateLimiterCanCall() external {
        _runClearOutboundInFlightBy(bridgeRateLimiter);
    }

    function testFuzz_clearOutboundInFlight_revertsIfNotAuthorised(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.clearOutboundInFlight(eids);
    }
}
