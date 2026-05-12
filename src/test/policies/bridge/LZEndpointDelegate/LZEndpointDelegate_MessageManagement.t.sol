// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZEndpointDelegateTestBase} from "src/test/policies/bridge/LZEndpointDelegate/LZEndpointDelegateTestBase.sol";

// Interfaces
import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

/// @dev LZ V2 message management (skip, nilify, burn, clear) forwarded via LZEndpointDelegate.
///      Mock-based verification of the proxy: each external call must land on the LZ endpoint
///      with the gateway as the OApp argument and the caller-supplied recovery parameters,
///      plus role-gated access control. For end-to-end recovery scenarios against the real
///      mock EndpointV2 see the gateway-level recovery tests.
contract LZEndpointDelegateTests_MessageManagement is LZEndpointDelegateTestBase {
    bytes32 constant SENDER = bytes32(uint256(0x1234));
    uint64 constant NONCE = 7;
    bytes32 constant PAYLOAD_HASH = bytes32(uint256(0xABCDEF));

    // ========== SKIP ========== //

    function _test_skip(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
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
        lzDelegate.skip(CANONICAL_EID, SENDER, NONCE);
    }

    // ========== NILIFY ========== //

    function _test_nilify(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
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
        lzDelegate.nilify(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== BURN ========== //

    function _test_burn(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
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
        lzDelegate.burn(CANONICAL_EID, SENDER, NONCE, PAYLOAD_HASH);
    }

    // ========== CLEAR ========== //

    function _buildOrigin() private pure returns (Origin memory) {
        return Origin({srcEid: CANONICAL_EID, sender: SENDER, nonce: NONCE});
    }

    function _test_clear(address caller_) internal {
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
        vm.prank(caller_);
        lzDelegate.clear(origin, guid, message);
    }

    function test_clear_adminCanCall() external {
        _test_clear(admin);
    }

    function test_clear_bridgeAdminCanCall() external {
        _test_clear(bridgeAdmin);
    }

    function testFuzz_clear_revertsIfNotBridgeAdminOrAdmin(address caller_) external {
        vm.assume(caller_ != admin && caller_ != bridgeAdmin);

        Origin memory origin = _buildOrigin();
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        lzDelegate.clear(origin, bytes32(0), bytes(""));
    }
}
