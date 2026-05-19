// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase_LZMessaging} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase_LZMessaging.sol";

// Interfaces
import {ILayerZeroEndpointV2, MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IMessagingChannel} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessagingChannel.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

// Contracts
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

/// @dev Retrying messages that failed due to fixable causes. Each test simulates
///      a transient or correctable failure (wrong peer, low supply, insufficient
///      gas, disabled bridge, desync'd approval), fixes the root cause, then
///      retries delivery and verifies the message is processed successfully.
contract LZBridgeGatewayTests_RetryingFailedMessages is LZBridgeGatewayTestBase_LZMessaging {
    // ========== WRONG SRC PEER ON DESTINATION ========== //

    /// @notice Destination has wrong src peer. EndpointV2.verify() fails because
    ///         gateway.allowInitializePath() returns false (peer mismatch).
    ///         Hash never stored. Recovery: fix peer, DVNs re-verify, deliver.
    function test_scenario_wrongSrcPeerSoFixPeerThenVerifyAndDeliver() external {
        // Set wrong src peer on destination (non-canonical)
        address wrongSrc = makeAddr("wrongSrc");
        vm.prank(admin);
        gateway2.setPeer(CANONICAL_EID, LZConfigLib.addressToBytes32(wrongSrc));

        // Send canonical -> non-canonical
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);

        // Verification fails: allowInitializePath returns false because peer is wrong.
        // The endpoint silently ignores the verify (hash NOT stored).
        // In production, DVN verification would not succeed until peer is fixed.
        _verifyOnly(packetBytes);

        // Confirm: hash is NOT stored (path not initialized)
        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();
        bytes32 hashBefore = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertEq(hashBefore, bytes32(0), "Hash should NOT be stored (path not initialized)");

        // Recovery step 1: fix peer to correct address
        vm.prank(admin);
        gateway2.setPeer(CANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway)));

        // Recovery step 2: DVNs re-verify (now allowInitializePath returns true)
        _verifyOnly(packetBytes);

        bytes32 hashAfter = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertTrue(hashAfter != bytes32(0), "Hash should be stored after re-verify");

        // Recovery step 3: deliver
        _manualDeliver(packetBytes, 1);

        assertEq(ohm.balanceOf(recipient), 1000e9, "Recipient should receive OHM after retry");
    }

    // ========== SUPPLY UNDERFLOW ========== //

    /// @notice Inbound on canonical: LZBridgeGateway._receiveBridgeOhm() reverts
    ///         on bridgedSupply underflow. Recovery: fix bridgedSupply, retry.
    function test_lzReceive_supplyUnderflowSoFixSupplyAndRetry() external {
        // bridgedSupply is 0, but someone sends from non-canonical to canonical
        bytes memory packetBytes = _sendNonCanonicalNoDeliver(1000e9);

        // Verify in endpoint (hash stored)
        _verifyOnly(packetBytes);

        // Delivery fails: bridgedSupply(0) - 1000e9 underflows
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail (underflow)");

        // Recovery: increase bridgedSupply (should have been 1000e9 or more)
        vm.prank(bridgeConfigurator);
        gateway.increaseBridgedSupply(1000e9);

        // Retry: succeeds now that bridgedSupply can absorb the decrement
        _manualDeliver(packetBytes, 0);

        assertEq(ohm.balanceOf(recipient), 1000e9, "Recipient should receive OHM after retry");
        assertEq(gateway.bridgedSupply(), 0, "bridgedSupply should be 0 after receive");
    }

    // ========== MINT APPROVAL DESYNC ========== //

    /// @notice Inbound on canonical: bridgedSupply check passes but OlympusMinter
    ///         reverts on mintOhm() because mintApproval was externally decreased
    ///         (invariant broken). Recovery: re-sync approval via decrease+increase, retry.
    function test_lzReceive_mintApprovalDesyncSoFixApprovalAndRetry() external {
        // Build up bridgedSupply + mintApproval via outflow
        _sendCanonicalToNonCanonical(recipient, 2000e9);
        assertEq(gateway.bridgedSupply(), 2000e9);
        assertEq(mintr.mintApproval(address(gateway)), 2000e9);

        // Break the invariant: externally decrease mintApproval
        // (simulates another policy or admin mistake calling MINTR directly)
        vm.prank(address(gateway));
        mintr.decreaseMintApproval(address(gateway), 1500e9);
        assertEq(mintr.mintApproval(address(gateway)), 500e9, "Approval desynchronized");

        // Inbound message: 1000e9
        bytes memory packetBytes = _sendNonCanonicalNoDeliver(1000e9);
        _verifyOnly(packetBytes);

        // Delivery fails: bridgedSupply(2000e9) >= 1000e9 passes,
        // but mintOhm(1000e9) reverts because mintApproval is only 500e9
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail (insufficient mint approval)");

        // Recovery: re-sync mintApproval via decrease+increase.
        // Decrease to 0 (clears approval), then increase back to force re-sync.
        uint256 currentSupply = gateway.bridgedSupply();
        vm.startPrank(bridgeConfigurator);
        gateway.decreaseBridgedSupply(currentSupply);
        gateway.increaseBridgedSupply(currentSupply);
        vm.stopPrank();

        assertEq(
            mintr.mintApproval(address(gateway)),
            currentSupply,
            "Approval should be re-synced"
        );

        // Retry: succeeds
        _manualDeliver(packetBytes, 0);

        // recipient: 2000e9 (setup) + 1000e9 (recovered)
        assertEq(ohm.balanceOf(recipient), 3000e9, "Recipient should receive OHM after retry");
        assertEq(gateway.bridgedSupply(), 1000e9, "bridgedSupply should decrease by inflow");
    }

    // ========== DISABLED BRIDGE -> RE-ENABLE -> RETRY ========== //

    /// @notice Destination gateway disabled. LZBridgeGateway.lzReceive() reverts
    ///         with ReceiveNotEnabled (isReceiveEnabled is false). Endpoint
    ///         _clearPayload rolls back, payload hash stays in storage. Re-enable
    ///         and retry succeeds.
    function test_lzReceive_disabledBridgeSoReEnableAndRetry() external {
        uint256 amount = 5000e9;

        // 1. Send from canonical (gateway enabled), packet enters mock queue
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

        // 2. Disable destination gateway before delivery
        vm.prank(admin);
        gateway2.disable(bytes(""));

        // 3. Attempt delivery fails (simulates executor catch)
        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway2));
        (bool success, ) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", NONCANONICAL_EID, dstAddr)
        );
        assertFalse(success, "Delivery should fail while disabled");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM yet");

        // 4. Re-enable destination gateway
        vm.prank(admin);
        gateway2.enable(bytes(""));

        // 5. Retry delivery succeeds
        verifyPackets(NONCANONICAL_EID, dstAddr);

        // 6. Assert message was delivered
        assertEq(ohm.balanceOf(recipient), amount, "Recipient should receive OHM after retry");
    }

    // ========== GATEWAY DISABLED -> SET RECEIVE ENABLED -> RETRY ========== //

    /// @notice Gateway disabled after send. lzReceive() reverts with
    ///         ReceiveNotEnabled. Admin sets isReceiveEnabled, retry succeeds.
    function test_lzReceive_gatewayDisabledSoSetReceiveEnabledAndRetry() external {
        // 1. Send from canonical, packet enters mock queue
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);

        // 2. Disable destination gateway (isReceiveEnabled becomes false)
        vm.prank(admin);
        gateway2.disable(bytes(""));
        assertFalse(gateway2.isReceiveEnabled(), "Receiving should be disabled");

        // 3. Verify packet in endpoint (hash stored)
        _verifyOnly(packetBytes);

        // 4. Delivery fails (isReceiveEnabled == false)
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail while receiving is disabled");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM yet");

        // 5. Admin enables receiving without re-enabling the gateway
        vm.prank(admin);
        gateway2.setIsReceiveEnabled(true);

        // 6. Retry delivery succeeds
        _manualDeliver(packetBytes, 1);

        assertEq(ohm.balanceOf(recipient), 1000e9, "Recipient should receive OHM after retry");
    }

    // ========== INSUFFICIENT GAS IN ENFORCED OPTIONS ========== //

    /// @notice Enforced options encode too little gas. EndpointV2.lzReceive() runs
    ///         out of gas within the executor's {gas: N} allocation.
    ///         Recovery: call endpoint.lzReceive() directly with sufficient gas
    ///         (enforced gas limit only restricts the executor, not direct calls).
    function test_scenario_insufficientGasSoManualRetryWithSufficientGas() external {
        // Set enforced options with very low gas (1000, way too low for lzReceive)
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: NONCANONICAL_EID,
            msgType: gateway.MSG_BRIDGE_OHM(),
            options: abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), uint128(1000))
        });
        vm.prank(admin);
        gateway.setEnforcedOptions(opts);

        // Send: options with 1000 gas are encoded in the packet
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);

        // Verify in endpoint (DVN verification is gas-independent)
        _verifyOnly(packetBytes);

        // Executor delivery: TestHelper.lzReceive passes gas:1000 -> OOG
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail (OOG from low gas)");

        // Recovery: call endpoint.lzReceive directly without gas limit.
        // The enforced options only affect the executor, not direct endpoint calls.
        _manualDeliver(packetBytes, 1);

        assertEq(
            ohm.balanceOf(recipient),
            1000e9,
            "Recipient should receive OHM after manual retry"
        );
    }

    // ========== INFLOW RATE LIMIT EXHAUSTED -> WAIT FOR DECAY -> RETRY ========== //

    /// @notice Two senders fill the destination's inbound capacity faster than the
    ///         window decays. The second user reads `receivable` while no inbound is
    ///         in flight (sees the full limit) and races to send; by the time their
    ///         message is delivered, the first user's message has already consumed
    ///         most of the capacity, so the second delivery reverts on `_inflow`.
    ///         Recovery: wait for the window to decay the in-flight amount, then retry.
    function test_lzReceive_inflowRateLimitSoWaitAndRetry() external {
        uint256 inLimit = 1_000e9;
        uint32 window = 3600;
        _setInRateLimit(gateway2, CANONICAL_EID, inLimit, window);

        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway2));

        // User 2 reads `receivable` first, seeing full capacity (no in-flight yet)
        (, uint256 user2InitialAvailable) = gateway2.receivable(CANONICAL_EID);
        assertEq(user2InitialAvailable, inLimit, "Initial inbound capacity should equal the limit");

        // Both users send within the same block; user 2 races on a stale read
        _sendCanonicalNoDeliver(800e9);
        _sendCanonicalNoDeliver(500e9);

        // Deliver only the first packet (FIFO order, popBack). It consumes 800e9 of
        // the 1000e9 inflow capacity.
        verifyPackets(NONCANONICAL_EID, dstAddr, 1, address(0), bytes(""));
        assertEq(ohm.balanceOf(recipient), 800e9, "User 1 should be delivered");
        (, uint256 availableAfterFirst) = gateway2.receivable(CANONICAL_EID);
        assertEq(availableAfterFirst, 200e9, "Only 200e9 should remain after the first delivery");

        // Try to deliver the second packet: reverts because 500e9 > 200e9 available
        (bool success, bytes memory returnData) = address(this).call(
            abi.encodeWithSignature(
                "verifyPackets(uint32,bytes32,uint256,address,bytes)",
                NONCANONICAL_EID,
                dstAddr,
                uint256(1),
                address(0),
                bytes("")
            )
        );
        assertFalse(success, "Second delivery should fail (inbound rate limit exhausted)");
        assertEq(
            returnData,
            abi.encodeWithSelector(IOffsettingRateLimiter.RateLimitExceeded.selector, 500e9, 200e9),
            "Revert reason should be RateLimitExceeded(500e9, 200e9)"
        );
        assertEq(ohm.balanceOf(recipient), 800e9, "User 2 not delivered yet");

        // Recovery: wait for the full window so the in-flight amount decays to zero
        skip(window);
        (, uint256 availableAfterDecay) = gateway2.receivable(CANONICAL_EID);
        assertEq(availableAfterDecay, inLimit, "Inbound capacity should be restored");

        // Retry user 2's packet: now succeeds
        verifyPackets(NONCANONICAL_EID, dstAddr, 1, address(0), bytes(""));
        assertEq(
            ohm.balanceOf(recipient),
            800e9 + 500e9,
            "Both users delivered after waiting the rate-limit window"
        );
    }

    // ========== INFLOW LIMIT TOO LOW FOR SEND -> RAISE LIMIT -> RETRY ========== //

    /// @notice Admin set the destination inflow limit lower than the source outflow
    ///         ceiling. The user's send passes outflow but the message exceeds the
    ///         full inflow limit (cannot decay through). Recovery: admin raises the
    ///         inflow limit to accommodate the message, then retry.
    function test_lzReceive_sendAmountGreaterThanFullInflowRateLimitSoCorrectLimitAndRetry()
        external
    {
        // Misconfiguration: destination inflow limit (100e9) is well below the source
        // outflow ceiling (default 1M), so a 500e9 send passes outflow but exceeds the
        // full inflow limit (decay alone cannot raise capacity above the limit).
        _setInRateLimit(gateway2, CANONICAL_EID, 100e9, 3600);

        // User sends 500e9 and the packet is queued
        bytes memory packet = _sendCanonicalNoDeliver(500e9);
        _verifyOnly(packet);

        // Delivery fails: 500e9 > 100e9 inflow capacity
        bool delivered = _tryDeliverPacket(packet);
        assertFalse(delivered, "Delivery should fail (inflow limit too low for this send)");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM yet");

        // Recovery: admin raises the inflow limit so the message can land
        _setInRateLimit(gateway2, CANONICAL_EID, 1_000e9, 3600);

        // Retry succeeds
        _manualDeliver(packet, 1);
        assertEq(ohm.balanceOf(recipient), 500e9, "Recipient should receive OHM after retry");
    }

    // ========== COMPROMISED DVN -> NILIFY -> HONEST DVN RE-VERIFY -> DELIVER ========== //

    /// @notice Compromised DVN submits a fake hash to EndpointV2. Delivery fails
    ///         at EndpointV2._clearPayload() with LZ_PayloadHashNotFound (fake hash
    ///         does not match the real payload). Admin nilifies, honest DVN re-verifies,
    ///         message delivered.
    ///
    /// @dev In the test, we call endpoint.verify() directly as the receive library
    ///      to simulate both compromised and honest DVN submissions. The ULN302 mock
    ///      caches DVN attestations (hashLookup), so we bypass the MessageLib path.
    function test_scenario_compromisedDVNSoNilifyAndReVerifyAndDeliver() external {
        // Build up bridgedSupply so inbound can succeed
        _sendCanonicalToNonCanonical(recipient, 2000e9);

        // 1. A legitimate message is sent from non-canonical
        bytes memory packetBytes = _sendNonCanonicalNoDeliver(1000e9);

        IMessagingChannel ep = _canonicalEndpoint();
        bytes32 peer = _nonCanonicalPeer();
        (uint32 srcEid, bytes32 senderAddr, ) = this.extractOrigin(packetBytes);
        address recvLib = _getReceiveLib(0, address(gateway), srcEid);

        // 2. Compromised DVN submits a FAKE hash to the endpoint
        bytes32 fakeHash = keccak256("malicious payload");
        vm.prank(recvLib);
        ILayerZeroEndpointV2(address(endpointSetup.endpointList[0])).verify(
            Origin({srcEid: srcEid, sender: senderAddr, nonce: 1}),
            address(gateway),
            fakeHash
        );

        bytes32 storedHash = ep.inboundPayloadHash(address(gateway), NONCANONICAL_EID, peer, 1);
        assertEq(storedHash, fakeHash, "Fake hash should be stored by compromised DVN");

        // 3. Admin detects the compromise and nilifies the fake hash via the LZEndpointDelegate
        //    policy, which is the gateway's endpoint delegate.
        vm.prank(bridgeAdmin);
        lzDelegate.nilify(NONCANONICAL_EID, peer, 1, fakeHash);

        bytes32 nilValue = ep.inboundPayloadHash(address(gateway), NONCANONICAL_EID, peer, 1);
        assertEq(nilValue, bytes32(type(uint256).max), "Hash should be NIL after nilify");

        // 4. Honest DVN re-verifies with the correct hash, overwriting NIL
        (bytes32 guid, bytes memory message) = this.extractGuidAndMessage(packetBytes);
        bytes32 realHash = keccak256(abi.encodePacked(guid, message));

        vm.prank(recvLib);
        ILayerZeroEndpointV2(address(endpointSetup.endpointList[0])).verify(
            Origin({srcEid: srcEid, sender: senderAddr, nonce: 1}),
            address(gateway),
            realHash
        );

        bytes32 restoredHash = ep.inboundPayloadHash(address(gateway), NONCANONICAL_EID, peer, 1);
        assertEq(restoredHash, realHash, "Real hash should overwrite NIL");

        // 5. Message delivered normally
        _manualDeliver(packetBytes, 0);

        // recipient: 2000e9 (setup) + 1000e9 (recovered message)
        assertEq(ohm.balanceOf(recipient), 3000e9, "Recipient should receive OHM");
        // bridgedSupply: 2000e9 (outflow) - 1000e9 (inflow) = 1000e9
        assertEq(gateway.bridgedSupply(), 1000e9, "bridgedSupply should decrease by inflow");
    }
}
