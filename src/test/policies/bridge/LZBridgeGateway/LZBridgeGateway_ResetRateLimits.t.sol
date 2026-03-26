// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Libraries
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Emergency rate limit reset.
contract LZBridgeGatewayTests_ResetRateLimits is LZBridgeGatewayTestBase {
    function test_resetRateLimits() external {
        // Configure rate limit
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 1_000e9,
            window: 3600
        });
        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);

        // Use up the full limit
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1_000e9,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1_000e9);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1_000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Verify limit is exhausted
        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 0, "Should be exhausted");

        // Reset
        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectEmit(true, true, true, true);
        emit RateLimiter.RateLimitsReset(eids);

        vm.prank(bridgeAdmin);
        gateway.resetRateLimits(eids);

        // amountInFlight should be 0, full limit available
        (uint192 amountInFlight, , uint192 limit, uint64 window) = gateway.rateLimits(
            NONCANONICAL_EID
        );
        assertEq(amountInFlight, 0, "amountInFlight should be reset");
        assertEq(limit, 1_000e9, "Limit should be preserved");
        assertEq(window, 3600, "Window should be preserved");

        (, canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 1_000e9, "Full limit should be available after reset");
    }

    function test_resetRateLimits_revertsIfNotBridgeAdmin() external {
        uint32[] memory eids = new uint32[](1);
        eids[0] = NONCANONICAL_EID;

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("bridge_admin"))
        );
        vm.prank(user);
        gateway.resetRateLimits(eids);
    }
}
