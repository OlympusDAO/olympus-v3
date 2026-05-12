// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee, MessagingReceipt} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";

// Contracts
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Outbound OHM bridging (burn + LZ send).
contract LZBridgeGatewayTests_BurnAndSend is LZBridgeGatewayTestBase {
    function test_burnAndSend_canonical() external {
        uint256 amount = 1000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        uint256 facilitatorEthBefore = facilitator.balance;

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.BridgedSupplyIncreased(amount);

        vm.expectEmit(true, true, true, false);
        emit ILZBridgeGateway.Sent(facilitator, amount, NONCANONICAL_EID, bytes32(0));

        MessagingReceipt memory receipt = gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        assertEq(
            receipt.fee.nativeFee,
            fee.nativeFee,
            "Receipt native fee should match estimated fee"
        );
        assertEq(receipt.fee.lzTokenFee, 0, "Receipt should have no lzToken fee");
        assertTrue(receipt.guid != bytes32(0), "Receipt guid should be non-zero");

        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator balance should decrease by amount"
        );
        assertEq(ohm.balanceOf(address(gateway)), 0, "Gateway should have no OHM after burn");
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should increase by amount");
        // Canonical outflow pre-funds mint approval for future inflow
        assertEq(
            mintr.mintApproval(address(gateway)),
            amount,
            "Mint approval should equal bridged supply after outflow"
        );
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee.nativeFee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway).balance, 0, "Gateway should hold no ETH after send");
    }

    function test_burnAndSend_nonCanonical_burnsWithoutSupplyTracking() external {
        // 1. Preparation: first bridge to non-canonical so facilitator has OHM there
        _sendCanonicalToNonCanonical(facilitator, 5000e9);

        uint256 amount = 1000e9;
        uint256 facilitatorBalanceBefore = ohm.balanceOf(facilitator);

        MessagingFee memory fee = gateway2.estimateSendFee(
            CANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        // 2. Test: send from non-canonical back to canonical
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount);

        uint256 facilitatorEthBefore = facilitator.balance;

        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track supply");
        // Non-canonical outflow does not pre-fund mint approval
        assertEq(
            mintr2.mintApproval(address(gateway2)),
            0,
            "Non-canonical outflow should not change mint approval"
        );
        assertEq(
            ohm.balanceOf(facilitator),
            facilitatorBalanceBefore - amount,
            "Facilitator balance should decrease by amount"
        );
        assertEq(ohm.balanceOf(address(gateway2)), 0, "Gateway2 should have no OHM after burn");
        assertEq(
            facilitator.balance,
            facilitatorEthBefore - fee.nativeFee,
            "Facilitator should spend exactly the native fee"
        );
        assertEq(address(gateway2).balance, 0, "Gateway2 should hold no ETH after send");
    }

    function test_burnAndSend_refundsExcessEth() external {
        uint256 amount = 1000e9;
        address payable refundAddr = payable(makeAddr("refundReceiver"));

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        uint256 excess = 5 ether;
        uint256 totalSent = fee.nativeFee + excess;

        uint256 refundBalanceBefore = refundAddr.balance;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        MessagingReceipt memory receipt = gateway.burnAndSend{value: totalSent}(
            NONCANONICAL_EID,
            recipient,
            amount,
            refundAddr,
            bytes("")
        );
        vm.stopPrank();

        // Receipt records the actual fee charged, not the excess msg.value.
        assertEq(receipt.fee.nativeFee, fee.nativeFee, "Receipt should report actual fee charged");
        assertLt(
            receipt.fee.nativeFee,
            totalSent,
            "Receipt fee must be less than totalSent when overpaying"
        );

        uint256 refundReceived = refundAddr.balance - refundBalanceBefore;
        // Refund should be approximately the excess (minus any rounding)
        assertGe(refundReceived, excess - 0.01 ether, "Refund should return most of the excess");
        assertLe(refundReceived, totalSent, "Refund should not exceed total sent");
    }

    function test_burnAndSend_withExtraOptions() external {
        uint256 amount = 1000e9;

        // Extra Type 3 options: add 100K more lzReceive gas on top of enforced 200K
        bytes memory extraOptions = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(100_000)
        );

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            extraOptions
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            extraOptions
        );
        vm.stopPrank();

        // Deliver packet: should succeed with combined options
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        assertEq(ohm.balanceOf(recipient), amount, "Recipient should receive OHM");
        assertEq(gateway.bridgedSupply(), amount, "Bridged supply should increase");
    }

    function test_burnAndSend_skipsUnconfiguredRateLimits() external {
        // No rate limit configured on either gateway
        (, , uint192 limit, uint64 window) = gateway.rateLimits(NONCANONICAL_EID);
        assertEq(limit, 0, "Limit should be 0");
        assertEq(window, 0, "Window should be 0");

        // Outflow succeeds
        _sendCanonicalToNonCanonical(recipient, 1000e9);

        // Inflow succeeds
        vm.prank(recipient);
        ohm.transfer(facilitator, 1000e9);
        _sendNonCanonicalToCanonical(recipient, 1000e9);
    }

    function test_burnAndSend_canonical_inflowRateLimit() external {
        // Set rate limit on canonical for both directions
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });
        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);

        // Send some out
        _sendCanonicalToNonCanonical(recipient, 5000e9);

        (uint256 inFlight, ) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 5000e9, "5000e9 should be in flight");

        // Bridge back: _inflow(NONCANONICAL_EID) reduces amountInFlight for the same key
        _sendNonCanonicalToCanonical(recipient, 2000e9);

        (inFlight, ) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 3000e9, "Inflow should reduce in-flight");
    }

    function test_burnAndSend_nonCanonical_inflowSkipsWhenAmountInFlightZero() external {
        // Configure rate limit on non-canonical gateway for inbound from canonical
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: CANONICAL_EID,
            limit: 10_000e9,
            window: 3600
        });
        vm.prank(bridgeAdmin);
        gateway2.setRateLimits(configs);

        // No outflow from gateway2: amountInFlight for CANONICAL_EID is 0
        (uint192 amountInFlight, , , ) = gateway2.rateLimits(CANONICAL_EID);
        assertEq(amountInFlight, 0, "amountInFlight should be 0 before inflow");

        // Send from canonical to non-canonical: gateway2 receives, _inflow hits amountInFlight == 0
        _sendCanonicalToNonCanonical(recipient, 1000e9);

        // amountInFlight remains 0: the _inflow override skipped the write
        (amountInFlight, , , ) = gateway2.rateLimits(CANONICAL_EID);
        assertEq(amountInFlight, 0, "amountInFlight should remain 0 after skipped inflow");

        // Full outflow capacity on gateway2 is still available
        (, uint256 canSend) = gateway2.getAmountCanBeSent(CANONICAL_EID);
        assertEq(canSend, 10_000e9, "Full outflow capacity should be available");
    }

    function test_burnAndSend_canonical_outflowRateLimit() external {
        // Set rate limit on canonical
        RateLimiter.RateLimitConfig[] memory configs = new RateLimiter.RateLimitConfig[](1);
        configs[0] = RateLimiter.RateLimitConfig({
            dstEid: NONCANONICAL_EID,
            limit: 5_000e9,
            window: 3600
        });
        vm.prank(bridgeAdmin);
        gateway.setRateLimits(configs);

        // Send within limit succeeds
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            3_000e9,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 3_000e9);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            3_000e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        (uint256 inFlight, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(inFlight, 3_000e9, "3000e9 should be in flight");
        assertEq(canSend, 2_000e9, "2000e9 should remain");

        // Send exceeding remaining limit reverts
        ohm.mint(facilitator, 2_001e9);
        fee = gateway.estimateSendFee(NONCANONICAL_EID, recipient, 2_001e9, bytes(""));
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 2_001e9);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            2_001e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    /// @notice Outflow rate limit blocks burnAndSend, but succeeds after the window elapses.
    function test_burnAndSend_outflowRateLimitSoRetryAfterWindowElapsed() external {
        // Set tight rate limit: 5000 OHM per hour
        uint192 limit = 5_000e9;
        uint64 window = 3600;
        _setRateLimit(NONCANONICAL_EID, limit, window);

        // Send up to the limit
        uint256 firstAmount = 5_000e9;
        _sendCanonicalToNonCanonical(recipient, firstAmount);

        (, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(canSend, 0, "No capacity remaining");

        // Attempt to send more, reverts
        uint256 retryAmount = 1_000e9;
        ohm.mint(facilitator, retryAmount);
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            retryAmount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), retryAmount);
        vm.expectRevert(abi.encodeWithSelector(RateLimiter.RateLimitExceeded.selector));
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            retryAmount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Wait for rate limit window to fully elapse
        skip(window);

        // Retry, succeeds
        fee = gateway.estimateSendFee(NONCANONICAL_EID, recipient, retryAmount, bytes(""));
        vm.startPrank(facilitator);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            retryAmount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        // Deliver
        verifyPackets(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));
        assertEq(
            ohm.balanceOf(recipient),
            firstAmount + retryAmount,
            "Recipient should receive OHM from both sends"
        );
    }

    function test_burnAndSend_revertsIfEnforcedOptionsLackExecutorGas() external {
        // Override enforced options to Type 3 prefix only (no executor lzReceive entry).
        // The LZ endpoint executor rejects options without a gas specification.
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: abi.encodePacked(uint16(3))
        });
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);

        uint256 amount = 1000e9;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        // endpoint.send() reverts because the options contain no executor gas entry.
        // The entire burnAndSend reverts atomically (OHM burn is also rolled back).
        vm.expectRevert(abi.encodeWithSignature("Executor_NoOptions()"));
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfInsufficientFee() external {
        uint256 amount = 1000e9;
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);

        // Send less ETH than required fee, so the endpoint reverts with LZ_InsufficientFee
        vm.expectRevert(
            abi.encodeWithSignature(
                "LZ_InsufficientFee(uint256,uint256,uint256,uint256)",
                fee.nativeFee,
                fee.nativeFee / 2,
                0,
                0
            )
        );
        gateway.burnAndSend{value: fee.nativeFee / 2}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfZeroRecipient() external {
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            address(0),
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfNoPeer() external {
        // Clear peer
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_NoPeer.selector,
                NONCANONICAL_EID
            )
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfSameEID() external {
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NoPeer.selector, CANONICAL_EID)
        );
        gateway.burnAndSend{value: 1 ether}(
            CANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfUnconfiguredEID() external {
        uint32 unknownEid = 999;

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NoPeer.selector, unknownEid)
        );
        gateway.burnAndSend{value: 1 ether}(
            unknownEid,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfInsufficientOhmBalance() external {
        uint256 amount = 1000e9;
        uint256 transferAmount = 500e9;

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        // Transfer less OHM than specified in burnAndSend
        ohm.transfer(address(gateway), transferAmount);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway.disable(bytes(""));

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function test_burnAndSend_revertsIfBridgeDisabledAndReceiveEnabled() external {
        vm.startPrank(admin);
        gateway.disable(bytes(""));
        gateway.setIsReceiveEnabled(true);
        vm.stopPrank();

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 100e9);

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();
    }

    function testFuzz_burnAndSend_revertsIfNotBridgeFacilitator(address caller_) external {
        vm.assume(caller_ != facilitator);

        vm.deal(caller_, 10 ether);
        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                bytes32("bridge_facilitator")
            )
        );
        gateway.burnAndSend{value: 1 ether}(
            NONCANONICAL_EID,
            recipient,
            100e9,
            payable(caller_),
            bytes("")
        );
    }
}
