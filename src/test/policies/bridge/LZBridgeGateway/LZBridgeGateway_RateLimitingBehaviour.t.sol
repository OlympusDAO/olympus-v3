// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";

/// @dev Rate limiting behaviour on burnAndSend (outflow).
contract LZBridgeGatewayTests_RateLimitingBehaviour is LZBridgeGatewayTestBase {
    // ========== FUZZ TESTS ========== //

    /// @notice Any limit/window combination is accepted and stored correctly.
    function testFuzz_burnAndSend_rateLimitStored(uint192 limit_, uint64 window_) external {
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: limit_,
            window: window_
        });

        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);

        (, , uint192 storedLimit, uint64 storedWindow) = gateway.rateLimits(NONCANONICAL_EID);
        assertEq(storedLimit, limit_, "Limit should match");
        assertEq(storedWindow, window_, "Window should match");
    }

    /// @notice With limit > 0 and window > 0, burnAndSend up to limit succeeds
    ///         and burnAndSend beyond limit reverts.
    function testFuzz_burnAndSend_rateLimitEnforced(uint192 limit_, uint64 window_) external {
        // Constrain to usable values: limit fits in OHM supply, window > 0
        vm.assume(limit_ > 0 && limit_ <= 100_000e9);
        vm.assume(window_ >= 60 && window_ <= 365 days);

        _setRateLimit(NONCANONICAL_EID, limit_, window_);

        // Mint enough OHM
        ohm.mint(facilitator, uint256(limit_) + 1);
        vm.deal(facilitator, 100 ether);

        // Send exactly the limit — should succeed
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            limit_,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), limit_);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            limit_,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Send 1 more — should revert (no capacity left)
        fee = gateway.estimateSendFee(NONCANONICAL_EID, recipient, 1, bytes(""));
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    // ========== ZERO LIMIT TESTS ========== //

    /// @notice limit=0, window=0 means unconfigured — burnAndSend is not rate-limited.
    function test_burnAndSend_unconfiguredRateLimit_noRestriction() external {
        // Default state: no rate limit configured
        (, , uint192 limit, uint64 window) = gateway.rateLimits(NONCANONICAL_EID);
        assertEq(limit, 0, "Default limit should be 0");
        assertEq(window, 0, "Default window should be 0");

        // Large outflow succeeds (gateway's _outflow override skips when limit=0 && window=0)
        _sendCanonicalToNonCanonical(recipient, 50_000e9);
        assertEq(ohm.balanceOf(recipient), 50_000e9, "Should send without rate limit");
    }

    /// @notice limit=0, window>0 blocks all burnAndSend (amountCanBeSent is always 0).
    function test_burnAndSend_zeroLimitNonZeroWindow_blocksAll() external {
        _setRateLimit(NONCANONICAL_EID, 0, 3600);

        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 0, "No amount should be sendable with zero limit");

        // Even 1 OHM should be rejected
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    /// @notice Setting limit and window back to 0 disables rate limiting on burnAndSend.
    function test_burnAndSend_disableRateLimitBySettingBothToZero() external {
        // Enable rate limit
        _setRateLimit(NONCANONICAL_EID, 1_000e9, 3600);

        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 1_000e9, "Should have 1000e9 capacity");

        // Disable rate limit by setting both to 0
        _setRateLimit(NONCANONICAL_EID, 0, 0);

        // Large outflow succeeds (skip path in gateway's _outflow override)
        _sendCanonicalToNonCanonical(recipient, 50_000e9);
        assertEq(ohm.balanceOf(recipient), 50_000e9, "Should send without rate limit");
    }

    // ========== DECAY & RECOVERY ========== //

    /// @notice Linear decay restores partial capacity mid-window.
    ///         After half the window, half the limit is available for burnAndSend again.
    function test_burnAndSend_linearDecayRestoresCapacityMidWindow() external {
        uint192 limit = 10_000e9;
        uint64 window = 3600;
        _setRateLimit(NONCANONICAL_EID, limit, window);

        // Exhaust the full limit
        _sendCanonicalToNonCanonical(recipient, limit);

        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 0, "No capacity after exhausting limit");

        // Advance halfway — linear decay restores half
        skip(window / 2);

        (, canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, uint256(limit) / 2, "Half capacity should be restored mid-window");

        // Send half the limit — succeeds
        uint256 halfLimit = uint256(limit) / 2;
        ohm.mint(facilitator, halfLimit);
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            halfLimit,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), halfLimit);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            halfLimit,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // 1 more reverts — capacity exhausted again
        ohm.mint(facilitator, 1);
        fee = gateway.estimateSendFee(NONCANONICAL_EID, recipient, 1, bytes(""));
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }
}
