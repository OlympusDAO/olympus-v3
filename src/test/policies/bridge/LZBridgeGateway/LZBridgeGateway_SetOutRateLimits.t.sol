// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Setting outbound rate limits. Gated to the `bridge_configurator` role.
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

        vm.prank(bridgeConfigurator);
        gateway.setOutRateLimits(configs);

        (uint256 inFlight, uint256 limit, uint32 window, ) = gateway.outRateLimits(
            NONCANONICAL_EID
        );
        assertEq(limit, 10_000e9, "Outbound limit should be set");
        assertEq(window, 3600, "Outbound window should be set");
        assertEq(inFlight, 0, "Outbound in-flight should remain zero");
    }

    function test_setOutRateLimits_doesNotTouchInRateLimits() external {
        (, uint256 inLimitBefore, uint32 inWindowBefore, ) = gateway.inRateLimits(NONCANONICAL_EID);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );
        vm.prank(bridgeConfigurator);
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

        vm.prank(bridgeConfigurator);
        gateway.setOutRateLimits(configs);

        (, uint256 limit, uint32 window, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(limit, 9_000e9, "Last entry should dominate the final limit");
        assertEq(window, 7200, "Last entry should dominate the final window");
    }

    /// @notice Outbound rate limits store any (limit, window) pair as configured.
    function testFuzz_setOutRateLimits(uint256 limit_, uint32 window_) external {
        window_ = uint32(bound(uint256(window_), 1, type(uint32).max));
        _setOutRateLimit(gateway, NONCANONICAL_EID, limit_, window_);

        (, uint256 storedLimit, uint32 storedWindow, ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(storedLimit, limit_, "Outbound limit should be stored as configured");
        assertEq(storedWindow, window_, "Outbound window should be stored as configured");
    }

    function testFuzz_setOutRateLimits_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        IOffsettingRateLimiter.RateLimitConfig[] memory configs = _buildConfigs(
            NONCANONICAL_EID,
            10_000e9,
            3600
        );
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        gateway.setOutRateLimits(configs);
    }
}
