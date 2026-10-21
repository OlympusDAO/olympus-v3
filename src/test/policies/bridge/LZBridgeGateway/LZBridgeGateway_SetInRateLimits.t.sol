// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Setting inbound rate limits. Gated to the `bridge_configurator` role.
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

        vm.prank(bridgeConfigurator);
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
        vm.prank(bridgeConfigurator);
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

        vm.prank(bridgeConfigurator);
        gateway.setInRateLimits(configs);

        (, uint256 limit, uint32 window, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(limit, 8_000e9, "Last entry should dominate the final limit");
        assertEq(window, 3600, "Last entry should dominate the final window");
    }

    /// @notice Inbound limits store any (limit, window) pair as configured.
    function testFuzz_setInRateLimits(uint256 limit_, uint32 window_) external {
        window_ = uint32(bound(uint256(window_), 1, type(uint32).max));
        _setInRateLimit(gateway, NONCANONICAL_EID, limit_, window_);

        (, uint256 storedLimit, uint32 storedWindow, ) = gateway.inRateLimits(NONCANONICAL_EID);
        assertEq(storedLimit, limit_, "Inbound limit should be stored as configured");
        assertEq(storedWindow, window_, "Inbound window should be stored as configured");
    }

    function testFuzz_setInRateLimits_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            5_000e9,
            1800
        );
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.setInRateLimits(configs);
    }
}
