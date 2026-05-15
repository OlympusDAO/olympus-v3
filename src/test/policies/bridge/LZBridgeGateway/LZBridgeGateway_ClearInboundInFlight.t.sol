// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev Clearing inbound in-flight state.
contract LZBridgeGatewayTests_ClearInboundInFlight is LZBridgeGatewayTestBase {
    /// @dev Primes inbound in-flight on `gateway2` (non-canonical) by delivering an
    ///      outbound message from canonical to non-canonical. The non-canonical
    ///      gateway then has `inRateLimits[CANONICAL_EID].inFlight > 0`.
    function _consumeInbound() internal {
        // Tighten inbound limit on gateway2 so it can be saturated
        _setInRateLimit(gateway2, CANONICAL_EID, 1_000e9, 3600);
        _sendCanonicalToNonCanonical(recipient, 1_000e9);

        (uint256 inFlight, , , ) = gateway2.inRateLimits(CANONICAL_EID);
        assertEq(inFlight, 1_000e9, "Inbound in-flight should be primed before clear");
    }

    function test_clearInboundInFlight_resetsInFlightAndPreservesLimit() external {
        _consumeInbound();

        uint32[] memory eids = new uint32[](1);
        eids[0] = CANONICAL_EID;

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InboundInFlightCleared(eids);

        vm.prank(bridgeRateLimiter);
        gateway2.clearInboundInFlight(eids);

        (uint256 inFlight, uint256 limit, uint32 window, uint48 lastUpdated) = gateway2
            .inRateLimits(CANONICAL_EID);
        assertEq(inFlight, 0, "Inbound in-flight should be reset");
        assertEq(limit, 1_000e9, "Inbound limit should be preserved");
        assertEq(window, 3600, "Inbound window should be preserved");
        assertEq(lastUpdated, uint48(vm.getBlockTimestamp()), "lastUpdated should be refreshed");

        (, uint256 available) = gateway2.receivable(CANONICAL_EID);
        assertEq(available, 1_000e9, "Full inbound capacity should be available after clear");
    }

    function test_clearInboundInFlight_doesNotAffectOutbound() external {
        _consumeInbound();
        (uint256 outInFlightBefore, uint256 outLimitBefore, uint32 outWindowBefore, ) = gateway2
            .outRateLimits(CANONICAL_EID);

        uint32[] memory eids = new uint32[](1);
        eids[0] = CANONICAL_EID;
        vm.prank(bridgeRateLimiter);
        gateway2.clearInboundInFlight(eids);

        (uint256 outInFlightAfter, uint256 outLimitAfter, uint32 outWindowAfter, ) = gateway2
            .outRateLimits(CANONICAL_EID);
        assertEq(outInFlightAfter, outInFlightBefore, "Outbound in-flight must be unchanged");
        assertEq(outLimitAfter, outLimitBefore, "Outbound limit must be unchanged");
        assertEq(outWindowAfter, outWindowBefore, "Outbound window must be unchanged");
    }

    function _runClearInboundInFlightBy(address caller_) internal {
        _consumeInbound();
        uint32[] memory eids = new uint32[](1);
        eids[0] = CANONICAL_EID;

        vm.prank(caller_);
        gateway2.clearInboundInFlight(eids);

        (uint256 inFlight, , , ) = gateway2.inRateLimits(CANONICAL_EID);
        assertEq(inFlight, 0, "Inbound in-flight should be reset by authorized caller");
    }

    function test_clearInboundInFlight_adminCanCall() external {
        _runClearInboundInFlightBy(admin);
    }

    function test_clearInboundInFlight_bridgeAdminCanCall() external {
        _runClearInboundInFlightBy(bridgeAdmin);
    }

    function test_clearInboundInFlight_bridgeRateLimiterCanCall() external {
        _runClearInboundInFlightBy(bridgeRateLimiter);
    }

    function testFuzz_clearInboundInFlight_revertsIfNotAuthorised(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        uint32[] memory eids = new uint32[](1);
        eids[0] = CANONICAL_EID;

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway2.clearInboundInFlight(eids);
    }
}
