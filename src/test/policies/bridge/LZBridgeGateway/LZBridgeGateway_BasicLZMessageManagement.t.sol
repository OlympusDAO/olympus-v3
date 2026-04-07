// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase_LZMessaging} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase_LZMessaging.sol";

// Interfaces
import {IMessagingChannel} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessagingChannel.sol";
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev LZ V2 message management tests (skip, nilify, burn, clear).
///      Tests cover outcome verification against the real mock EndpointV2
///      (payload hash, nonce, deliverability) and access control (admin
///      role, unauthorized caller revert). For realistic recovery scenarios
///      with specific failure causes, see LZBridgeGateway_RecoveryAfterUndeliverableMessages.t.sol
///      and LZBridgeGateway_RetryingFailedMessages.t.sol.
contract LZBridgeGatewayTests_BasicLZMessageManagement is LZBridgeGatewayTestBase_LZMessaging {
    // ========== SKIP ========== //

    /// @notice skip() advances the lazy nonce past an unverified nonce.
    ///         A message sent at the skipped nonce can never be verified or delivered.
    function test_skip_preventsVerificationAndDelivery() external {
        // 1. Send a message (nonce 1 queued, not yet verified in endpoint)
        _sendCanonicalNoDeliver(1000e9);

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        // 2. Skip nonce 1 before DVN verification
        vm.prank(bridgeAdmin);
        gateway2.skip(CANONICAL_EID, peer, 1);

        assertEq(
            ep.lazyInboundNonce(address(gateway2), CANONICAL_EID, peer),
            1,
            "Lazy nonce should advance to 1"
        );

        // 3. Attempt delivery: verifyPackets tries to verify+deliver nonce 1,
        //    but nonce 1 was already consumed by skip, so verification fails
        bool delivered = _tryDeliverToNonCanonical();
        assertFalse(delivered, "Delivery should fail for skipped nonce");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM");
    }

    function _test_skip(address caller_) internal {
        bytes32 peer = _canonicalPeer();

        vm.prank(caller_);
        gateway2.skip(CANONICAL_EID, peer, 1);

        assertEq(
            _nonCanonicalEndpoint().lazyInboundNonce(address(gateway2), CANONICAL_EID, peer),
            1,
            "Lazy nonce should advance"
        );
    }

    function test_skip_adminCanCall() external {
        _test_skip(admin);
    }

    function test_skip_bridgeAdminCanCall() external {
        _test_skip(bridgeAdmin);
    }

    function testFuzz_skip_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway2.skip(CANONICAL_EID, bytes32(uint256(1)), 1);
    }

    // ========== NILIFY ========== //

    /// @notice nilify() replaces a verified payload hash with NIL, preventing delivery.
    ///         Design intent: invalidate a fake hash submitted by a compromised DVN.
    ///         Here we test the mechanic in isolation (hash replacement + delivery block).
    function test_nilify_preventsDeliveryOfVerifiedMessage() external {
        // 1. Send and verify (DVN confirms the message)
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);
        _verifyOnly(packetBytes);

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        bytes32 hashBefore = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertTrue(hashBefore != bytes32(0), "Payload hash should be set after verify");

        // 2. Admin nilifies the verified message
        vm.prank(bridgeAdmin);
        gateway2.nilify(CANONICAL_EID, peer, 1, hashBefore);

        bytes32 hashAfter = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertEq(hashAfter, bytes32(type(uint256).max), "Payload hash should be NIL");

        // 3. Attempt delivery: hash mismatch (NIL != real hash) causes revert
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail after nilify");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM");
    }

    function _test_nilify(address caller_) internal {
        bytes memory packetBytes = _sendAndVerify();

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();
        bytes32 hash = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);

        vm.prank(caller_);
        gateway2.nilify(CANONICAL_EID, peer, 1, hash);

        assertEq(
            ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1),
            bytes32(type(uint256).max),
            "Hash should be NIL"
        );
    }

    function test_nilify_adminCanCall() external {
        _test_nilify(admin);
    }

    function test_nilify_bridgeAdminCanCall() external {
        _test_nilify(bridgeAdmin);
    }

    function testFuzz_nilify_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway2.nilify(CANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    // ========== BURN ========== //

    /// @notice burn() permanently deletes a nilified payload hash.
    ///         Design intent: destroy a nonce when a compromised DVN hides the payload,
    ///         making clear() impossible. burn does not require the original payload.
    ///         Flow: verify -> nilify -> skip(nonce+1) to advance lazy nonce -> burn.
    function test_burn_permanentlyDeletesPayloadHash() external {
        // 1. Send and verify
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);
        _verifyOnly(packetBytes);

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        bytes32 payloadHash = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertTrue(payloadHash != bytes32(0), "Payload hash should be set");

        // 2. Nilify (invalidate the hash, replacing with NIL)
        vm.prank(bridgeAdmin);
        gateway2.nilify(CANONICAL_EID, peer, 1, payloadHash);

        // 3. Advance lazyInboundNonce past nonce 1 (burn requires nonce <= lazyInboundNonce).
        //    inboundNonce() returns 1 (NIL hash counts as "verified" for nonce tracking).
        //    skip() requires nonce == inboundNonce + 1, so we skip nonce 2.
        vm.prank(bridgeAdmin);
        gateway2.skip(CANONICAL_EID, peer, 2);

        // 4. Burn the nilified nonce (pass NIL hash as payloadHash)
        vm.prank(bridgeAdmin);
        gateway2.burn(CANONICAL_EID, peer, 1, bytes32(type(uint256).max));

        // 5. Payload hash permanently deleted
        bytes32 hashAfter = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertEq(hashAfter, bytes32(0), "Payload hash should be empty after burn");

        // 6. Delivery impossible: hash deleted, nothing to match
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail after burn");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM");
    }

    function _test_burn(address caller_) internal {
        bytes memory packetBytes = _sendAndVerify();

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();
        bytes32 hash = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);

        // nilify first, then advance nonce, then burn
        vm.startPrank(caller_);
        gateway2.nilify(CANONICAL_EID, peer, 1, hash);
        gateway2.skip(CANONICAL_EID, peer, 2);
        gateway2.burn(CANONICAL_EID, peer, 1, bytes32(type(uint256).max));
        vm.stopPrank();

        assertEq(
            ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1),
            bytes32(0),
            "Hash should be deleted"
        );
    }

    function test_burn_adminCanCall() external {
        _test_burn(admin);
    }

    function test_burn_bridgeAdminCanCall() external {
        _test_burn(bridgeAdmin);
    }

    function testFuzz_burn_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway2.burn(CANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    // ========== CLEAR ========== //

    /// @notice clear() consumes a verified message without executing lzReceive.
    ///         The nonce advances and the hash is deleted, but no OHM is minted.
    function test_clear_consumesMessageWithoutExecution() external {
        // 1. Send and verify
        bytes memory packetBytes = _sendCanonicalNoDeliver(1000e9);
        _verifyOnly(packetBytes);

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        bytes32 hashBefore = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertTrue(hashBefore != bytes32(0), "Payload hash should be set after verify");

        // 2. Clear the message (consume without executing)
        (bytes32 guid, bytes memory message) = this.extractGuidAndMessage(packetBytes);
        (uint32 srcEid, bytes32 senderAddr, uint64 nonce) = this.extractOrigin(packetBytes);
        Origin memory origin = Origin({srcEid: srcEid, sender: senderAddr, nonce: nonce});

        vm.prank(bridgeAdmin);
        gateway2.clear(origin, guid, message);

        // 3. Payload hash deleted, nonce advanced
        bytes32 hashAfter = ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1);
        assertEq(hashAfter, bytes32(0), "Payload hash should be empty after clear");

        uint64 nonceAfter = ep.lazyInboundNonce(address(gateway2), CANONICAL_EID, peer);
        assertEq(nonceAfter, 1, "Lazy nonce should advance to 1 after clear");

        // 4. OHM was NOT minted (clear does not call lzReceive)
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM after clear");

        // 5. Re-delivery also fails (hash already deleted)
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Re-delivery should fail after clear");
    }

    function _test_clear(address caller_) internal {
        bytes memory packetBytes = _sendAndVerify();

        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        (uint32 srcEid, bytes32 senderAddr, uint64 nonce) = this.extractOrigin(packetBytes);
        (bytes32 guid, bytes memory message) = this.extractGuidAndMessage(packetBytes);
        Origin memory origin = Origin({srcEid: srcEid, sender: senderAddr, nonce: nonce});

        vm.prank(caller_);
        gateway2.clear(origin, guid, message);

        assertEq(
            ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1),
            bytes32(0),
            "Hash should be deleted"
        );
        assertEq(
            ep.lazyInboundNonce(address(gateway2), CANONICAL_EID, peer),
            1,
            "Lazy nonce should advance"
        );
    }

    function test_clear_adminCanCall() external {
        _test_clear(admin);
    }

    function test_clear_bridgeAdminCanCall() external {
        _test_clear(bridgeAdmin);
    }

    function testFuzz_clear_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: bytes32(uint256(1)),
            nonce: 1
        });
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        gateway2.clear(origin, bytes32(0), bytes(""));
    }
}
