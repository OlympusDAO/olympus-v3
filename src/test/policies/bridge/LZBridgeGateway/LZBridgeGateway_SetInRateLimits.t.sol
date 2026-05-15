// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev Setting inbound rate limits.
contract LZBridgeGatewayTests_SetInRateLimits is LZBridgeGatewayTestBase {
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

    function test_setInRateLimits_emitsEventAndStoresLimit() external {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            5_000e9,
            1800
        );

        vm.expectEmit(true, true, true, true);
        emit IOffsettingRateLimiter.InRateLimitsSet(configs);

        vm.prank(bridgeRateLimiter);
        gateway.setInRateLimits(configs);

        (uint256 inFlight, uint256 limit, uint32 window, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(limit, 5_000e9, "Inbound limit should be set");
        assertEq(window, 1800, "Inbound window should be set");
        assertEq(inFlight, 0, "Inbound in-flight should remain zero");
    }

    function test_setInRateLimits_doesNotTouchOutRateLimits() external {
        (, uint256 outLimitBefore, uint32 outWindowBefore, ) = gateway.outRateLimits(
            NONCANONICAL_EID
        );

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            5_000e9,
            1800
        );
        vm.prank(bridgeRateLimiter);
        gateway.setInRateLimits(configs);

        (, uint256 outLimitAfter, uint32 outWindowAfter, ) = gateway.outRateLimits(
            NONCANONICAL_EID
        );
        assertEq(outLimitAfter, outLimitBefore, "Outbound limit must be unchanged");
        assertEq(outWindowAfter, outWindowBefore, "Outbound window must be unchanged");
    }

    function test_setInRateLimits_repeatedEntriesLastWins() external {
        IOffsettingRateLimiter.RateLimitConfig[]
            memory configs = new IOffsettingRateLimiter.RateLimitConfig[](2);
        configs[0] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 100e9,
            window: 60
        });
        configs[1] = IOffsettingRateLimiter.RateLimitConfig({
            eid: NONCANONICAL_EID,
            limit: 8_000e9,
            window: 3600
        });

        vm.prank(bridgeRateLimiter);
        gateway.setInRateLimits(configs);

        (, uint256 limit, uint32 window, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(limit, 8_000e9, "Last entry should dominate the final limit");
        assertEq(window, 3600, "Last entry should dominate the final window");
    }

    function _runSetInRateLimitsBy(address caller_) internal {
        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            5_000e9,
            1800
        );
        vm.prank(caller_);
        gateway.setInRateLimits(configs);

        (, uint256 limit, , ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(limit, 5_000e9, "Authorized caller should set the limit");
    }

    function test_setInRateLimits_adminCanCall() external {
        _runSetInRateLimitsBy(admin);
    }

    function test_setInRateLimits_bridgeAdminCanCall() external {
        _runSetInRateLimitsBy(bridgeAdmin);
    }

    function test_setInRateLimits_bridgeRateLimiterCanCall() external {
        _runSetInRateLimitsBy(bridgeRateLimiter);
    }

    /// @notice Inbound limits store any (limit, window) pair as configured.
    function testFuzz_setInRateLimits(uint256 limit_, uint32 window_) external {
        // Bound window to non-zero so the standard decay path is exercised
        window_ = uint32(bound(uint256(window_), 1, type(uint32).max));
        _setInRateLimit(gateway, NONCANONICAL_EID, limit_, window_);

        (, uint256 storedLimit, uint32 storedWindow, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(storedLimit, limit_, "Inbound limit should be stored as configured");
        assertEq(storedWindow, window_, "Inbound window should be stored as configured");
    }

    function testFuzz_setInRateLimits_revertsIfNotAuthorised(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin && caller_ != bridgeRateLimiter);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            5_000e9,
            1800
        );
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway.setInRateLimits(configs);
    }
}
