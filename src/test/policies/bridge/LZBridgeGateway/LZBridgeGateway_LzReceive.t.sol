// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IOffsettingRateLimiter} from "src/interfaces/IOffsettingRateLimiter.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev Inbound message handling (mint on receive).
contract LZBridgeGatewayTests_LzReceive is LZBridgeGatewayTestBase {
    function test_lzReceive_decrementsSupplyOnCanonical() external {
        // 1. Preparation: bridge out first
        _sendCanonicalToNonCanonical(recipient, 5000e9);
        assertEq(gateway.bridgedSupply(), 5000e9, "Supply should be 5000e9 after send");
        // Outflow pre-funded mint approval = 5000e9
        assertEq(
            mintr.mintApproval(address(gateway)),
            5000e9,
            "Mint approval should equal bridged supply after outflow"
        );

        // 2. Test: bridge back
        _sendNonCanonicalToCanonical(recipient, 2000e9);

        assertEq(gateway.bridgedSupply(), 3000e9, "Supply should decrease on receive");
        // Canonical inflow consumed 2000e9 from pre-funded approval
        // 5000e9 (outflow) - 2000e9 (inflow mint) = 3000e9
        assertEq(
            mintr.mintApproval(address(gateway)),
            3000e9,
            "Mint approval should decrease by inflow amount"
        );
        // Recipient got 5000e9 from first bridge + 2000e9 from second = 7000e9
        assertEq(ohm.balanceOf(recipient), 7000e9, "Recipient should have OHM from both bridges");
    }

    function test_lzReceive_mintsWithoutSupplyTrackingOnNonCanonical() external {
        _sendCanonicalToNonCanonical(recipient, 5000e9);

        assertEq(ohm.balanceOf(recipient), 5000e9, "Recipient should receive OHM");
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track supply");
        // Non-canonical uses JIT: approval is fully consumed each mint, so remains 0
        assertEq(
            mintr2.mintApproval(address(gateway2)),
            0,
            "Non-canonical JIT approval should be fully consumed"
        );
    }

    function test_lzReceive_succeedsWhenBridgeDisabledButReceiveEnabled() external {
        // Disable gateway2 but allow receiving
        vm.startPrank(admin);
        gateway2.disable(bytes(""));
        gateway2.setIsReceiveEnabled(true);
        vm.stopPrank();

        assertFalse(gateway2.isEnabled(), "isEnabled should be false");
        assertTrue(gateway2.isReceiveEnabled(), "isReceiveEnabled should be true");

        // Send from canonical, gateway2 should still receive
        _sendCanonicalToNonCanonical(recipient, 1000e9);

        assertEq(ohm.balanceOf(recipient), 1000e9, "Recipient should receive OHM despite disabled");
    }

    function test_lzReceive_succeedsAfterBridgeDisableAndReceiveEnable() external {
        vm.startPrank(admin);
        gateway2.disable(bytes(""));
        gateway2.setIsReceiveEnabled(true);
        gateway2.enable(bytes(""));
        vm.stopPrank();

        assertTrue(gateway2.isReceiveEnabled(), "isReceiveEnabled should be true after re-enable");

        _sendCanonicalToNonCanonical(recipient, 1000e9);

        assertEq(ohm.balanceOf(recipient), 1000e9, "Recipient should receive OHM");
    }

    /// @notice Inbound delivery larger than the counterpart outbound in-flight clamps
    ///         the outbound in-flight to zero without emitting any auxiliary event.
    function test_lzReceive_offsetsOutboundAndInflowClampsAtZeroOnNonCanonical() external {
        // Bootstrap bridgedSupply on canonical so the later non-canonical -> canonical
        // delivery does not underflow.
        _sendCanonicalToNonCanonical(recipient, 1_000e9);

        // Prime the outbound side on gateway2 with a small amount
        ohm.mint(facilitator, 100e9);
        _sendNonCanonicalToCanonical(recipient, 100e9);

        (uint256 outInFlight, , , ) = gateway2.outRateLimits(CANONICAL_EID);
        assertEq(outInFlight, 100e9, "Outbound in-flight on gateway2 should be primed");

        // Deliver canonical -> non-canonical with 500e9: the inflow tries to credit
        // the outbound counterpart by 500e9, which is greater than the current 100e9
        // in-flight, so the outbound is clamped at zero.
        _sendCanonicalToNonCanonical(recipient, 500e9);

        (outInFlight, , , ) = gateway2.outRateLimits(CANONICAL_EID);
        assertEq(outInFlight, 0, "Outbound in-flight should be clamped to zero");
    }

    /// @notice A partial offset reduces the counterpart in-flight by exactly the delta.
    function test_lzReceive_offsetsOutboundPartiallyOnNonCanonical() external {
        // Bootstrap bridgedSupply on canonical for the later inbound from non-canonical
        _sendCanonicalToNonCanonical(recipient, 1_000e9);

        ohm.mint(facilitator, 500e9);
        _sendNonCanonicalToCanonical(recipient, 500e9);
        (uint256 outInFlight, , , ) = gateway2.outRateLimits(CANONICAL_EID);
        assertEq(outInFlight, 500e9, "Outbound in-flight on gateway2 should be primed to 500e9");

        // 300e9 inflow from canonical clamps outbound by exactly 300e9
        _sendCanonicalToNonCanonical(recipient, 300e9);

        (outInFlight, , , ) = gateway2.outRateLimits(CANONICAL_EID);
        assertEq(outInFlight, 200e9, "Outbound in-flight should drop to 200e9");
    }

    function test_lzReceive_revertsIfWrongPeer() external {
        address wrongSender = makeAddr("wrongSender");
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(wrongSender),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_OnlyPeer.selector,
                CANONICAL_EID,
                LZConfigLib.addressToBytes32(wrongSender)
            )
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfInvalidMessageType() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // Encode an invalid message type
        bytes memory invalidPayload = abi.encode(uint8(99), abi.encode(recipient, uint256(100e9)));

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidMessageType.selector, 99)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), invalidPayload, address(0), bytes(""));
    }

    /// @notice Inbound delivery exceeding the non-canonical inbound rate limit reverts in
    ///         `lzReceive`.
    /// @dev `verifyPackets` makes several internal `this.*` calls before the actual
    ///      delivery, so `vm.expectRevert` can be consumed by an earlier non-reverting
    ///      call. We instead invoke `verifyPackets` via low-level call (which captures
    ///      both the success flag and the raw returndata), and assert on the returndata.
    function test_lzReceive_revertsIfExceedingInLimitOnNonCanonical() external {
        _setInRateLimit(gateway2, CANONICAL_EID, 100e9, 3600);

        uint256 amount = 500e9;
        ohm.mint(facilitator, amount);
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway2));
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", NONCANONICAL_EID, dstAddr)
        );
        assertFalse(success, "verifyPackets should fail when inbound limit is exceeded");
        assertEq(
            returnData,
            abi.encodeWithSelector(
                IOffsettingRateLimiter.RateLimitExceeded.selector,
                amount,
                100e9
            ),
            "Revert reason must match RateLimitExceeded(amount, available)"
        );
    }

    /// @notice Inbound delivery exceeding the canonical inbound rate limit reverts in
    ///         `lzReceive`.
    function test_lzReceive_revertsIfExceedingInLimitOnCanonical() external {
        // Bootstrap canonical bridgedSupply so the inbound has supply to decrement
        // before the rate-limit check trips.
        _sendCanonicalToNonCanonical(recipient, 5_000e9);

        _setInRateLimit(gateway, NONCANONICAL_EID, 100e9, 3600);

        uint256 amount = 500e9;
        ohm.mint(facilitator, amount);
        MessagingFee memory fee = gateway2.estimateSendFee(
            CANONICAL_EID,
            recipient,
            amount,
            bytes("")
        );

        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount);
        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            recipient,
            amount,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway));
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", CANONICAL_EID, dstAddr)
        );
        assertFalse(success, "verifyPackets should fail when canonical inbound limit is exceeded");
        assertEq(
            returnData,
            abi.encodeWithSelector(
                IOffsettingRateLimiter.RateLimitExceeded.selector,
                amount,
                100e9
            ),
            "Revert reason must match RateLimitExceeded(amount, available)"
        );
    }

    /// @notice An inbound limit of zero on canonical blocks every lzReceive, including 1 wei.
    function test_lzReceive_revertsIfZeroInLimitOnCanonical() external {
        // Bootstrap canonical bridgedSupply so the inbound supply check passes
        _sendCanonicalToNonCanonical(recipient, 1_000e9);

        _setInRateLimit(gateway, NONCANONICAL_EID, 0, 3600);

        ohm.mint(facilitator, 1);
        MessagingFee memory fee = gateway2.estimateSendFee(CANONICAL_EID, recipient, 1, bytes(""));
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), 1);
        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            recipient,
            1,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway));
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", CANONICAL_EID, dstAddr)
        );
        assertFalse(success, "verifyPackets should fail when canonical inbound limit is zero");
        assertEq(
            returnData,
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
    }

    /// @notice An inbound limit of zero on non-canonical blocks every lzReceive, including 1 wei.
    function test_lzReceive_revertsIfZeroInLimitOnNonCanonical() external {
        _setInRateLimit(gateway2, CANONICAL_EID, 0, 3600);

        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            1,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), 1);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            1,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway2));
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", NONCANONICAL_EID, dstAddr)
        );
        assertFalse(success, "verifyPackets should fail when non-canonical inbound limit is zero");
        assertEq(
            returnData,
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 1, 0)
        );
    }

    /// @notice Inbound delivery on canonical larger than the counterpart outbound
    ///         in-flight clamps the outbound in-flight to zero.
    function test_lzReceive_offsetsOutboundAndInflowClampsAtZeroOnCanonical() external {
        // Prime canonical outbound at a small value (and seed bridgedSupply by 100e9)
        _sendCanonicalToNonCanonical(recipient, 100e9);

        (uint256 outInFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(outInFlight, 100e9, "Canonical outbound in-flight should be primed at 100e9");

        // Add extra bridgedSupply so the later inbound (500e9) does not underflow.
        // increaseBridgedSupply does not touch outRateLimits, preserving the 100e9 prime.
        vm.prank(admin);
        gateway.increaseBridgedSupply(400e9);

        // Receive 500e9 from non-canonical: the inflow clamps canonical outbound to zero
        ohm.mint(facilitator, 500e9);
        _sendNonCanonicalToCanonical(recipient, 500e9);

        (outInFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(outInFlight, 0, "Canonical outbound in-flight should be clamped to zero");
    }

    /// @notice A partial inbound on canonical reduces the counterpart outbound in-flight by
    ///         exactly the delta.
    function test_lzReceive_offsetsOutboundPartiallyOnCanonical() external {
        // Prime canonical outbound at 500e9 (and bridgedSupply at 500e9 in the same call)
        _sendCanonicalToNonCanonical(recipient, 500e9);

        (uint256 outInFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(outInFlight, 500e9, "Canonical outbound in-flight should be primed at 500e9");

        // Receive 300e9 from non-canonical: canonical outbound drops by exactly 300e9
        ohm.mint(facilitator, 300e9);
        _sendNonCanonicalToCanonical(recipient, 300e9);

        (outInFlight, , , ) = gateway.outRateLimits(NONCANONICAL_EID);
        assertEq(outInFlight, 200e9, "Canonical outbound in-flight should drop to 200e9");
    }

    function test_lzReceive_revertsIfSupplyUnderflowOnCanonical() external {
        // Don't bridge out first, so bridgedSupply = 0
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });

        bytes memory payload = abi.encode(uint8(1), abi.encode(recipient, uint256(100e9)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILZBridgeGateway.LZBridgeGateway_BridgedSupplyUnderflow.selector,
                0,
                100e9
            )
        );
        vm.prank(address(endpointSetup.endpointList[0]));
        gateway.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfEmptyPayload() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfMalformedOuterPayload() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // 64 bytes: too short for ABI-encoded (uint8, bytes) which needs >= 96
        bytes memory malformed = abi.encode(uint256(1), uint256(2));

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), malformed, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfPayloadDataTooShort() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // msgType=1 but inner data is only 32 bytes (address only, missing uint256 amount)
        bytes memory shortData = abi.encode(recipient);
        bytes memory payload = abi.encode(uint8(1), shortData);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfPayloadDataTooLong() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        // msgType=1 but inner data is 96 bytes (extra word appended)
        bytes memory longData = abi.encode(recipient, uint256(100e9), uint256(0));
        bytes memory payload = abi.encode(uint8(1), longData);

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidPayload.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
    }

    function test_lzReceive_revertsIfPeerCleared() external {
        // Clear peer so peers[CANONICAL_EID] == bytes32(0)
        vm.prank(admin);
        gateway2.setPeer(CANONICAL_EID, bytes32(0));

        // origin.sender == bytes32(0) would match the cleared slot without the fix
        Origin memory origin = Origin({srcEid: CANONICAL_EID, sender: bytes32(0), nonce: 1});

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_NoPeer.selector, CANONICAL_EID)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function test_lzReceive_revertsIfBridgeDisabledAndReceiveEnabledFalse() external {
        vm.prank(admin);
        gateway2.disable(bytes(""));

        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_ReceiveNotEnabled.selector)
        );
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }

    function testFuzz_lzReceive_revertsIfNotEndpoint(address caller_) external {
        vm.assume(caller_ != address(endpointSetup.endpointList[1]));

        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyEndpoint.selector)
        );
        vm.prank(caller_);
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }
}
