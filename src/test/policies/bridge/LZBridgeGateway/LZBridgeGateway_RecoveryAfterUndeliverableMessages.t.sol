// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase_LZMessaging} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase_LZMessaging.sol";

// Interfaces
import {ILayerZeroEndpointV2, MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IMessagingChannel} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessagingChannel.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev Recovery from permanently undeliverable messages. Each test simulates
///      a misconfiguration or compromise that makes a message unrecoverable,
///      then demonstrates the cleanup procedure: clear/nilify/burn the stuck
///      message, correct bridgedSupply, and note user reimbursement.
contract LZBridgeGatewayTests_RecoveryAfterUndeliverableMessages is
    LZBridgeGatewayTestBase_LZMessaging
{
    // ========== WRONG DST PEER ON SOURCE ========== //

    /// @notice Source gateway has wrong dst peer. EndpointV2 reverts calling
    ///         lzReceive on the wrong address (no ILayerZeroReceiver).
    ///         Message can never be delivered. Recovery: fix peer, correct bridgedSupply, reimburse user.
    function test_scenario_wrongDstPeerSoMessageUndeliverable() external {
        // Set wrong dst peer on source (canonical)
        address wrongPeer = makeAddr("wrongPeer");
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, LZConfigLib.addressToBytes32(wrongPeer));

        // Send: OHM burned, bridgedSupply increased, message addressed to wrongPeer
        uint256 amount = 1000e9;
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

        // bridgedSupply increased on canonical
        assertEq(gateway.bridgedSupply(), amount, "bridgedSupply should increase");

        // Delivery attempt fails: wrongPeer does not implement ILayerZeroReceiver
        bytes32 wrongPeerB32 = LZConfigLib.addressToBytes32(wrongPeer);
        (bool success, ) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", NONCANONICAL_EID, wrongPeerB32)
        );
        assertFalse(success, "Delivery should fail (wrong receiver)");
        assertEq(ohm.balanceOf(recipient), 0, "Recipient should have no OHM");

        // Recovery: fix peer for future sends
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, LZConfigLib.addressToBytes32(address(gateway2)));

        // Recovery: correct bridgedSupply (OHM was burned but never minted on destination)
        uint256 currentSupply = gateway.bridgedSupply();
        vm.prank(bridgeAdmin);
        gateway.decreaseBridgedSupply(currentSupply);

        assertEq(gateway.bridgedSupply(), 0, "bridgedSupply should be corrected");

        // NOTE: The user's OHM was burned and never received on destination.
        // The protocol must reimburse the user (e.g., mint equivalent OHM).
    }

    // ========== COMPROMISED DVN HIDES PAYLOAD -> NILIFY -> BURN ========== //

    /// @notice Compromised DVN submits a fake hash and hides the original payload.
    ///         Delivery fails at EndpointV2._clearPayload() (hash mismatch). clear()
    ///         is impossible without the real payload. Admin nilifies, then burns.
    ///
    /// @dev burn does not require the original payload (unlike clear). burn requires
    ///      nonce <= lazyInboundNonce, so skip() advances the nonce first.
    function test_scenario_compromisedDVNSoNilifyAndBurn() external {
        // Build up bridgedSupply so verify path can initialize
        _sendCanonicalToNonCanonical(recipient, 2000e9);

        // 1. A message is sent from non-canonical
        bytes memory packetBytes = _sendNonCanonicalNoDeliver(1000e9);

        IMessagingChannel ep = _canonicalEndpoint();
        bytes32 peer = _nonCanonicalPeer();
        (uint32 srcEid, bytes32 senderAddr, ) = this.extractOrigin(packetBytes);
        address recvLib = _getReceiveLib(0, address(gateway), srcEid);

        // 2. Compromised DVN submits a fake hash (and hides the real payload)
        bytes32 fakeHash = keccak256("malicious payload");
        vm.prank(recvLib);
        ILayerZeroEndpointV2(address(endpointSetup.endpointList[0])).verify(
            Origin({srcEid: srcEid, sender: senderAddr, nonce: 1}),
            address(gateway),
            fakeHash
        );

        // 3. Admin cannot call clear() because the real payload is unknown.
        //    Admin nilifies the fake hash instead via the LZEndpointDelegate policy, which is the
        //    gateway's endpoint delegate.
        vm.prank(bridgeAdmin);
        lzDelegate.nilify(NONCANONICAL_EID, peer, 1, fakeHash);

        assertEq(
            ep.inboundPayloadHash(address(gateway), NONCANONICAL_EID, peer, 1),
            bytes32(type(uint256).max),
            "Hash should be NIL"
        );

        // 4. Advance lazyInboundNonce past nonce 1 (required for burn).
        //    inboundNonce() returns 1 (NIL hash counts as "verified" for nonce tracking).
        //    skip() requires nonce == inboundNonce + 1, so we skip nonce 2.
        vm.prank(bridgeAdmin);
        lzDelegate.skip(NONCANONICAL_EID, peer, 2);

        // 5. Burn the nilified nonce permanently (pass NIL hash as payloadHash)
        vm.prank(bridgeAdmin);
        lzDelegate.burn(NONCANONICAL_EID, peer, 1, bytes32(type(uint256).max));

        assertEq(
            ep.inboundPayloadHash(address(gateway), NONCANONICAL_EID, peer, 1),
            bytes32(0),
            "Hash should be deleted after burn"
        );

        // 6. Nonce is permanently consumed. Neither the real nor fake message can be delivered.
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail permanently after burn");

        // recipient only has OHM from setup, nothing from burned nonce
        assertEq(ohm.balanceOf(recipient), 2000e9, "Recipient should only have OHM from setup");

        // NOTE: If a legitimate user's OHM was burned on the non-canonical chain
        // (real message at the same nonce), the protocol must reimburse.
    }

    // ========== DISABLED OLD BRIDGE -> CLEAR + FIX PEER ========== //

    /// @notice Peer points to a disabled gateway. LZBridgeGateway.lzReceive()
    ///         reverts with NotEnabled (onlyEnabled modifier).
    ///         Recovery: admin clears from the old gateway (clear has no onlyEnabled
    ///         check), corrects bridgedSupply, reimburses user.
    function test_lzReceive_disabledOldBridgeSoClearAndFixPeer() external {
        uint256 amount = 1000e9;

        // 1. Disable destination gateway (simulates "old" bridge)
        vm.prank(admin);
        gateway2.disable(bytes(""));

        // 2. Send canonical -> non-canonical (message goes to disabled gateway2)
        bytes memory packetBytes = _sendCanonicalNoDeliver(amount);

        // 3. DVNs verify the message (hash stored even though gateway is disabled)
        _verifyOnly(packetBytes);

        // 4. Delivery fails: gateway2 is disabled (onlyEnabled modifier)
        bool delivered = _tryDeliverPacket(packetBytes);
        assertFalse(delivered, "Delivery should fail (gateway disabled)");

        // 5. Admin clears the message from the old gateway via the destination's delegate policy
        //    (clear works when disabled because it bypasses the gateway's `lzReceive`).
        (bytes32 guid, bytes memory message) = this.extractGuidAndMessage(packetBytes);
        (uint32 srcEid, bytes32 senderAddr, uint64 nonce) = this.extractOrigin(packetBytes);
        Origin memory origin = Origin({srcEid: srcEid, sender: senderAddr, nonce: nonce});

        vm.prank(bridgeAdmin);
        lzDelegate2.clear(origin, guid, message);

        // 6. Verify clear outcome: hash deleted, nonce advanced, no OHM minted
        IMessagingChannel ep = _nonCanonicalEndpoint();
        bytes32 peer = _canonicalPeer();

        assertEq(
            ep.inboundPayloadHash(address(gateway2), CANONICAL_EID, peer, 1),
            bytes32(0),
            "Hash should be empty after clear"
        );
        assertEq(
            ep.lazyInboundNonce(address(gateway2), CANONICAL_EID, peer),
            1,
            "Lazy nonce should advance"
        );
        assertEq(
            ohm.balanceOf(recipient),
            0,
            "Recipient should have no OHM (clear skips lzReceive)"
        );

        // 7. Correct bridgedSupply on canonical (send increased it, but receive never happened)
        assertEq(gateway.bridgedSupply(), amount, "bridgedSupply was increased by the send");
        vm.prank(bridgeAdmin);
        gateway.decreaseBridgedSupply(amount);
        assertEq(gateway.bridgedSupply(), 0, "bridgedSupply corrected");

        // NOTE: The user's OHM was burned on canonical but never minted on destination.
        // The protocol must reimburse the user (e.g., mint equivalent OHM).
        // For future sends: deploy new gateway, update peer on source via setPeer.
    }
}
