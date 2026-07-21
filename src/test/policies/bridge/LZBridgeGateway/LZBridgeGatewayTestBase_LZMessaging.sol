// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILayerZeroEndpointV2, MessagingFee, Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IMessagingChannel} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessagingChannel.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";
import {PacketV1Codec} from "@lz-evm-protocol-v2-3.0.162/messagelib/libs/PacketV1Codec.sol";

/// @dev Shared helpers for LZ messaging tests that work with raw packets,
///      endpoint verification, and manual delivery against the real mock EndpointV2.
contract LZBridgeGatewayTestBase_LZMessaging is LZBridgeGatewayTestBase {
    using PacketV1Codec for bytes;

    // ========== SEND HELPERS ========== //

    /// @dev Sends canonical -> non-canonical, returns raw packet without delivering.
    function _sendCanonicalNoDeliver(uint256 amount_) internal returns (bytes memory packetBytes) {
        MessagingFee memory fee = gateway.estimateSendFee(
            NONCANONICAL_EID,
            recipient,
            amount_,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway), amount_);
        gateway.burnAndSend{value: fee.nativeFee}(
            NONCANONICAL_EID,
            recipient,
            amount_,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        packetBytes = getNextInflightPacket(
            uint16(NONCANONICAL_EID),
            LZConfigLib.addressToBytes32(address(gateway2))
        );
    }

    /// @dev Sends non-canonical -> canonical, returns raw packet without delivering.
    function _sendNonCanonicalNoDeliver(
        uint256 amount_
    ) internal returns (bytes memory packetBytes) {
        ohm.mint(facilitator, amount_);
        vm.deal(facilitator, 100 ether);

        MessagingFee memory fee = gateway2.estimateSendFee(
            CANONICAL_EID,
            recipient,
            amount_,
            bytes("")
        );
        vm.startPrank(facilitator);
        ohm.transfer(address(gateway2), amount_);
        gateway2.burnAndSend{value: fee.nativeFee}(
            CANONICAL_EID,
            recipient,
            amount_,
            payable(facilitator),
            bytes("")
        );
        vm.stopPrank();

        packetBytes = getNextInflightPacket(
            uint16(CANONICAL_EID),
            LZConfigLib.addressToBytes32(address(gateway))
        );
    }

    /// @dev Sends canonical -> non-canonical and verifies (stores hash) without delivering.
    function _sendAndVerify() internal returns (bytes memory packetBytes) {
        packetBytes = _sendCanonicalNoDeliver(1000e9);
        _verifyOnly(packetBytes);
    }

    // ========== VERIFY & DELIVER HELPERS ========== //

    /// @dev Verifies a packet in the destination endpoint (stores payload hash) without delivering.
    function _verifyOnly(bytes memory packetBytes_) internal {
        this.validatePacket(packetBytes_, bytes(""));
    }

    /// @dev Attempts delivery of a specific packet via TestHelper.lzReceive (respects gas from options).
    function _tryDeliverPacket(bytes memory packetBytes_) internal returns (bool success) {
        (bytes32 guid, ) = this.extractGuidAndMessage(packetBytes_);
        bytes memory options = optionsLookup[guid];
        (success, ) = address(this).call(
            abi.encodeWithSignature("lzReceive(bytes,bytes)", packetBytes_, options)
        );
    }

    /// @dev Attempts to deliver the next pending packet to non-canonical via verifyPackets.
    function _tryDeliverToNonCanonical() internal returns (bool success) {
        bytes32 dstAddr = LZConfigLib.addressToBytes32(address(gateway2));
        (success, ) = address(this).call(
            abi.encodeWithSignature("verifyPackets(uint32,bytes32)", NONCANONICAL_EID, dstAddr)
        );
    }

    /// @dev Delivers a packet by calling endpoint.lzReceive directly (no gas limit from options).
    function _manualDeliver(bytes memory packetBytes_, uint256 endpointIndex_) internal {
        (uint32 srcEid, bytes32 senderAddr, uint64 nonce) = this.extractOrigin(packetBytes_);
        (bytes32 guid, bytes memory message) = this.extractGuidAndMessage(packetBytes_);
        address receiver = this.extractReceiver(packetBytes_);

        Origin memory origin = Origin({srcEid: srcEid, sender: senderAddr, nonce: nonce});

        ILayerZeroEndpointV2(address(endpointSetup.endpointList[endpointIndex_])).lzReceive(
            origin,
            receiver,
            guid,
            message,
            bytes("")
        );
    }

    // ========== PACKET EXTRACTION HELPERS ========== //

    function extractOrigin(
        bytes calldata p_
    ) external pure returns (uint32 srcEid, bytes32 sender_, uint64 nonce) {
        srcEid = p_.srcEid();
        sender_ = p_.sender();
        nonce = p_.nonce();
    }

    function extractGuidAndMessage(
        bytes calldata p_
    ) external pure returns (bytes32 guid, bytes memory message) {
        guid = p_.guid();
        message = p_.message();
    }

    function extractReceiver(bytes calldata p_) external pure returns (address) {
        return p_.receiverB20();
    }

    // ========== ENDPOINT HELPERS ========== //

    function _canonicalEndpoint() internal view returns (IMessagingChannel) {
        return IMessagingChannel(address(endpointSetup.endpointList[0]));
    }

    function _nonCanonicalEndpoint() internal view returns (IMessagingChannel) {
        return IMessagingChannel(address(endpointSetup.endpointList[1]));
    }

    function _canonicalPeer() internal view returns (bytes32) {
        return LZConfigLib.addressToBytes32(address(gateway));
    }

    function _nonCanonicalPeer() internal view returns (bytes32) {
        return LZConfigLib.addressToBytes32(address(gateway2));
    }

    /// @dev Gets the registered receive library for a receiver on a given endpoint.
    function _getReceiveLib(
        uint256 endpointIndex_,
        address receiver_,
        uint32 srcEid_
    ) internal view returns (address) {
        (address lib, ) = ILayerZeroEndpointV2(address(endpointSetup.endpointList[endpointIndex_]))
            .getReceiveLibrary(receiver_, srcEid_);
        return lib;
    }
}
