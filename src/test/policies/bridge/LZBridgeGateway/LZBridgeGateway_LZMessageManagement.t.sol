// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

/// @dev ILZEndpointV2Admin message management access control.
contract LZBridgeGatewayTests_LZMessageManagement is LZBridgeGatewayTestBase {
    function test_skip_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce
            )
        );
        vm.prank(bridgeAdmin);
        gateway.skip(NONCANONICAL_EID, sender, nonce);
    }

    function test_skip_adminCanCall() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "skip(address,uint32,bytes32,uint64)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce
            )
        );
        vm.prank(admin);
        gateway.skip(NONCANONICAL_EID, sender, nonce);
    }

    function test_skip_revertsIfNotBridgeAdminOrAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(user);
        gateway.skip(NONCANONICAL_EID, bytes32(uint256(1)), 1);
    }

    function test_nilify_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            )
        );
        vm.prank(bridgeAdmin);
        gateway.nilify(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_nilify_adminCanCall() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "nilify(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            )
        );
        vm.prank(admin);
        gateway.nilify(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_nilify_revertsIfNotBridgeAdminOrAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(user);
        gateway.nilify(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    function test_burn_proxiesToEndpoint() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            )
        );
        vm.prank(bridgeAdmin);
        gateway.burn(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_burn_adminCanCall() external {
        bytes32 sender = LZConfigLib.addressToBytes32(address(gateway2));
        uint64 nonce = 1;
        bytes32 payloadHash = keccak256("test");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "burn(address,uint32,bytes32,uint64,bytes32)",
                address(gateway),
                NONCANONICAL_EID,
                sender,
                nonce,
                payloadHash
            )
        );
        vm.prank(admin);
        gateway.burn(NONCANONICAL_EID, sender, nonce, payloadHash);
    }

    function test_burn_revertsIfNotBridgeAdminOrAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(user);
        gateway.burn(NONCANONICAL_EID, bytes32(uint256(1)), 1, bytes32(uint256(1)));
    }

    function test_clear_proxiesToEndpoint() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });
        bytes32 guid = bytes32(uint256(42));
        bytes memory message = bytes("test_message");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                address(gateway),
                origin,
                guid,
                message
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                address(gateway),
                origin,
                guid,
                message
            )
        );
        vm.prank(bridgeAdmin);
        gateway.clear(origin, guid, message);
    }

    function test_clear_adminCanCall() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: LZConfigLib.addressToBytes32(address(gateway2)),
            nonce: 1
        });
        bytes32 guid = bytes32(uint256(42));
        bytes memory message = bytes("test_message");
        address endpoint_ = gateway.LZ_ENDPOINT();

        vm.mockCall(
            endpoint_,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                address(gateway),
                origin,
                guid,
                message
            ),
            bytes("")
        );
        vm.expectCall(
            endpoint_,
            abi.encodeWithSignature(
                "clear(address,(uint32,bytes32,uint64),bytes32,bytes)",
                address(gateway),
                origin,
                guid,
                message
            )
        );
        vm.prank(admin);
        gateway.clear(origin, guid, message);
    }

    function test_clear_revertsIfNotBridgeAdminOrAdmin() external {
        Origin memory origin = Origin({
            srcEid: NONCANONICAL_EID,
            sender: bytes32(uint256(1)),
            nonce: 1
        });
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(user);
        gateway.clear(origin, bytes32(0), bytes(""));
    }
}
