// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev Peer registration and removal.
contract LZBridgeGatewayTests_SetPeer is LZBridgeGatewayTestBase {
    function test_setPeer() external {
        bytes32 newPeer = LZConfigLib.addressToBytes32(makeAddr("newPeer"));

        vm.expectEmit(true, true, true, true);
        emit ILZBridgeGateway.PeerSet(uint32(42), newPeer);

        vm.prank(admin);
        gateway.setPeer(uint32(42), newPeer);

        assertEq(gateway.peers(uint32(42)), newPeer, "Peer should be set");
    }

    function test_setPeer_clears() external {
        assertTrue(
            gateway.peers(NONCANONICAL_EID) != bytes32(0),
            "Peer should be non-zero before clear"
        );

        vm.prank(admin);
        gateway.setPeer(NONCANONICAL_EID, bytes32(0));

        assertEq(gateway.peers(NONCANONICAL_EID), bytes32(0), "Peer should be cleared");
    }

    function testFuzz_setPeer_revertsIfNotAdmin(address caller_) external {
        vm.assume(caller_ != admin);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        gateway.setPeer(uint32(42), bytes32(uint256(1)));
    }
}
