// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Constants
import {BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @dev LZ V2 message management (skip, nilify, burn, clear) forwarded via LZEndpointDelegate.
///      Mock-based verification of the proxy: each external call must land on the LZ endpoint
///      with the gateway as the OApp argument and the caller-supplied recovery parameters,
///      plus role-gated access control. Every entry point is gated to `bridge_configurator`.
///      For end-to-end recovery scenarios against the real mock EndpointV2 see the
///      gateway-level recovery tests.
contract LZEndpointDelegateTests_MessageManagement is LZEndpointDelegateTestBase {
    bytes32 constant SENDER = bytes32(uint256(0x1234));
    uint64 constant NONCE = 7;
    bytes32 constant PAYLOAD_HASH = bytes32(uint256(0xABCDEF));

    // ========== SKIP ========== //

    function test_skip_bridgeConfiguratorCanCall() external {
        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    function testFuzz_skip_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    // ========== NILIFY ========== //

    function test_nilify_bridgeConfiguratorCanCall() external {
        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE,
                PAYLOAD_HASH
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE,
                PAYLOAD_HASH
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function testFuzz_nilify_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== BURN ========== //

    function test_burn_bridgeConfiguratorCanCall() external {
        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE,
                PAYLOAD_HASH
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                gateway,
                CANONICAL_EID,
                SENDER,
                NONCE,
                PAYLOAD_HASH
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    function testFuzz_burn_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== CLEAR ========== //

    function _buildOrigin() private pure returns (Origin memory) {
        return Origin({srcEid: CANONICAL_EID, sender: SENDER, nonce: NONCE});
    }

    function test_clear_bridgeConfiguratorCanCall() external {
        Origin memory origin = _buildOrigin();
        bytes32 guid = bytes32(uint256(0x55));
        bytes memory message = hex"deadbeef";

        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                gateway,
                origin,
                guid,
                message
            ),
            bytes("")
        );
        vm.expectCall(
            lzEndpoint,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                gateway,
                origin,
                guid,
                message
            )
        );
        vm.prank(bridgeConfigurator);
        lzDelegate.clear(origin, guid, message);
    }

    function testFuzz_clear_revertsIfNotBridgeConfigurator(address caller_) external {
        vm.assume(caller_ != bridgeConfigurator);

        Origin memory origin = _buildOrigin();
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BRIDGE_CONFIGURATOR_ROLE)
        );
        vm.prank(caller_);
        lzDelegate.clear(origin, bytes32(0), bytes(""));
    }
}
