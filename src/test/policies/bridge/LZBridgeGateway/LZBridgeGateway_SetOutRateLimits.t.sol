// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev Setting outbound rate limits.
contract LZBridgeGatewayTests_SetOutRateLimits is LZBridgeGatewayTestBase {
    function _buildConfigs(
        uint32 eid_,
        uint256 limit_,
        uint32 window_
    ) internal pure returns (IOffsettingRateLimiter.RateLimitConfig[] memory configs) {
        configs = new IOffsettingRateLimiter.RateLimitConfig[](1);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: eid_,
            limit: limit_,
            window: window_
        });
    }

    function test_setOutRateLimits_emitsEventAndStoresLimit() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.OutRateLimitsSet(configs);

        vm.prank(bridgeRateLimiter);
        gateway.setOutRateLimits(configs);

        (uint256 inFlight, uint256 limit, uint32 window, ) = gateway.outRateLimits(
            NONCANONICAL_EID
        );
        assertEq(limit, 10_000e9, "Outbound limit should be set");
        assertEq(window, 3600, "Outbound window should be set");
        assertEq(inFlight, 0, "Outbound in-flight should remain zero");
    }

    function test_setOutRateLimits_doesNotTouchInRateLimits() external {
        // Default in-rate limit is set in test base; capture and verify untouched
        (, uint256 inLimitBefore, uint32 inWindowBefore, ) = gateway.inRateLimits(NONCANONICAL_EID);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );
        vm.prank(bridgeRateLimiter);
        gateway.setOutRateLimits(configs);

        (, uint256 inLimitAfter, uint32 inWindowAfter, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(inLimitAfter, inLimitBefore, "Inbound limit must be unchanged");
        assertEq(inWindowAfter, inWindowBefore, "Inbound window must be unchanged");
    }

    function test_setOutRateLimits_repeatedEntriesLastWins() external {
        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](2);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 1_000e9,
            window: 60
        });
        configs[1] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 9_000e9,
            window: 7200
        });

        vm.prank(bridgeRateLimiter);
        gateway.setOutRateLimits(configs);

        (, uint256 limit, uint32 window, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(limit, 9_000e9, "Last entry should dominate the final limit");
        assertEq(window, 7200, "Last entry should dominate the final window");
    }

    function _runSetOutRateLimitsBy(address caller_) internal {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );
        vm.prank(caller_);
        gateway.setOutRateLimits(configs);

        (, uint256 limit, , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(limit, 10_000e9, "Authorized caller should set the limit");
    }

    function test_setOutRateLimits_adminCanCall() external {
        _runSetOutRateLimitsBy(admin);
    }

    function test_setOutRateLimits_bridgeAdminCanCall() external {
        _runSetOutRateLimitsBy(bridgeAdmin);
    }

    function test_setOutRateLimits_bridgeRateLimiterCanCall() external {
        _runSetOutRateLimitsBy(bridgeRateLimiter);
    }

    /// @notice Outbound rate limits store any (limit, window) pair as configured.
    function testFuzz_setOutRateLimits(uint256 limit_, uint32 window_) external {
        // Bound window to non-zero so the standard decay path is exercised
        window_ = uint32(bound(uint256(window_), 1, type(uint32).max));
        _setOutRateLimit(gateway, NONCANONICAL_EID, limit_, window_);

        (, uint256 storedLimit, uint32 storedWindow, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(storedLimit, limit_, "Outbound limit should be stored as configured");
        assertEq(storedWindow, window_, "Outbound window should be stored as configured");
    }

    function testFuzz_setOutRateLimits_revertsIfNotAuthorised(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setOutRateLimits(configs);
    }
}
