// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev Inbound message handling (mint on receive).
contract LZBridgeGatewayTests_LzReceive is LZBridgeGatewayTestBase {
    function test_lzReceive_canonical_decrementsSupply() external {
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

    function test_lzReceive_nonCanonical_mintsWithoutSupplyTracking() external {
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

        // Send from canonical — gateway2 should still receive
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

    function test_lzReceive_revertsIfSupplyUnderflow() external {
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

    // Note: since both `gateway.burnAndSend` and `LZCrossChainBridge` validate that the recipient
    // address is non-zero on the source side, reaching this branch would require either a bug
    // introduced in a future version of the gateway or facilitator or a fault on the LayerZero side.
    // This test exists as a defense-in-depth check on the receive path.
    function test_lzReceive_revertsIfRecipientIsZeroAddress() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });

        bytes memory payload = abi.encode(uint8(1), abi.encode(address(0), uint256(100e9)));

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_InvalidAddress.selector, "to")
        );
        vm.prank(address(endpointSetup.endpointList[0]));
        gateway.lzReceive(origin, bytes32(0), payload, address(0), bytes(""));
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
}
