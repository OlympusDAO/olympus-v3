// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev Inbound message handling (mint on receive).
contract LZBridgeGatewayTests_LzReceive is LZBridgeGatewayTestBase {
    function test_lzReceive_canonical_decrementsSupply() external {
        // 1. Preparation: bridge out first
        _sendCanonicalToNonCanonical(recipient, 5000e9);
        assertEq(gateway.bridgedSupply(), 5000e9, "Supply should be 5000e9 after send");

        // 2. Test: bridge back
        _sendNonCanonicalToCanonical(recipient, 2000e9);

        assertEq(gateway.bridgedSupply(), 3000e9, "Supply should decrease on receive");
        // Recipient got 5000e9 from first bridge + 2000e9 from second = 7000e9
        assertEq(ohm.balanceOf(recipient), 7000e9, "Recipient should have OHM from both bridges");
    }

    function test_lzReceive_nonCanonical_mintsWithoutSupplyTracking() external {
        _sendCanonicalToNonCanonical(recipient, 5000e9);

        assertEq(ohm.balanceOf(recipient), 5000e9, "Recipient should receive OHM");
        assertEq(gateway2.bridgedSupply(), 0, "Non-canonical should not track supply");
    }

    function test_lzReceive_revertsIfNotEndpoint() external {
        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(
            abi.encodeWithSelector(ILZBridgeGateway.LZBridgeGateway_OnlyEndpoint.selector)
        );
        vm.prank(user);
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

    function test_lzReceive_revertsIfNotEnabled() external {
        vm.prank(admin);
        gateway2.disable(bytes(""));

        Origin memory origin = Origin({
            srcEid: CANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway)),
            nonce: 1
        });

        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(address(endpointSetup.endpointList[1]));
        gateway2.lzReceive(origin, bytes32(0), bytes(""), address(0), bytes(""));
    }
}
