// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev Public view function verification.
contract LZBridgeGatewayTests_View is LZBridgeGatewayTestBase {
    function test_allowInitializePath_validPeer() external view {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertTrue(gateway.allowInitializePath(origin), "Should allow valid peer");
    }

    function test_allowInitializePath_noPeer() external view {
        Origin memory origin = Origin({
            srcEid: uint32(42),
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 0
        });
        assertFalse(gateway.allowInitializePath(origin), "Should not allow unknown peer");
    }

    function test_allowInitializePath_clearedPeerRejectsZeroSender() external {
        // Clear peer so peers[NONCANONICAL_EID] == bytes32(0)
        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        // origin.sender == bytes32(0) would match the cleared slot without the fix
        Origin memory origin = Origin({srcEid: NONCANONICAL_EID, sender: bytes32(0), nonce: 0});
        assertFalse(gateway.allowInitializePath(origin), "Cleared peer must not match zero sender");
    }

    function test_nextNonce_returnsZero() external view {
        assertEq(
            gateway.nextNonce(NONCANONICAL_EID, bytes32(0)),
            0,
            "Should return 0 (unordered messaging)"
        );
    }

    function test_LZ_ENDPOINT() external view {
        assertEq(
            gateway.LZ_ENDPOINT(),
            address(endpointSetup.endpointList[0]),
            "LZ_ENDPOINT should match endpoint"
        );
    }

    function test_IS_CANONICAL() external view {
        assertTrue(gateway.IS_CANONICAL(), "Canonical gateway should return true");
        assertFalse(gateway2.IS_CANONICAL(), "Non-canonical gateway should return false");
    }

    function test_MINTR() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should match deployed module");
    }

    function test_ohm() external view {
        assertEq(gateway.ohm(), address(ohm), "OHM should match token address");
    }

    function test_bridgedSupply() external view {
        assertEq(gateway.bridgedSupply(), 0, "Bridged supply should be zero initially");
    }

    function test_MSG_BRIDGE_OHM() external view {
        assertEq(gateway.MSG_BRIDGE_OHM(), 1, "MSG_BRIDGE_OHM should be 1");
    }

    function test_peers() external view {
        assertEq(
            gateway.peers(NONCANONICAL_EID),
            LZConfigLib.addressToBytes32(address(gateway2)),
            "Peer should match non-canonical gateway"
        );
    }

    function test_isReceiveEnabled_defaultsFalse() external view {
        assertFalse(gateway.isReceiveEnabled(), "isReceiveEnabled should default to false");
    }

    function test_getAmountCanBeSent() external {
        // Configure rate limit: 10_000e9 over 1 hour
        uint192 limit = 10_000e9;
        uint64 window = 1 hours;
        _setRateLimit(NONCANONICAL_EID, limit, window);

        (uint256 currentInFlight, uint256 canSend) = gateway.getAmountCanBeSent(NONCANONICAL_EID);
        assertEq(currentInFlight, 0, "No amount should be in flight initially");
        assertEq(canSend, limit, "Full limit should be available");
    }
}
